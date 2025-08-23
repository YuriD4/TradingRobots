//+------------------------------------------------------------------+
//|                                            TrendChangeSimple.mq5 |
//|                                    Copyright 2023, TradingRobots |
//|                                             https://www.example.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, TradingRobots"
#property link      "https://www.example.com"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include "TrendChangeSimpleConfig.mqh"
#include "TrendChangeSimpleUtils.mqh"
#include "TradingOperationsSimple.mqh"
#include "RangeManager.mqh"

// Входные параметры
input int      InpMagicNumber = 234567;          // Уникальный идентификатор советника
input double   InpLotSize = 0.01;                // Базовый размер лота
input int      InpBreakoutPoints = 10;           // Количество пунктов для пробоя диапазона
input int      InpStopLossPoints = 20;           // Фиксированный стоп-лосс в пунктах
input double   InpTakeProfitMultiplier = 2.0;    // Множитель тейк-профита относительно стоп-лосса
input int      InpMaxReversals = 3;              // Максимальное количество разворотов
input double   InpLotScalingFactor = 1.0;        // Коэффициент увеличения лота при развороте
input int      InpTradingStartHour = 0;          // Начало торговли (часы)
input int      InpTradingEndHour = 23;           // Окончание торговли (часы)
input bool     InpDebugMode = true;              // Режим отладки

// Глобальные объекты
CTrade                          trade;                    // Объект для торговых операций
CTrendChangeSimpleConfig*       config;                  // Конфигурация робота
CTrendChangeSimpleUtils*        utils;                   // Вспомогательные функции
CTradingOperationsSimple*       tradingOps;              // Торговые операции
CRangeManager*                  rangeManager;            // Менеджер диапазонов

// Состояние системы
enum SYSTEM_STATE
{
    STATE_LOOKING_FOR_SIGNAL,    // Ищем сигнал от диапазона
    STATE_POSITION_OPEN,         // Позиция открыта
    STATE_BLOCKED_UNTIL_TOMORROW // Заблокировано до завтра (после TP)
};

// Глобальные переменные состояния
SYSTEM_STATE                   systemState = STATE_LOOKING_FOR_SIGNAL;
datetime                       lastBarTime = 0;
datetime                       lastBlockedDay = 0;
bool                          trailingStopActivated = false;

// Переменные для отслеживания пробоев диапазона
bool                          upBreakoutDetected = false;
bool                          downBreakoutDetected = false;
double                        upBreakoutPrice = 0.0;
double                        downBreakoutPrice = 0.0;

