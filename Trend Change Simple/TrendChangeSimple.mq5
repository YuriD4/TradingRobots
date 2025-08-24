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
input int      InpForceCloseHour = 20;           // Час принудительного закрытия позиций (по серверному времени)
input bool     InpDebugMode = true;              // Режим отладки
input bool     InpReverseOnBreakeven = true;     // Разворачиваться ли при закрытии по безубытку
input int      InpMaxBreakoutReturnHours = 3;    // Максимальное время между пробоем и возвратом (часы)

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

//+------------------------------------------------------------------+
//| ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ СОСТОЯНИЯ СИСТЕМЫ                          |
//+------------------------------------------------------------------+
// Состояние системы
SYSTEM_STATE                   systemState = STATE_LOOKING_FOR_SIGNAL;
datetime                       lastBarTime = 0;
datetime                       lastBlockedDay = 0;
datetime                       lastForceCloseDay = 0;
bool                          trailingStopActivated = false;

// Флаги обнаруженных пробоев диапазона
bool                          upBreakoutDetected = false;     // Был ли пробой вверх
bool                          downBreakoutDetected = false;   // Был ли пробой вниз
double                        upBreakoutPrice = 0.0;          // Цена пробоя вверх
double                        downBreakoutPrice = 0.0;        // Цена пробоя вниз
datetime                      upBreakoutTime = 0;             // Время пробоя вверх
datetime                      downBreakoutTime = 0;           // Время пробоя вниз

