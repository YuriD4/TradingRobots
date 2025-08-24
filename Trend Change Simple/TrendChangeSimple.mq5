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

// Глобальные переменные состояния
SYSTEM_STATE                   systemState = STATE_LOOKING_FOR_SIGNAL;
datetime                       lastBarTime = 0;
datetime                       lastBlockedDay = 0;
datetime                       lastForceCloseDay = 0;
bool                          trailingStopActivated = false;

// Переменные для отслеживания пробоев диапазона
bool                          upBreakoutDetected = false;
bool                          downBreakoutDetected = false;
double                        upBreakoutPrice = 0.0;
double                        downBreakoutPrice = 0.0;
datetime                      upBreakoutTime = 0;
datetime                      downBreakoutTime = 0;

// Переменные для отслеживания состояния цены относительно диапазона
bool                          wasPriceAboveRange = false;
bool                          wasPriceBelowRange = false;
bool                          wasPriceInRange = false;

// Переменные для ограничения торговли по направлениям
bool                          canTradeUp = true;    // Можно ли торговать пробой вверх
bool                          canTradeDown = true;  // Можно ли торговать пробой вниз

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
    
    // Инициализируем переменные состояния цены
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double rangeHigh = rangeManager.GetRangeHigh();
    double rangeLow = rangeManager.GetRangeLow();
    double breakoutDistance = utils.PointsToPrice(config.BreakoutPoints());
    
    // При инициализации НЕ устанавливаем флаги, даже если цена вне диапазона
    // Это предотвращает регистрацию "пробоев" которые уже произошли до запуска
    wasPriceAboveRange = false;
    wasPriceBelowRange = false;
    wasPriceInRange = true; // Начинаем с предположения, что цена в диапазоне
    
    // Определяем, в каком состоянии начала торговля
    bool priceIsAboveRange = (currentPrice > (rangeHigh + breakoutDistance));
    bool priceIsBelowRange = (currentPrice < (rangeLow - breakoutDistance));
    
    // Устанавливаем ограничения на торговлю в зависимости от начального положения цены
    // Если цена НАЧАЛА ДЕНЬ вне диапазона, блокируем соответствующее направление
    canTradeUp = !priceIsAboveRange;   // Можно торговать вверх, если цена НЕ выше диапазона в начале дня
    canTradeDown = !priceIsBelowRange; // Можно торговать вниз, если цена НЕ ниже диапазона в начале дня
    
    if(config.DebugMode())
    {
        Print("DEBUG: Initial price position check:");
        Print("DEBUG:   Current price: ", currentPrice);
        Print("DEBUG:   Range high + distance: ", (rangeHigh + breakoutDistance));
        Print("DEBUG:   Range low - distance: ", (rangeLow - breakoutDistance));
        Print("DEBUG:   Price is ABOVE range: ", priceIsAboveRange ? "YES" : "NO");
        Print("DEBUG:   Price is BELOW range: ", priceIsBelowRange ? "YES" : "NO");
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
    
    // ЧЕТКАЯ БИЗНЕС-ЛОГИКА:
    // 1. Ждем, пока цена ВЫЙДЕТ за границы диапазона (вверх или вниз)
    // 2. Запоминаем время выхода
    // 3. Ждем, пока цена ВЕРНЕТСЯ в диапазон
    // 4. Проверяем, что между выходом и возвращением прошло ≤ 3 часов
    // 5. Если условие выполняется - открываем сделку
    // 6. Если условие не выполняется - сбрасываем флаги и ждем нового выхода
    
    // Отслеживаем текущее состояние цены относительно диапазона
    // ВАЖНО: Здесь мы проверяем, находится ли цена ВНУТРИ границ диапазона, а не вышла ли она на расстояние
    bool isPriceStrictlyAboveRange = (currentPrice > rangeHigh);
    bool isPriceStrictlyBelowRange = (currentPrice < rangeLow);
    bool isPriceStrictlyInRange = (!isPriceStrictlyAboveRange && !isPriceStrictlyBelowRange);
    
    // Отслеживаем переходы цены относительно границ диапазона (без учета расстояния)
    bool enteredRangeFromAbove = (wasPriceAboveRange && isPriceStrictlyInRange);
    bool enteredRangeFromBelow = (wasPriceBelowRange && isPriceStrictlyInRange);
    bool exitedRangeUp = (wasPriceInRange && isPriceStrictlyAboveRange);
    bool exitedRangeDown = (wasPriceInRange && isPriceStrictlyBelowRange);
    
    // Обновляем состояние цены
    wasPriceAboveRange = isPriceStrictlyAboveRange;
    wasPriceBelowRange = isPriceStrictlyBelowRange;
    wasPriceInRange = isPriceStrictlyInRange;
    
    // Проверяем, произошел ли настоящий пробой (выход на нужное расстояние)
    bool isActualBreakoutDown = (currentPrice < (rangeLow - breakoutDistance));
    bool isActualBreakoutUp = (currentPrice > (rangeHigh + breakoutDistance));
    
    if(config.DebugMode())
    {
        Print("DEBUG: Price state tracking:");
        Print("DEBUG:   Current price: ", currentPrice);
        Print("DEBUG:   Range high: ", rangeHigh, ", Range low: ", rangeLow);
        Print("DEBUG:   Breakout distance: ", breakoutDistance);
        Print("DEBUG:   Strict range boundaries - Above: ", isPriceStrictlyAboveRange ? "YES" : "NO",
              ", Below: ", isPriceStrictlyBelowRange ? "YES" : "NO",
              ", In range: ", isPriceStrictlyInRange ? "YES" : "NO");
        Print("DEBUG:   Actual breakout detection - Up: ", isActualBreakoutUp ? "YES" : "NO",
              ", Down: ", isActualBreakoutDown ? "YES" : "NO");
        Print("DEBUG:   Previous state - Above: ", wasPriceAboveRange ? "YES" : "NO",
              ", Below: ", wasPriceBelowRange ? "YES" : "NO",
              ", In range: ", wasPriceInRange ? "YES" : "NO");
        Print("DEBUG:   Trading permissions - Up: ", canTradeUp ? "ALLOWED" : "BLOCKED",
              ", Down: ", canTradeDown ? "ALLOWED" : "BLOCKED");
        Print("DEBUG:   Existing breakouts - Up: ", upBreakoutDetected ? "DETECTED" : "NOT DETECTED",
              ", Down: ", downBreakoutDetected ? "DETECTED" : "NOT DETECTED");
    }
    
    // 1. Обнаружение пробоя ВНИЗ (цена вышла из диапазона на нужное расстояние)
    // Пробой регистрируется только если:
    // - цена была в диапазоне и вышла вниз на нужное расстояние
    // - торговля вниз разрешена (canTradeDown = true)
    if(!downBreakoutDetected && isActualBreakoutDown && wasPriceInRange && canTradeDown)
    {
        // Фиксируем момент первого выхода вниз
        downBreakoutDetected = true;
        downBreakoutPrice = currentPrice;
        downBreakoutTime = currentTime;
        
        Print("CRITICAL: DOWN breakout DETECTED at price ", currentPrice, " at time ", TimeToString(currentTime));
        Print("CRITICAL: Range low: ", rangeLow, ", Breakout threshold: ", (rangeLow - breakoutDistance));
        Print("CRITICAL: Trading permission - Down breakout ALLOWED");
        
        // Блокируем дальнейшую торговлю вниз в течение этого дня
        canTradeDown = false;
        Print("CRITICAL: Trading permission - Down breakout BLOCKED for the rest of the day");
    }
    else if(!canTradeDown && isActualBreakoutDown && wasPriceInRange)
    {
        Print("CRITICAL: DOWN breakout DETECTED but IGNORED - trading permission BLOCKED");
        Print("CRITICAL: Price broke range down but we started below range or already had down breakout");
    }
    
    // 2. Обнаружение пробоя ВВЕРХ (цена вышла из диапазона на нужное расстояние)
    // Пробой регистрируется только если:
    // - цена была в диапазоне и вышла вверх на нужное расстояние
    // - торговля вверх разрешена (canTradeUp = true)
    if(!upBreakoutDetected && isActualBreakoutUp && wasPriceInRange && canTradeUp)
    {
        // Фиксируем момент первого выхода вверх
        upBreakoutDetected = true;
        upBreakoutPrice = currentPrice;
        upBreakoutTime = currentTime;
        
        Print("CRITICAL: UP breakout DETECTED at price ", currentPrice, " at time ", TimeToString(currentTime));
        Print("CRITICAL: Range high: ", rangeHigh, ", Breakout threshold: ", (rangeHigh + breakoutDistance));
        Print("CRITICAL: Trading permission - Up breakout ALLOWED");
        
        // Блокируем дальнейшую торговлю вверх в течение этого дня
        canTradeUp = false;
        Print("CRITICAL: Trading permission - Up breakout BLOCKED for the rest of the day");
    }
    else if(!canTradeUp && isActualBreakoutUp && wasPriceInRange)
    {
        Print("CRITICAL: UP breakout DETECTED but IGNORED - trading permission BLOCKED");
        Print("CRITICAL: Price broke range up but we started above range or already had up breakout");
    }
    
    // 3. Возврат после пробоя ВНИЗ → сигнал BUY
    if(downBreakoutDetected)
    {
        if(config.DebugMode())
            Print("DEBUG: Checking DOWN breakout return condition - current price: ", currentPrice, 
                  ", threshold: ", (rangeLow + onePoint));
                  
        if(currentPrice >= (rangeLow + onePoint))
        {
            // Проверяем корректность времени
            if(currentTime < downBreakoutTime)
            {
                Print("DEBUG: WARNING - Current time (", TimeToString(currentTime), ") is before breakout time (", TimeToString(downBreakoutTime), "). Resetting DOWN breakout flag.");
                // Сбрасываем флаг пробоя, так как время некорректно
                downBreakoutDetected = false;
                downBreakoutPrice = 0.0;
                downBreakoutTime = 0;
            }
            else
            {
                // Проверяем, не превышает ли время между пробоем и возвратом максимальное значение
                int secondsPassed = (int)(currentTime - downBreakoutTime);
                int hoursPassed = secondsPassed / 3600;
                
                if(config.DebugMode())
                    Print("DEBUG: Return after DOWN breakout → Opening BUY (time elapsed: ", hoursPassed, " hours)");
                
                // Только если время в пределах допустимого, открываем позицию
                if(hoursPassed <= config.MaxBreakoutReturnHours())
                {
                    OpenBuyPosition();
                    ResetBreakoutFlags();
                    systemState = STATE_POSITION_OPEN;
                    return; // Важно: выходим после открытия позиции
                }
                else
                {
                    if(config.DebugMode())
                        Print("DEBUG: DOWN breakout return ignored - time elapsed (", hoursPassed, " hours) exceeds maximum (", config.MaxBreakoutReturnHours(), " hours)");
                    // Сбрасываем флаг пробоя, так как время истекло
                    downBreakoutDetected = false;
                    downBreakoutPrice = 0.0;
                    downBreakoutTime = 0;
                }
            }
        }
    }
    
    // 4. Возврат после пробоя ВВЕРХ → сигнал SELL
    if(upBreakoutDetected)
    {
        if(config.DebugMode())
            Print("DEBUG: Checking UP breakout return condition - current price: ", currentPrice, 
                  ", threshold: ", (rangeHigh - onePoint));
                  
        if(currentPrice <= (rangeHigh - onePoint))
        {
            // Проверяем корректность времени
            if(currentTime < upBreakoutTime)
            {
                Print("DEBUG: WARNING - Current time (", TimeToString(currentTime), ") is before breakout time (", TimeToString(upBreakoutTime), "). Resetting UP breakout flag.");
                // Сбрасываем флаг пробоя, так как время некорректно
                upBreakoutDetected = false;
                upBreakoutPrice = 0.0;
                upBreakoutTime = 0;
            }
            else
            {
                // Проверяем, не превышает ли время между пробоем и возвратом максимальное значение
                int secondsPassed = (int)(currentTime - upBreakoutTime);
                int hoursPassed = secondsPassed / 3600;
                
                if(config.DebugMode())
                    Print("DEBUG: Return after UP breakout → Opening SELL (time elapsed: ", hoursPassed, " hours)");
                
                // Только если время в пределах допустимого, открываем позицию
                if(hoursPassed <= config.MaxBreakoutReturnHours())
                {
                    OpenSellPosition();
                    ResetBreakoutFlags();
                    systemState = STATE_POSITION_OPEN;
                    return; // Важно: выходим после открытия позиции
                }
                else
                {
                    if(config.DebugMode())
                        Print("DEBUG: UP breakout return ignored - time elapsed (", hoursPassed, " hours) exceeds maximum (", config.MaxBreakoutReturnHours(), " hours)");
                    // Сбрасываем флаг пробоя, так как время истекло
                    upBreakoutDetected = false;
                    upBreakoutPrice = 0.0;
                    upBreakoutTime = 0;
                }
            }
        }
    }
    
    // 3. Возврат после пробоя ВНИЗ → сигнал BUY
    if(downBreakoutDetected && currentPrice >= (rangeLow + onePoint))
    {
        // Цена вернулась в диапазон снизу
        // Проверяем время между выходом и возвращением
        int secondsPassed = (int)(currentTime - downBreakoutTime);
        int hoursPassed = secondsPassed / 3600;
        
        Print("CRITICAL: Return after DOWN breakout detected");
        Print("CRITICAL: Breakout time: ", TimeToString(downBreakoutTime));
        Print("CRITICAL: Return time: ", TimeToString(currentTime));
        Print("CRITICAL: Time elapsed: ", hoursPassed, " hours (max allowed: ", config.MaxBreakoutReturnHours(), " hours)");
        
        // Проверяем, что время возврата в пределах допустимого
        if(hoursPassed <= config.MaxBreakoutReturnHours())
        {
            Print("CRITICAL: Opening BUY position - valid breakout-return pattern within ", hoursPassed, " hours");
                
            OpenBuyPosition();
            ResetBreakoutFlags();
            systemState = STATE_POSITION_OPEN;
            return;
        }
        else
        {
            // Время истекло, сбрасываем флаг
            Print("CRITICAL: DOWN breakout return IGNORED - time expired (", hoursPassed, " hours > ", config.MaxBreakoutReturnHours(), " hours)");
                
            downBreakoutDetected = false;
            downBreakoutPrice = 0.0;
            downBreakoutTime = 0;
        }
    }
    
    // 4. Возврат после пробоя ВВЕРХ → сигнал SELL
    if(upBreakoutDetected && currentPrice <= (rangeHigh - onePoint))
    {
        // Цена вернулась в диапазон сверху
        // Проверяем время между выходом и возвращением
        int secondsPassed = (int)(currentTime - upBreakoutTime);
        int hoursPassed = secondsPassed / 3600;
        
        Print("CRITICAL: Return after UP breakout detected");
        Print("CRITICAL: Breakout time: ", TimeToString(upBreakoutTime));
        Print("CRITICAL: Return time: ", TimeToString(currentTime));
        Print("CRITICAL: Time elapsed: ", hoursPassed, " hours (max allowed: ", config.MaxBreakoutReturnHours(), " hours)");
        
        // Проверяем, что время возврата в пределах допустимого
        if(hoursPassed <= config.MaxBreakoutReturnHours())
        {
            Print("CRITICAL: Opening SELL position - valid breakout-return pattern within ", hoursPassed, " hours");
                
            OpenSellPosition();
            ResetBreakoutFlags();
            systemState = STATE_POSITION_OPEN;
            return;
        }
        else
        {
            // Время истекло, сбрасываем флаг
            Print("CRITICAL: UP breakout return IGNORED - time expired (", hoursPassed, " hours > ", config.MaxBreakoutReturnHours(), " hours)");
                
            upBreakoutDetected = false;
            upBreakoutPrice = 0.0;
            upBreakoutTime = 0;
        }
    }
    
    // Если цена внутри диапазона (но не возврат после пробоя), сбрасываем флаги
    // Это нужно для случаев, когда цена просто колеблется внутри диапазона
    if(currentPrice >= (rangeLow - breakoutDistance) && currentPrice <= (rangeHigh + breakoutDistance))
    {
        // Но только если не ждем возврата после пробоя
        if(!downBreakoutDetected && !upBreakoutDetected)
        {
            // Цена просто внутри диапазона, сбрасываем флаги на всякий случай
            if(downBreakoutDetected || upBreakoutDetected)
            {
                if(config.DebugMode())
                    Print("DEBUG: Price is inside range without prior breakout, resetting flags");
                ResetBreakoutFlags();
            }
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
    
    // Сбрасываем переменные отслеживания состояния цены
    wasPriceAboveRange = false;
    wasPriceBelowRange = false;
    wasPriceInRange = true; // По умолчанию считаем, что цена в диапазоне
    
    // Сбрасываем ограничения на торговлю (разрешаем оба направления)
    canTradeUp = true;
    canTradeDown = true;
    
    if(config.DebugMode())
        Print("DEBUG: System reset - Lot=", currentLotSize, ", Reversals=", currentReversalCount,
              ", Last direction: ", EnumToString(lastTradeDirection));
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
    Print("CRITICAL: Resetting breakout flags");
    Print("CRITICAL:   Before reset - DOWN breakout detected: ", downBreakoutDetected ? "YES" : "NO", 
          ", time: ", downBreakoutTime > 0 ? TimeToString(downBreakoutTime) : "N/A");
    Print("CRITICAL:   Before reset - UP breakout detected: ", upBreakoutDetected ? "YES" : "NO", 
          ", time: ", upBreakoutTime > 0 ? TimeToString(upBreakoutTime) : "N/A");
    
    upBreakoutDetected = false;
    downBreakoutDetected = false;
    upBreakoutPrice = 0.0;
    downBreakoutPrice = 0.0;
    upBreakoutTime = 0;
    downBreakoutTime = 0;
    
    Print("CRITICAL: Breakout flags reset. Up: ", upBreakoutDetected ? "YES" : "NO",
          ", Down: ", downBreakoutDetected ? "YES" : "NO");
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