// Переменные для системы разворотов
int                           currentReversalCount = 0;
double                        currentLotSize = 0.0;
ENUM_POSITION_TYPE            lastTradeDirection = WRONG_VALUE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    if(InpDebugMode)
        Print("DEBUG: *** INITIALIZING TREND CHANGE SIMPLE ***");
        
    // Создаем объекты конфигурации
    config = new CTrendChangeSimpleConfig(
        InpMagicNumber,
        InpLotSize,
        InpBreakoutPoints,
        InpStopLossPoints,
        InpTakeProfitMultiplier,
        InpMaxReversals,
        InpLotScalingFactor,
        InpTradingStartHour,
        InpTradingEndHour,
        InpDebugMode
    );
    
    // Создаем вспомогательные объекты
    utils = new CTrendChangeSimpleUtils(_Symbol, config.DebugMode());
    tradingOps = new CTradingOperationsSimple(_Symbol, config.MagicNumber(), GetPointer(trade), config.DebugMode());
    rangeManager = new CRangeManager(_Symbol, utils, config.DebugMode());
    
    // Настраиваем торговый объект
    trade.SetExpertMagicNumber(config.MagicNumber());
    trade.SetMarginMode();
    trade.SetTypeFillingBySymbol(_Symbol);
    trade.SetDeviationInPoints(10);
    
    // Инициализируем систему
    ResetSystem();
    
    if(config.DebugMode())
    {
        Print("DEBUG: System reset completed. Reversals: ", currentReversalCount,
              ", Lot: ", currentLotSize,
              ", Last direction: ", EnumToString(lastTradeDirection));
    }
    
    // Пытаемся определить направление последней открытой позиции
    if(tradingOps.HasOpenPosition())
    {
        lastTradeDirection = tradingOps.GetCurrentPositionType();
        systemState = STATE_POSITION_OPEN;
        if(config.DebugMode())
            Print("DEBUG: Found open position with direction: ", EnumToString(lastTradeDirection));
    }
    else
    {
        if(config.DebugMode())
            Print("DEBUG: No open position found");
            
        // Проверяем, не заблокирована ли система сегодня
        datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
        if(lastBlockedDay == currentDay && systemState == STATE_BLOCKED_UNTIL_TOMORROW)
        {
            if(config.DebugMode())
                Print("DEBUG: System is blocked until tomorrow");
        }
        else
        {
            // Сбросим блокировку, если день сменился
            if(lastBlockedDay != currentDay && systemState == STATE_BLOCKED_UNTIL_TOMORROW)
            {
                if(config.DebugMode())
                    Print("DEBUG: Day changed, unblocking system");
                systemState = STATE_LOOKING_FOR_SIGNAL;
                ResetSystem();
            }
        }
    }
    
    if(config.DebugMode())
    {
        Print("DEBUG: TrendChangeSimple initialized. State: ", EnumToString(systemState),
              ", Reversals: ", currentReversalCount,
              ", Lot: ", currentLotSize,
              ", Last direction: ", EnumToString(lastTradeDirection));
    }
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(reason == REASON_REMOVE || reason == REASON_PROGRAM || reason == REASON_CLOSE)
    {
        tradingOps.CloseAllPositions();
    }
    
    if(CheckPointer(config) == POINTER_DYNAMIC) delete config;
    if(CheckPointer(utils) == POINTER_DYNAMIC) delete utils;
    if(CheckPointer(tradingOps) == POINTER_DYNAMIC) delete tradingOps;
    if(CheckPointer(rangeManager) == POINTER_DYNAMIC) delete rangeManager;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!utils.IsTradingTimeAllowed(config.TradingStartHour(), config.TradingEndHour()))
        return;
    
    // Проверяем новый бар
    datetime currentBarTime = iTime(_Symbol, _Period, 1);
    bool isNewBar = (currentBarTime != lastBarTime);
    if(isNewBar)
    {
        lastBarTime = currentBarTime;
        CheckNewDay();
    }
    
    // Обновляем диапазон только при новом баре
    if(isNewBar)
    {
        if(!rangeManager.UpdateRange())
        {
            if(config.DebugMode())
                Print("DEBUG: Range not available");
            return;
        }
    }
    
    // Основная логика в зависимости от состояния системы
    switch(systemState)
    {
        case STATE_LOOKING_FOR_SIGNAL:
            ProcessSignalSearch();
            break;
            
        case STATE_POSITION_OPEN:
            ProcessOpenPosition();
            break;
            
        case STATE_BLOCKED_UNTIL_TOMORROW:
            // Ничего не делаем, ждем смены дня
            break;
    }
}

//+------------------------------------------------------------------+
//| Функция поиска сигнала для входа                                 |
//+------------------------------------------------------------------+
void ProcessSignalSearch()
{
    // Если система заблокирована до завтра, не ищем сигналы
    if(systemState == STATE_BLOCKED_UNTIL_TOMORROW)
        return;
        
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double rangeHigh = rangeManager.GetRangeHigh();
    double rangeLow = rangeManager.GetRangeLow();
    double breakoutDistance = utils.PointsToPrice(config.BreakoutPoints());
    double onePoint = utils.PointsToPrice(1);
    
    // 1. Обнаружение пробоя ВНИЗ
    if(!downBreakoutDetected && currentPrice < (rangeLow - breakoutDistance))
    {
        downBreakoutDetected = true;
        downBreakoutPrice = currentPrice;
        
        if(config.DebugMode())
            Print("DEBUG: DOWN breakout detected at ", currentPrice);
    }
    
    // 2. Обнаружение пробоя ВВЕРХ  
    if(!upBreakoutDetected && currentPrice > (rangeHigh + breakoutDistance))
    {
        upBreakoutDetected = true;
        upBreakoutPrice = currentPrice;
        
        if(config.DebugMode())
            Print("DEBUG: UP breakout detected at ", currentPrice);
    }
    
    // 3. Возврат после пробоя ВНИЗ → сигнал BUY
    if(downBreakoutDetected && currentPrice >= (rangeLow + onePoint))
    {
        if(config.DebugMode())
            Print("DEBUG: Return after DOWN breakout → Opening BUY");
            
        OpenBuyPosition();
        ResetBreakoutFlags();
        systemState = STATE_POSITION_OPEN;
        return; // Важно: выходим после открытия позиции
    }
    
    // 4. Возврат после пробоя ВВЕРХ → сигнал SELL
    if(upBreakoutDetected && currentPrice <= (rangeHigh - onePoint))
    {
        if(config.DebugMode())
            Print("DEBUG: Return after UP breakout → Opening SELL");
            
        OpenSellPosition();
        ResetBreakoutFlags();
        systemState = STATE_POSITION_OPEN;
        return; // Важно: выходим после открытия позиции
    }
}