// Флаги разрешения торговли по направлениям (сбрасываются ежедневно)
bool                          canTradeUp = true;             // Можно ли торговать вверх (SELL)
bool                          canTradeDown = true;           // Можно ли торговать вниз (BUY)

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
        InpForceCloseHour,
        InpDebugMode,
        InpReverseOnBreakeven,
        InpMaxBreakoutReturnHours
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
    
    //+------------------------------------------------------------------+
    //| ЕЖЕДНЕВНАЯ ИНИЦИАЛИЗАЦИЯ ТОРГОВОЙ ЛОГИКИ                         |
    //+------------------------------------------------------------------+
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double rangeHigh = rangeManager.GetRangeHigh();
    double rangeLow = rangeManager.GetRangeLow();
    double breakoutDistance = utils.PointsToPrice(config.BreakoutPoints());
    
    // ПРИ НАЧАЛЕ НОВОГО ДНЯ:
    // 1. СБРАСЫВАЕМ ВСЕ ФЛАГИ НАПРАВЛЕНИЙ И ПРОБОЕВ
    canTradeUp = true;          // Разрешаем торговлю вверх
    canTradeDown = true;        // Разрешаем торговлю вниз
    upBreakoutDetected = false;   // Сбрасываем флаг пробоя вверх
    downBreakoutDetected = false; // Сбрасываем флаг пробоя вниз
    upBreakoutPrice = 0.0;
    downBreakoutPrice = 0.0;
    upBreakoutTime = 0;
    downBreakoutTime = 0;
    
    // 2. ОПРЕДЕЛЯЕМ НАЧАЛЬНОЕ ПОЛОЖЕНИЕ ЦЕНЫ ОТНОСИТЕЛЬНО ДИАПАЗОНА
    bool priceStartedAboveRange = (currentPrice > rangeHigh);
    bool priceStartedBelowRange = (currentPrice < rangeLow);
    
    // 3. УСТАНАВЛИВАЕМ ОГРАНИЧЕНИЯ НА ТОРГОВЛЮ ПО НАПРАВЛЕНИЯМ
    // Если цена НАЧАЛА ДЕНЬ вне диапазона, блокируем соответствующее направление
    if(priceStartedAboveRange)
    {
        canTradeUp = false;     // Цена уже выше диапазона → блокируем торговлю вверх
        if(config.DebugMode())
            Print("DEBUG: Price started ABOVE range - blocking UP trading for today");
    }
    
    if(priceStartedBelowRange)
    {
        canTradeDown = false;   // Цена уже ниже диапазона → блокируем торговлю вниз
        if(config.DebugMode())
            Print("DEBUG: Price started BELOW range - blocking DOWN trading for today");
    }
    
    if(config.DebugMode())
    {
        Print("DEBUG: === DAILY INITIALIZATION ===");
        Print("DEBUG: Current price: ", currentPrice);
        Print("DEBUG: Range - High: ", rangeHigh, ", Low: ", rangeLow);
        Print("DEBUG: Breakout distance: ", breakoutDistance);
        Print("DEBUG: Price started - Above range: ", priceStartedAboveRange ? "YES" : "NO", 
              ", Below range: ", priceStartedBelowRange ? "YES" : "NO");
        Print("DEBUG: Trading permissions - Up: ", canTradeUp ? "ALLOWED" : "BLOCKED", 
              ", Down: ", canTradeDown ? "ALLOWED" : "BLOCKED");
        Print("DEBUG: ===========================");
    }
    
    if(config.DebugMode())
    {
        Print("DEBUG: Initial price state - Starting with price IN RANGE to prevent false breakouts");
        Print("DEBUG: Current price: ", currentPrice);
        Print("DEBUG: Range high: ", rangeHigh, ", Range low: ", rangeLow);
        Print("DEBUG: Breakout distance: ", breakoutDistance);
        Print("DEBUG: Price ABOVE range: ", priceIsAboveRange ? "YES" : "NO");
        Print("DEBUG: Price BELOW range: ", priceIsBelowRange ? "YES" : "NO");
        Print("DEBUG: Trading permissions - Up: ", canTradeUp ? "ALLOWED" : "BLOCKED", 
              ", Down: ", canTradeDown ? "ALLOWED" : "BLOCKED");
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
    
    datetime currentTime = TimeCurrent();
    
    // Принудительно проверяем и сбрасываем просроченные флаги на каждом тике
    ForceExpireBreakouts(currentTime);
    
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
    
    // Проверяем необходимость принудительного закрытия позиций
    CheckForceCloseTime();
    
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
    datetime currentTime = TimeCurrent();
    
    //+------------------------------------------------------------------+
    //| СИСТЕМА ПРИНЯТИЯ РЕШЕНИЙ - ПОИСК ТОРГОВЫХ СИГНАЛОВ              |
    //+------------------------------------------------------------------+
    
    // 1. ВЫЧИСЛЯЕМ ГРАНИЦЫ ДИАПАЗОНА С УЧЕТОМ ДИСТАНЦИИ ПРОБОЯ
    double upperBreakoutThreshold = rangeHigh + breakoutDistance;  // Порог пробоя вверх
    double lowerBreakoutThreshold = rangeLow - breakoutDistance;   // Порог пробоя вниз
    
    // 2. ОПРЕДЕЛЯЕМ ТЕКУЩЕЕ ПОЛОЖЕНИЕ ЦЕНЫ
    bool isPriceAboveRange = (currentPrice > rangeHigh);           // Цена выше диапазона
    bool isPriceBelowRange = (currentPrice < rangeLow);            // Цена ниже диапазона
    bool isPriceInRange = (!isPriceAboveRange && !isPriceBelowRange); // Цена в диапазоне
    
    // 3. ОПРЕДЕЛЯЕМ НАЛИЧИЕ ФАКТИЧЕСКИХ ПРОБОЕВ
    bool isActualBreakoutDown = (currentPrice < lowerBreakoutThreshold);  // Пробой вниз (с расстоянием)
    bool isActualBreakoutUp = (currentPrice > upperBreakoutThreshold);    // Пробой вверх (с расстоянием)
    
    // 4. ПОДРОБНОЕ ЛОГИРОВАНИЕ ДЛЯ ОТЛАДКИ
    if(config.DebugMode())
    {
        Print("DEBUG: === SIGNAL PROCESSING DECISION TREE ===");
        Print("DEBUG: Current price: ", currentPrice);
        Print("DEBUG: Range - High: ", rangeHigh, ", Low: ", rangeLow);
        Print("DEBUG: Breakout distance: ", breakoutDistance);
        Print("DEBUG: Breakout thresholds - Up: ", upperBreakoutThreshold, ", Down: ", lowerBreakoutThreshold);
        Print("DEBUG: Price position - Above range: ", isPriceAboveRange ? "YES" : "NO", 
              ", Below range: ", isPriceBelowRange ? "YES" : "NO", 
              ", In range: ", isPriceInRange ? "YES" : "NO");
        Print("DEBUG: Actual breakouts - Up: ", isActualBreakoutUp ? "YES" : "NO", 
              ", Down: ", isActualBreakoutDown ? "YES" : "NO");
        Print("DEBUG: Trading permissions - Up: ", canTradeUp ? "ALLOWED" : "BLOCKED", 
              ", Down: ", canTradeDown ? "ALLOWED" : "BLOCKED");
        Print("DEBUG: Existing breakouts - Up: ", upBreakoutDetected ? "DETECTED" : "NOT DETECTED", 
              ", Down: ", downBreakoutDetected ? "DETECTED" : "NOT DETECTED");
        Print("DEBUG: ========================================");
    }
    
    //+------------------------------------------------------------------+
    //| ЭТАП 1: ОБНАРУЖЕНИЕ ПРОБОЕВ С УЧЕТОМ РАЗРЕШЕНИЙ НАПРАВЛЕНИЙ     |
    //+------------------------------------------------------------------+
    
    // ПРОБОЙ ВНИЗ: Цена выходит НИЖЕ диапазона на нужное расстояние
    if(!downBreakoutDetected && isActualBreakoutDown && canTradeDown)
    {
        downBreakoutDetected = true;
        downBreakoutPrice = currentPrice;
        downBreakoutTime = currentTime;
        
        Print("CRITICAL: >>> DOWN BREAKOUT DETECTED <<<");
        Print("CRITICAL: Price: ", currentPrice, " at time: ", TimeToString(currentTime));
        Print("CRITICAL: Range low: ", rangeLow, ", Breakout threshold: ", lowerBreakoutThreshold);
        Print("CRITICAL: Blocking DOWN trading for the rest of the day");
        
        // Блокируем торговлю вниз до конца дня
        canTradeDown = false;
    }
    
    // ПРОБОЙ ВВЕРХ: Цена выходит ВЫШЕ диапазона на нужное расстояние
    if(!upBreakoutDetected && isActualBreakoutUp && canTradeUp)
    {
        upBreakoutDetected = true;
        upBreakoutPrice = currentPrice;
        upBreakoutTime = currentTime;
        
        Print("CRITICAL: >>> UP BREAKOUT DETECTED <<<");
        Print("CRITICAL: Price: ", currentPrice, " at time: ", TimeToString(currentTime));
        Print("CRITICAL: Range high: ", rangeHigh, ", Breakout threshold: ", upperBreakoutThreshold);
        Print("CRITICAL: Blocking UP trading for the rest of the day");
        
        // Блокируем торговлю вверх до конца дня
        canTradeUp = false;
    }
    
    //+------------------------------------------------------------------+
    //| ЭТАП 2: ОБНАРУЖЕНИЕ ВОЗВРАТОВ ПОСЛЕ ПРОБОЕВ                     |
    //+------------------------------------------------------------------+
    
    // ВОЗВРАТ ПОСЛЕ ПРОБОЯ ВНИЗ → СИГНАЛ BUY
    if(downBreakoutDetected && currentPrice >= (rangeLow + onePoint))
    {
        int secondsPassed = (int)(currentTime - downBreakoutTime);
        int hoursPassed = secondsPassed / 3600;
        
        Print("CRITICAL: >>> RETURN AFTER DOWN BREAKOUT DETECTED <<<");
        Print("CRITICAL: Return price: ", currentPrice, " at time: ", TimeToString(currentTime));
        Print("CRITICAL: Time elapsed: ", hoursPassed, " hours");
        
        // Проверяем ограничение по времени (≤ 3 часов)
        if(hoursPassed <= config.MaxBreakoutReturnHours())
        {
            Print("CRITICAL: *** OPENING BUY POSITION ***");
            Print("CRITICAL: Valid breakout-return pattern within ", hoursPassed, " hours");
            OpenBuyPosition();
            ResetBreakoutFlags();  // Сбрасываем флаги пробоев (но оставляем canTradeDown = false!)
            systemState = STATE_POSITION_OPEN;
            return;
        }
        else
        {
            Print("CRITICAL: BUY signal IGNORED - time expired (", hoursPassed, " hours > ", config.MaxBreakoutReturnHours(), " hours)");
            // Сбрасываем только флаг пробоя, не блокируем навсегда
            downBreakoutDetected = false;
            downBreakoutPrice = 0.0;
            downBreakoutTime = 0;
        }
    }
    
    // ВОЗВРАТ ПОСЛЕ ПРОБОЯ ВВЕРХ → СИГНАЛ SELL
    if(upBreakoutDetected && currentPrice <= (rangeHigh - onePoint))
    {
        int secondsPassed = (int)(currentTime - upBreakoutTime);
        int hoursPassed = secondsPassed / 3600;
        
        Print("CRITICAL: >>> RETURN AFTER UP BREAKOUT DETECTED <<<");
        Print("CRITICAL: Return price: ", currentPrice, " at time: ", TimeToString(currentTime));
        Print("CRITICAL: Time elapsed: ", hoursPassed, " hours");
        
        // Проверяем ограничение по времени (≤ 3 часов)
        if(hoursPassed <= config.MaxBreakoutReturnHours())
        {
            Print("CRITICAL: *** OPENING SELL POSITION ***");
            Print("CRITICAL: Valid breakout-return pattern within ", hoursPassed, " hours");
            OpenSellPosition();
            ResetBreakoutFlags();  // Сбрасываем флаги пробоев (но оставляем canTradeUp = false!)
            systemState = STATE_POSITION_OPEN;
            return;
        }
        else
        {
            Print("CRITICAL: SELL signal IGNORED - time expired (", hoursPassed, " hours > ", config.MaxBreakoutReturnHours(), " hours)");
            // Сбрасываем только флаг пробоя, не блокируем навсегда
            upBreakoutDetected = false;
            upBreakoutPrice = 0.0;
            upBreakoutTime = 0;
        }
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
    bool isBreakeven = trailingStopActivated && !isStopLoss && !isTakeProfit;
    
    // Если не можем определить по DEAL_REASON, используем profit
    if(dealReason == -1 || dealReason == DEAL_REASON_CLIENT || dealReason == DEAL_REASON_EXPERT)
    {
        if(config.DebugMode())
            Print("DEBUG: Using profit-based determination");
        isStopLoss = (profit < 0);
        isTakeProfit = (profit >= 0);
        isBreakeven = false; // Не можем определить по profit
    }
    
    // Анализируем результат сделки
    if(isTakeProfit || (isBreakeven && !config.ReverseOnBreakeven()))
    {
        string reasonText = isTakeProfit ? "TAKE PROFIT" : "BREAKEVEN (treated as TP)";
        if(config.DebugMode())
            Print("DEBUG: *** ", reasonText, " *** → System blocked until tomorrow");
            
        systemState = STATE_BLOCKED_UNTIL_TOMORROW;
        lastBlockedDay = iTime(_Symbol, PERIOD_D1, 0);
        // Сбрасываем все параметры
        currentReversalCount = 0;
        currentLotSize = config.LotSize();
        lastTradeDirection = WRONG_VALUE;
        trailingStopActivated = false;
        ResetForceCloseDay(); // Сбрасываем день принудительного закрытия
    }
    else if(isStopLoss || (isBreakeven && config.ReverseOnBreakeven()))
    {
        string reasonText = isStopLoss ? "STOP LOSS" : "BREAKEVEN (treated as SL)";
        if(config.DebugMode())
            Print("DEBUG: *** ", reasonText, " *** → Immediate reversal");
            
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
            ResetForceCloseDay(); // Сбрасываем день принудительного закрытия
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
    
    Print("CRITICAL: Opening BUY - Lot=", currentLotSize, ", Price=", price, ", SL=", stopLoss, ", TP=", takeProfit, 
          ", Reversal #", currentReversalCount);
    
    if(tradingOps.Buy(currentLotSize, stopLoss, takeProfit))
    {
        trailingStopActivated = false;
        lastTradeDirection = POSITION_TYPE_BUY;
        
        Print("CRITICAL: BUY opened successfully");
    }
    else
    {
        Print("CRITICAL: Failed to open BUY position. Error: ", GetLastError());
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
    
    Print("CRITICAL: Opening SELL - Lot=", currentLotSize, ", Price=", price, ", SL=", stopLoss, ", TP=", takeProfit,
          ", Reversal #", currentReversalCount);
    
    if(tradingOps.Sell(currentLotSize, stopLoss, takeProfit))
    {
        trailingStopActivated = false;
        lastTradeDirection = POSITION_TYPE_SELL;
        
        Print("CRITICAL: SELL opened successfully");
    }
    else
    {
        Print("CRITICAL: Failed to open SELL position. Error: ", GetLastError());
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
              ", Last force close day: ", lastForceCloseDay,
              ", State: ", EnumToString(systemState));
        Print("DEBUG: Trading permissions before check - Up: ", canTradeUp ? "ALLOWED" : "BLOCKED", 
              ", Down: ", canTradeDown ? "ALLOWED" : "BLOCKED");
    }
    
    if(systemState == STATE_BLOCKED_UNTIL_TOMORROW && currentDay > lastBlockedDay)
    {
        if(config.DebugMode())
            Print("DEBUG: *** NEW DAY *** → System unblocked");
            
        systemState = STATE_LOOKING_FOR_SIGNAL;
        ResetSystem();
        ResetBreakoutFlags();
        ResetForceCloseDay(); // Сбрасываем день принудительного закрытия
        
        if(config.DebugMode())
        {
            Print("DEBUG: Trading permissions after reset - Up: ", canTradeUp ? "ALLOWED" : "BLOCKED", 
                  ", Down: ", canTradeDown ? "ALLOWED" : "BLOCKED");
        }
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
    
    // ВАЖНО: Не сбрасываем флаги направлений (canTradeUp/canTradeDown) здесь!
    // Они сбрасываются только при ежедневной инициализации
    
    if(config.DebugMode())
    {
        Print("DEBUG: === SYSTEM RESET ===");
        Print("DEBUG: Lot size: ", currentLotSize);
        Print("DEBUG: Reversal count: ", currentReversalCount);
        Print("DEBUG: Last trade direction: ", EnumToString(lastTradeDirection));
        Print("DEBUG: Trading permissions - Up: ", canTradeUp ? "ALLOWED" : "BLOCKED", 
              ", Down: ", canTradeDown ? "ALLOWED" : "BLOCKED");
        Print("DEBUG: ===================");
    }
}

//+------------------------------------------------------------------+
//| Функция сброса дня принудительного закрытия                      |
//+------------------------------------------------------------------+
void ResetForceCloseDay()
{
    lastForceCloseDay = 0;
    
    if(config.DebugMode())
        Print("DEBUG: Force close day reset");
}

//+------------------------------------------------------------------+
//| Функция сброса флагов пробоев                                    |
//+------------------------------------------------------------------+
void ResetBreakoutFlags()
{
    bool oldUpFlag = upBreakoutDetected;
    bool oldDownFlag = downBreakoutDetected;
    
    upBreakoutDetected = false;
    downBreakoutDetected = false;
    upBreakoutPrice = 0.0;
    downBreakoutPrice = 0.0;
    upBreakoutTime = 0;
    downBreakoutTime = 0;
    
    if(config.DebugMode())
    {
        Print("CRITICAL: === BREAKOUT FLAGS RESET ===");
        Print("CRITICAL: Previous state - Up: ", oldUpFlag ? "DETECTED" : "NOT DETECTED",
              ", Down: ", oldDownFlag ? "DETECTED" : "NOT DETECTED");
        Print("CRITICAL: New state - Up: ", upBreakoutDetected ? "DETECTED" : "NOT DETECTED",
              ", Down: ", downBreakoutDetected ? "DETECTED" : "NOT DETECTED");
        Print("CRITICAL: ==========================");
    }
}

//+------------------------------------------------------------------+
//| Функция принудительной проверки и сброса просроченных флагов     |
//+------------------------------------------------------------------+
void ForceExpireBreakouts(datetime currentTime)
{
    // Получаем текущее состояние цены для отладки
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double rangeHigh = rangeManager.GetRangeHigh();
    double rangeLow = rangeManager.GetRangeLow();
    double breakoutDistance = utils.PointsToPrice(config.BreakoutPoints());
    
    bool isPriceAboveRange = (currentPrice > (rangeHigh + breakoutDistance));
    bool isPriceBelowRange = (currentPrice < (rangeLow - breakoutDistance));
    bool isPriceInRange = (!isPriceAboveRange && !isPriceBelowRange);
    
    // Простая проверка: если с момента пробоя прошло больше 3 часов, сбрасываем флаги
    bool downExpired = false;
    bool upExpired = false;
    
    if(downBreakoutDetected)
    {
        if(currentTime >= downBreakoutTime)
        {
            int hoursPassed = (int)(currentTime - downBreakoutTime) / 3600;
            if(hoursPassed > config.MaxBreakoutReturnHours())
            {
                Print("CRITICAL: DOWN breakout EXPIRED after ", hoursPassed, " hours (max ", config.MaxBreakoutReturnHours(), " hours)");
                Print("CRITICAL: Current price state - In range: ", isPriceInRange ? "YES" : "NO", 
                      ", Above range: ", isPriceAboveRange ? "YES" : "NO", 
                      ", Below range: ", isPriceBelowRange ? "YES" : "NO");
                Print("CRITICAL: Current price: ", currentPrice, ", Range low: ", rangeLow, ", Breakout threshold: ", (rangeLow - breakoutDistance));
                downExpired = true;
            }
        }
        else
        {
            // Время некорректно, сбрасываем флаг
            Print("CRITICAL: Time inconsistency for DOWN breakout, resetting flag");
            downExpired = true;
        }
    }
    
    if(upBreakoutDetected)
    {
        if(currentTime >= upBreakoutTime)
        {
            int hoursPassed = (int)(currentTime - upBreakoutTime) / 3600;
            if(hoursPassed > config.MaxBreakoutReturnHours())
            {
                Print("CRITICAL: UP breakout EXPIRED after ", hoursPassed, " hours (max ", config.MaxBreakoutReturnHours(), " hours)");
                Print("CRITICAL: Current price state - In range: ", isPriceInRange ? "YES" : "NO", 
                      ", Above range: ", isPriceAboveRange ? "YES" : "NO", 
                      ", Below range: ", isPriceBelowRange ? "YES" : "NO");
                Print("CRITICAL: Current price: ", currentPrice, ", Range high: ", rangeHigh, ", Breakout threshold: ", (rangeHigh + breakoutDistance));
                upExpired = true;
            }
        }
        else
        {
            // Время некорректно, сбрасываем флаг
            Print("CRITICAL: Time inconsistency for UP breakout, resetting flag");
            upExpired = true;
        }
    }
    
    // Сбрасываем флаги в конце, чтобы не повлиять на логику выше
    if(downExpired)
    {
        downBreakoutDetected = false;
        downBreakoutPrice = 0.0;
        downBreakoutTime = 0;
    }
    
    if(upExpired)
    {
        upBreakoutDetected = false;
        upBreakoutPrice = 0.0;
        upBreakoutTime = 0;
    }
}

//+------------------------------------------------------------------+
//| Функция проверки времени принудительного закрытия позиций       |
//+------------------------------------------------------------------+
void CheckForceCloseTime()
{
    // Получаем текущее время
    datetime currentTime = TimeCurrent();
    MqlDateTime currentDT;
    TimeToStruct(currentTime, currentDT);
    
    // Получаем текущий день
    datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
    
    // Проверяем, не выполняли ли мы уже закрытие сегодня
    if(lastForceCloseDay == currentDay)
    {
        return; // Уже выполняли закрытие сегодня
    }
    
    // Проверяем, наступил ли час принудительного закрытия
    if(currentDT.hour == config.ForceCloseHour())
    {
        // Проверяем, есть ли открытые позиции
        if(tradingOps.HasOpenPosition())
        {
            if(config.DebugMode())
                Print("DEBUG: Force closing all positions at ", TimeToString(currentTime));
                
            // Закрываем все позиции
            tradingOps.CloseAllPositions();
            
            // Обновляем состояние системы
            systemState = STATE_BLOCKED_UNTIL_TOMORROW;
            lastBlockedDay = currentDay;
            lastForceCloseDay = currentDay;
            
            // Сбрасываем параметры
            ResetSystem();
            ResetBreakoutFlags();
            
            if(config.DebugMode())
                Print("DEBUG: All positions closed and system blocked until tomorrow");
        }
        else
        {
            // Нет открытых позиций, но помечаем день, чтобы не проверять снова
            lastForceCloseDay = currentDay;
            
            if(config.DebugMode())
                Print("DEBUG: No open positions to close at force close time");
        }
    }
}
//+------------------------------------------------------------------+