//+------------------------------------------------------------------+
//| Функция обработки открытой позиции                               |
//+------------------------------------------------------------------+
void ProcessOpenPosition()
{
    // Проверяем, есть ли еще открытая позиция
    bool hasPosition = tradingOps.HasOpenPosition();
    
    if(config.DebugMode())
    {
        if(!hasPosition)
        {
            Print("DEBUG: No open position detected → Processing closed position");
        }
    }
    
    if(!hasPosition)
    {
        // Позиция закрыта → анализируем результат
        ProcessClosedPosition();
        return;
    }
    
    // Управляем трейлинг-стопом только если это не реверсная сделка
    ulong ticket = tradingOps.GetCurrentPositionTicket();
    if(ticket != 0 && !trailingStopActivated && currentReversalCount == 0)
        CheckTrailingStop(ticket);
}

//+------------------------------------------------------------------+
//| КЛЮЧЕВАЯ функция обработки закрытой позиции                      |
//+------------------------------------------------------------------+
void ProcessClosedPosition()
{
    // Получаем информацию о последней сделке
    int dealReason = tradingOps.GetLastTradeReason();
    double profit = 0.0;
    bool hasResult = tradingOps.GetLastTradeResult(profit);
    
    if(config.DebugMode())
    {
        string reasonStr = "UNKNOWN";
        if(dealReason == DEAL_REASON_SL) reasonStr = "SL";
        else if(dealReason == DEAL_REASON_TP) reasonStr = "TP";
        else if(dealReason == DEAL_REASON_CLIENT) reasonStr = "CLIENT";
        else if(dealReason == DEAL_REASON_EXPERT) reasonStr = "EXPERT";
        else if(dealReason == DEAL_REASON_SO) reasonStr = "SO";
        
        Print("DEBUG: Position closed. Reason: ", reasonStr, " (", dealReason, ")",
              ", Profit: ", profit,
              ", Reversals: ", currentReversalCount,
              ", Last direction: ", EnumToString(lastTradeDirection));
    }
    
    // Определяем причину закрытия сделки
    // Считаем стоп-лоссом: DEAL_REASON_SL и DEAL_REASON_SO
    bool isStopLoss = (dealReason == DEAL_REASON_SL || dealReason == DEAL_REASON_SO);
    bool isTakeProfit = (dealReason == DEAL_REASON_TP);
    
    // Если не можем определить по DEAL_REASON, используем profit
    if(dealReason == -1 || dealReason == DEAL_REASON_CLIENT || dealReason == DEAL_REASON_EXPERT)
    {
        if(config.DebugMode())
            Print("DEBUG: Using profit-based determination");
        isStopLoss = (profit < 0);
        isTakeProfit = (profit >= 0);
    }
    
    // Анализируем результат сделки
    if(isTakeProfit)
    {
        // Прибыльная сделка (TP или breakeven SL) → блокируем систему до завтра
        if(config.DebugMode())
            Print("DEBUG: *** PROFITABLE TRADE *** → System blocked until tomorrow");
            
        systemState = STATE_BLOCKED_UNTIL_TOMORROW;
        lastBlockedDay = iTime(_Symbol, PERIOD_D1, 0);
        // Сбрасываем все параметры
        currentReversalCount = 0;
        currentLotSize = config.LotSize();
        lastTradeDirection = WRONG_VALUE;
        trailingStopActivated = false;
    }
    else if(isStopLoss)
    {
        // Убыточная сделка (SL) → немедленный разворот
        if(config.DebugMode())
            Print("DEBUG: *** STOP LOSS *** → Immediate reversal");
            
        if(currentReversalCount < config.MaxReversals())
        {
            ExecuteImmediateReversal();
        }
        else
        {
            // Лимит разворотов достигнут
            if(config.DebugMode())
                Print("DEBUG: Max reversals reached → System blocked until tomorrow");
                
            systemState = STATE_BLOCKED_UNTIL_TOMORROW;
            lastBlockedDay = iTime(_Symbol, PERIOD_D1, 0);
            // Сбрасываем все параметры
            currentReversalCount = 0;
            currentLotSize = config.LotSize();
            lastTradeDirection = WRONG_VALUE;
            trailingStopActivated = false;
        }
    }
    else
    {
        // Неизвестная причина → возвращаемся к поиску сигналов
        if(config.DebugMode())
            Print("DEBUG: Unknown close reason → Return to signal search");
            
        systemState = STATE_LOOKING_FOR_SIGNAL;
        // Не сбрасываем реверсы, если они есть
        lastTradeDirection = WRONG_VALUE;
        trailingStopActivated = false;
    }
}

//+------------------------------------------------------------------+
//| Функция немедленного разворота                                   |
//+------------------------------------------------------------------+
void ExecuteImmediateReversal()
{
    // Проверяем, не превышен ли лимит реверсов
    if(currentReversalCount >= config.MaxReversals())
    {
        if(config.DebugMode())
            Print("DEBUG: Reversal limit already reached, blocking system");
        systemState = STATE_BLOCKED_UNTIL_TOMORROW;
        lastBlockedDay = iTime(_Symbol, PERIOD_D1, 0);
        // Сбрасываем все параметры
        currentReversalCount = 0;
        currentLotSize = config.LotSize();
        lastTradeDirection = WRONG_VALUE;
        trailingStopActivated = false;
        return;
    }
    
    currentReversalCount++;
    
    // Увеличиваем лот
    if(config.LotScalingFactor() > 1.0)
        currentLotSize *= config.LotScalingFactor();
    
    if(config.DebugMode())
        Print("DEBUG: Executing immediate reversal #", currentReversalCount, 
              " with lot ", currentLotSize, 
              ", max allowed: ", config.MaxReversals());
    
    // Небольшая задержка перед открытием новой позиции
    Sleep(100);
    
    // Открываем противоположную позицию
    if(lastTradeDirection == POSITION_TYPE_BUY)
    {
        // Была покупка → открываем продажу
        if(config.DebugMode())
            Print("DEBUG: Reversing from BUY to SELL");
        OpenSellPosition();
    }
    else if(lastTradeDirection == POSITION_TYPE_SELL)
    {
        // Была продажа → открываем покупку  
        if(config.DebugMode())
            Print("DEBUG: Reversing from SELL to BUY");
        OpenBuyPosition();
    }
    else
    {
        // Если не определено направление последней сделки, открываем противоположную позицию
        // относительно сигнала, который вызвал закрытие позиции
        if(config.DebugMode())
            Print("DEBUG: Last direction unknown, using price-based decision");
            
        double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double rangeHigh = rangeManager.GetRangeHigh();
        double rangeLow = rangeManager.GetRangeLow();
        
        // Простая логика: если цена выше середины диапазона, открываем sell, иначе buy
        double rangeMid = (rangeHigh + rangeLow) / 2;
        if(currentPrice > rangeMid)
        {
            if(config.DebugMode())
                Print("DEBUG: Price above range midpoint, opening SELL");
            OpenSellPosition();
        }
        else
        {
            if(config.DebugMode())
                Print("DEBUG: Price below range midpoint, opening BUY");
            OpenBuyPosition();
        }
    }
    
    systemState = STATE_POSITION_OPEN;
}

//+------------------------------------------------------------------+
//| Функция открытия позиции на покупку                               |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
    double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double stopLossDistance = utils.PointsToPrice(config.StopLossPoints());
    double stopLoss = price - stopLossDistance;
    double takeProfitDistance = stopLossDistance * config.TakeProfitMultiplier();
    double takeProfit = price + takeProfitDistance;
    
    // Для реверсных сделок используем рыночную цену
    if(currentReversalCount > 0)
    {
        price = SymbolInfoDouble(_Symbol, SYMBOL_BID); // Используем bid для buy
        stopLoss = price - stopLossDistance;
        takeProfit = price + takeProfitDistance;
    }
    
    if(config.DebugMode())
        Print("DEBUG: Opening BUY - Lot=", currentLotSize, ", Price=", price, ", SL=", stopLoss, ", TP=", takeProfit, 
              ", Reversal #", currentReversalCount);
    
    if(tradingOps.Buy(currentLotSize, stopLoss, takeProfit))
    {
        trailingStopActivated = false;
        lastTradeDirection = POSITION_TYPE_BUY;
        
        if(config.DebugMode())
            Print("DEBUG: BUY opened successfully");
    }
    else if(config.DebugMode())
    {
        Print("DEBUG: Failed to open BUY position. Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Функция открытия позиции на продажу                              |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double stopLossDistance = utils.PointsToPrice(config.StopLossPoints());
    double stopLoss = price + stopLossDistance;
    double takeProfitDistance = stopLossDistance * config.TakeProfitMultiplier();
    double takeProfit = price - takeProfitDistance;
    
    // Для реверсных сделок используем рыночную цену
    if(currentReversalCount > 0)
    {
        price = SymbolInfoDouble(_Symbol, SYMBOL_ASK); // Используем ask для sell
        stopLoss = price + stopLossDistance;
        takeProfit = price - takeProfitDistance;
    }
    
    if(config.DebugMode())
        Print("DEBUG: Opening SELL - Lot=", currentLotSize, ", Price=", price, ", SL=", stopLoss, ", TP=", takeProfit,
              ", Reversal #", currentReversalCount);
    
    if(tradingOps.Sell(currentLotSize, stopLoss, takeProfit))
    {
        trailingStopActivated = false;
        lastTradeDirection = POSITION_TYPE_SELL;
        
        if(config.DebugMode())
            Print("DEBUG: SELL opened successfully");
    }
    else if(config.DebugMode())
    {
        Print("DEBUG: Failed to open SELL position. Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Функция проверки трейлинг-стопа                                  |
//+------------------------------------------------------------------+
void CheckTrailingStop(ulong ticket)
{
    double currentProfit = tradingOps.GetCurrentPositionProfit();
    double stopLossDistance = utils.PointsToPrice(config.StopLossPoints());
    
    // Рассчитываем прибыль, необходимую для передвижения стопа в безубыток
    double lotSize = tradingOps.GetCurrentPositionLots();
    double breakEvenProfit = stopLossDistance * lotSize / _Point;
    
    if(config.DebugMode() && currentProfit > breakEvenProfit * 0.8)
    {
        Print("DEBUG: Trailing stop check for position #", ticket, 
              " - Profit: ", currentProfit, ", Break-even threshold: ", breakEvenProfit);
    }
    
    if(currentProfit >= breakEvenProfit)
    {
        double openPrice = tradingOps.GetCurrentPositionOpenPrice();
        if(config.DebugMode())
            Print("DEBUG: Profit threshold reached, moving stop to breakeven for position #", ticket,
                  ". Open price: ", openPrice);
                  
        if(tradingOps.ModifyStopLoss(ticket, openPrice))
        {
            trailingStopActivated = true;
            if(config.DebugMode())
                Print("DEBUG: Stop moved to breakeven for position #", ticket);
        }
        else if(config.DebugMode())
        {
            Print("DEBUG: Failed to move stop to breakeven for position #", ticket);
        }
    }
}

//+------------------------------------------------------------------+
//| Функция проверки смены дня                                       |
//+------------------------------------------------------------------+
void CheckNewDay()
{
    datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
    
    if(config.DebugMode())
    {
        Print("DEBUG: Checking day change. Current day: ", currentDay, 
              ", Last blocked day: ", lastBlockedDay,
              ", State: ", EnumToString(systemState));
    }
    
    if(systemState == STATE_BLOCKED_UNTIL_TOMORROW && currentDay > lastBlockedDay)
    {
        if(config.DebugMode())
            Print("DEBUG: *** NEW DAY *** → System unblocked");
            
        systemState = STATE_LOOKING_FOR_SIGNAL;
        ResetSystem();
        ResetBreakoutFlags();
    }
    else if(systemState == STATE_BLOCKED_UNTIL_TOMORROW && currentDay == lastBlockedDay)
    {
        if(config.DebugMode())
            Print("DEBUG: System still blocked until tomorrow");
    }
}

//+------------------------------------------------------------------+
//| Функция сброса системы                                           |
//+------------------------------------------------------------------+
void ResetSystem()
{
    currentReversalCount = 0;
    currentLotSize = config.LotSize();
    lastTradeDirection = WRONG_VALUE;
    trailingStopActivated = false;
    
    if(config.DebugMode())
        Print("DEBUG: System reset - Lot=", currentLotSize, ", Reversals=", currentReversalCount,
              ", Last direction: ", EnumToString(lastTradeDirection));
}

//+------------------------------------------------------------------+
//| Функция сброса флагов пробоев                                    |
//+------------------------------------------------------------------+
void ResetBreakoutFlags()
{
    upBreakoutDetected = false;
    downBreakoutDetected = false;
    upBreakoutPrice = 0.0;
    downBreakoutPrice = 0.0;
    
    if(config.DebugMode())
        Print("DEBUG: Breakout flags reset. Up: ", upBreakoutDetected ? "YES" : "NO",
              ", Down: ", downBreakoutDetected ? "YES" : "NO");
}
//+------------------------------------------------------------------+