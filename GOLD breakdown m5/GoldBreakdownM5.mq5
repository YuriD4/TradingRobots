//+------------------------------------------------------------------+
//| GoldBreakdownM5.mq5                                              |
//| GOLD Breakdown M5 Trading Robot                                  |
//| Торгует пробои максимумов/минимумов предыдущего дня на золоте    |
//+------------------------------------------------------------------+
//| Логика торговли:                                                 |
//| 1. Отслеживает максимум и минимум предыдущего дня                |
//| 2. BUY: цена пробивает на 50 пунктов выше максимума пред. дня    |
//| 3. SELL: цена пробивает на 50 пунктов ниже минимума пред. дня    |
//| 4. Размер лота: 0.01 на каждую $1000 депозита                   |
//| 5. SL и TP: по 200 пунктов                                       |
//| 6. При убытке: открывается противоположная сделка                |
//| 7. Продолжается до прибыли или достижения макс. кол-ва сделок    |
//| 8. Сброс логики каждый новый торговый день                       |
//| Примечание: 100 пунктов = $1 в цене золота                      |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#property strict

// Входные параметры
input int      InpBreakoutPoints = 50;          // Пробой в пунктах (по умолчанию 50)

// Параметры для первой сделки (при пробое)
input int      InpStopLossPoints = 200;         // Стоп-лосс первой сделки в пунктах (по умолчанию 200)
input int      InpTakeProfitPoints = 200;       // Тейк-профит первой сделки в пунктах (по умолчанию 200)

// Параметры для восстановительных сделок (после стопа)
input int      InpRecoveryStopLossPoints = 150; // Стоп-лосс восстановительных сделок в пунктах (по умолчанию 150)
input int      InpRecoveryTakeProfitPoints = 150; // Тейк-профит восстановительных сделок в пунктах (по умолчанию 150)

input double   InpLotMultiplier = 1.0;          // Множитель лота (по умолчанию 1.0)
input int      InpMaxAdditionalTrades = 5;      // Макс. доп. сделок после первого убытка (по умолчанию 5)
input int      InpDynamicLevelsAfterStops = 3;  // После скольких стопов включать часовые уровни (по умолчанию 3)
input int      InpMagicNumber = 555777;         // Уникальный идентификатор советника
input bool     InpDebugMode = true;             // Режим отладки

// Глобальные переменные для торговли
CTrade         trade;                           // Объект для торговых операций
double         pointValue = 0.0;                // Правильное значение пункта для золота
double         prevDayHigh = 0.0;               // Максимум предыдущего дня
double         prevDayLow = 0.0;                // Минимум предыдущего дня
datetime       currentDay = 0;                  // Текущий день для отслеживания смены дня
bool           buyBreakoutTriggered = false;    // Флаг пробоя максимума
bool           sellBreakoutTriggered = false;   // Флаг пробоя минимума
int            currentTradeSequence = 0;        // Текущая последовательность сделок
bool           isInBuySequence = false;         // Флаг последовательности покупок
bool           isInSellSequence = false;        // Флаг последовательности продаж
double         baseLotSize = 0.0;               // Базовый размер лота
ulong          lastTradeTicket = 0;             // Тикет последней сделки
bool           dayTradingComplete = false;      // Флаг завершения торговли на день

// Переменные для динамических уровней (настраивается параметром InpDynamicLevelsAfterStops)
bool           waitingForHourlyBreakout = false; // Флаг ожидания пробоя часовых уровней
double         hourlyHigh = 0.0;                // Максимум за последний час
double         hourlyLow = 0.0;                 // Минимум за последний час
bool           hourlyBuyBreakoutTriggered = false;  // Флаг пробоя часового максимума
bool           hourlySellBreakoutTriggered = false; // Флаг пробоя часового минимума

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Проверяем, что торгуем золотом
   if(StringFind(_Symbol, "GOLD") == -1 && StringFind(_Symbol, "XAU") == -1)
   {
   }
   
   // Настройка объекта торговли
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(10);
   
   // Рассчитываем правильное значение пункта для золота
   CalculatePointValue();
   
   // Инициализируем переменные
   InitializeDailyData();
   
   if(InpDebugMode)
   {
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Удаляем все возможные графические объекты
   ObjectsDeleteAll(0, 0, -1);
   
   // При удалении советника закрываем все позиции
   if(reason == REASON_REMOVE || reason == REASON_PROGRAM || reason == REASON_CLOSE)
   {
      CloseAllPositions();
   }
}

//+------------------------------------------------------------------+
//| Функция инициализации данных дня                                 |
//+------------------------------------------------------------------+
void InitializeDailyData()
{
   datetime currentTime = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   
   // Устанавливаем текущий день
   currentDay = StringToTime(StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day));
   
   // Получаем данные предыдущего дня
   CalculatePreviousDayHighLow();
   
   // Сбрасываем флаги
   ResetDailyFlags();
   
   // Рассчитываем базовый размер лота
   baseLotSize = CalculateBaseLotSize();
   
   if(InpDebugMode)
   {
   }
}

//+------------------------------------------------------------------+
//| Функция расчета максимума и минимума за период 16:00-20:00       |
//| предыдущего дня с проверкой на дневные экстремумы                |
//+------------------------------------------------------------------+
void CalculatePreviousDayHighLow()
{
   // Получаем текущее время
   datetime currentTime = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   
   // Получаем дневные максимум и минимум предыдущего дня
   double dailyHigh = iHigh(_Symbol, PERIOD_D1, 1);
   double dailyLow = iLow(_Symbol, PERIOD_D1, 1);
   
   // Формируем время начала и конца периода предыдущего дня (16:00-20:00)
   datetime prevDayStart = StringToTime(StringFormat("%04d.%02d.%02d 16:00", dt.year, dt.mon, dt.day - 1));
   datetime prevDayEnd = StringToTime(StringFormat("%04d.%02d.%02d 20:00", dt.year, dt.mon, dt.day - 1));
   
   // Получаем данные за период 16:00-20:00 предыдущего дня (M5 = 5-минутные бары)
   double highArray[], lowArray[];
   datetime timeArray[];
   
   // Копируем данные за последние несколько дней, чтобы найти нужный период
   int barsCount = 500; // Достаточно баров для поиска нужного периода
   
   if(CopyHigh(_Symbol, PERIOD_M5, 0, barsCount, highArray) < 0 ||
      CopyLow(_Symbol, PERIOD_M5, 0, barsCount, lowArray) < 0 ||
      CopyTime(_Symbol, PERIOD_M5, 0, barsCount, timeArray) < 0)
   {
      // Если не удалось получить данные, используем fallback
      prevDayHigh = dailyHigh;
      prevDayLow = dailyLow;
      
      if(prevDayHigh <= 0 || prevDayLow <= 0)
      {
         prevDayHigh = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         prevDayLow = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      }
      return;
   }
   
   // Ищем максимум и минимум в период 16:00-20:00 предыдущего дня
   double sessionHigh = 0.0;
   double sessionLow = 999999.0;
   bool foundData = false;
   
   for(int i = 0; i < barsCount; i++)
   {
      // Проверяем, попадает ли время бара в нужный период
      if(timeArray[i] >= prevDayStart && timeArray[i] <= prevDayEnd)
      {
         foundData = true;
         
         if(highArray[i] > sessionHigh) sessionHigh = highArray[i];
         if(lowArray[i] < sessionLow) sessionLow = lowArray[i];
      }
   }
   
   // Если не нашли данные за нужный период, используем дневные уровни
   if(!foundData || sessionHigh <= 0 || sessionLow <= 0)
   {
      prevDayHigh = dailyHigh;
      prevDayLow = dailyLow;
      
      if(prevDayHigh <= 0 || prevDayLow <= 0)
      {
         prevDayHigh = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         prevDayLow = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      }
      return;
   }
   
   // Применяем фильтр: используем уровни сессии только если они совпадают с дневными экстремумами
   // Для HIGH: используем sessionHigh только если он равен dailyHigh
   // Для LOW: используем sessionLow только если он равен dailyLow
   
   double tolerance = 0.01; // Допуск для сравнения цен (1 пункт)
   
   // Проверяем HIGH
   if(MathAbs(sessionHigh - dailyHigh) <= tolerance)
   {
      prevDayHigh = sessionHigh; // Максимум сессии совпадает с дневным максимумом
   }
   else
   {
      prevDayHigh = 0.0; // Максимум сессии не является дневным максимумом - не торгуем пробой вверх
   }
   
   // Проверяем LOW
   if(MathAbs(sessionLow - dailyLow) <= tolerance)
   {
      prevDayLow = sessionLow; // Минимум сессии совпадает с дневным минимумом
   }
   else
   {
      prevDayLow = 999999.0; // Минимум сессии не является дневным минимумом - не торгуем пробой вниз
   }
   
   // Если ни один из уровней не подходит, используем дневные уровни как fallback
   if(prevDayHigh <= 0 && prevDayLow >= 999999.0)
   {
      prevDayHigh = dailyHigh;
      prevDayLow = dailyLow;
   }
}

//+------------------------------------------------------------------+
//| Функция расчета правильного значения пункта для золота           |
//+------------------------------------------------------------------+
void CalculatePointValue()
{
   // Для золота с 2 знаками после запятой (2000.50):
   // 100 пунктов = 1.00 = $1
   // Значит 1 пункт = 0.01
   pointValue = _Point;
}

//+------------------------------------------------------------------+
//| Функция сброса дневных флагов                                    |
//+------------------------------------------------------------------+
void ResetDailyFlags()
{
   buyBreakoutTriggered = false;
   sellBreakoutTriggered = false;
   currentTradeSequence = 0;
   isInBuySequence = false;
   isInSellSequence = false;
   lastTradeTicket = 0;
   dayTradingComplete = false;
   
   // Сбрасываем флаги динамических уровней
   waitingForHourlyBreakout = false;
   hourlyHigh = 0.0;
   hourlyLow = 0.0;
   hourlyBuyBreakoutTriggered = false;
   hourlySellBreakoutTriggered = false;
}

//+------------------------------------------------------------------+
//| Функция расчета базового размера лота                            |
//+------------------------------------------------------------------+
double CalculateBaseLotSize()
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double lotSize = (accountBalance / 1000.0) * 0.01; // 0.01 лота на каждую $1000
   
   // Ограничиваем минимальный и максимальный размер лота
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   
   // Округляем до шага изменения размера лота
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Функция проверки смены дня                                       |
//+------------------------------------------------------------------+
bool IsNewDay()
{
   datetime currentTime = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   
   datetime todayStart = StringToTime(StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day));
   
   if(todayStart != currentDay)
   {
      currentDay = todayStart;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Функция проверки времени закрытия позиций (22:00)                |
//+------------------------------------------------------------------+
bool IsTimeToClosePositions()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   // Проверяем, наступило ли время 22:00 или позже
   if(dt.hour >= 22)
   {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Функция расчета уровней за последний час                         |
//+------------------------------------------------------------------+
void CalculateHourlyLevels()
{
   // Получаем данные за последний час (12 закрытых баров по M5)
   // start_pos = 1 чтобы исключить текущий незакрытый бар
   double highArray[], lowArray[];
   
   if(CopyHigh(_Symbol, PERIOD_M5, 1, 12, highArray) < 0 ||
      CopyLow(_Symbol, PERIOD_M5, 1, 12, lowArray) < 0)
   {
      // Если не удалось получить данные, используем iHigh/iLow
      hourlyHigh = iHigh(_Symbol, PERIOD_M5, 1);
      hourlyLow = iLow(_Symbol, PERIOD_M5, 1);
      
      // Проверяем корректность данных
      if(hourlyHigh <= 0 || hourlyLow <= 0)
      {
         hourlyHigh = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         hourlyLow = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      }
      return;
   }
   
   // Находим максимум и минимум за последний час
   // Массив упорядочен от настоящего к прошлому: [0] = самый недавний закрытый бар
   hourlyHigh = highArray[0];
   hourlyLow = lowArray[0];
   
   for(int i = 1; i < 12; i++)
   {
      if(highArray[i] > hourlyHigh) hourlyHigh = highArray[i];
      if(lowArray[i] < hourlyLow) hourlyLow = lowArray[i];
   }
   
   // Сбрасываем флаги пробоя часовых уровней
   hourlyBuyBreakoutTriggered = false;
   hourlySellBreakoutTriggered = false;
}

//+------------------------------------------------------------------+
//| Функция проверки пробоя часовых уровней                          |
//+------------------------------------------------------------------+
void CheckHourlyBreakouts()
{
   if(!waitingForHourlyBreakout) return;
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_LAST);
   double hourlyBuyBreakoutLevel = hourlyHigh + (InpBreakoutPoints * pointValue);
   double hourlySellBreakoutLevel = hourlyLow - (InpBreakoutPoints * pointValue);
   
   if(InpDebugMode)
   {
   }
   
   // Проверяем пробой часового максимума
   if(!hourlyBuyBreakoutTriggered && currentPrice > hourlyBuyBreakoutLevel)
   {
      hourlyBuyBreakoutTriggered = true;
      
      if(InpDebugMode)
      {
      }
      
      // Открываем следующую сделку в последовательности
      // Переключаемся на покупки независимо от текущей последовательности
      isInSellSequence = false;
      isInBuySequence = true;
      OpenNextTradeInSequence();
      
      waitingForHourlyBreakout = false;
   }
   
   // Проверяем пробой часового минимума
   if(!hourlySellBreakoutTriggered && currentPrice < hourlySellBreakoutLevel)
   {
      hourlySellBreakoutTriggered = true;
      
      if(InpDebugMode)
      {
      }
      
      // Открываем следующую сделку в последовательности
      // Переключаемся на продажи независимо от текущей последовательности
      isInBuySequence = false;
      isInSellSequence = true;
      OpenNextTradeInSequence();
      
      waitingForHourlyBreakout = false;
   }
}

//+------------------------------------------------------------------+
//| Функция открытия следующей сделки в последовательности           |
//+------------------------------------------------------------------+
void OpenNextTradeInSequence()
{
   if(dayTradingComplete) return;
   
   // Рассчитываем размер лота для текущей сделки в последовательности
   double lotSize = baseLotSize * MathPow(InpLotMultiplier, currentTradeSequence - 1);
   
   // Ограничиваем максимальный размер лота
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(lotSize > maxLot) lotSize = maxLot;
   
   // Округляем до шага изменения размера лота
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   if(isInBuySequence)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double stopLoss = ask - (InpRecoveryStopLossPoints * pointValue);
      double takeProfit = ask + (InpRecoveryTakeProfitPoints * pointValue);
      
      if(InpDebugMode)
      {
      }
      
      if(trade.Buy(lotSize, _Symbol, 0, stopLoss, takeProfit))
      {
         lastTradeTicket = trade.ResultOrder();
      }
      else
      {
         // Если не удалось открыть сделку, сбрасываем ожидание
         waitingForHourlyBreakout = false;
      }
   }
   else if(isInSellSequence)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double stopLoss = bid + (InpRecoveryStopLossPoints * pointValue);
      double takeProfit = bid - (InpRecoveryTakeProfitPoints * pointValue);
      
      if(InpDebugMode)
      {
      }
      
      if(trade.Sell(lotSize, _Symbol, 0, stopLoss, takeProfit))
      {
         lastTradeTicket = trade.ResultOrder();
      }
      else
      {
         // Если не удалось открыть сделку, сбрасываем ожидание
         waitingForHourlyBreakout = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Функция проверки пробоя уровней                                  |
//+------------------------------------------------------------------+
void CheckBreakouts()
{
   if(dayTradingComplete) return;
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_LAST);
   double buyBreakoutLevel = prevDayHigh + (InpBreakoutPoints * pointValue);
   double sellBreakoutLevel = prevDayLow - (InpBreakoutPoints * pointValue);
   
   // Проверяем пробой максимума (сигнал на покупку)
   if(!buyBreakoutTriggered && currentPrice > buyBreakoutLevel)
   {
      buyBreakoutTriggered = true;
      if(InpDebugMode)
      {
      }
      
      // Если нет активных последовательностей, начинаем новую
      if(!isInBuySequence && !isInSellSequence)
      {
         StartBuySequence();
      }
   }
   
   // Проверяем пробой минимума (сигнал на продажу)
   if(!sellBreakoutTriggered && currentPrice < sellBreakoutLevel)
   {
      sellBreakoutTriggered = true;
      if(InpDebugMode)
      {
      }
      
      // Если нет активных последовательностей, начинаем новую
      if(!isInBuySequence && !isInSellSequence)
      {
         StartSellSequence();
      }
   }
}

//+------------------------------------------------------------------+
//| Функция начала последовательности покупок                        |
//+------------------------------------------------------------------+
void StartBuySequence()
{
   if(dayTradingComplete) return;
   
   isInBuySequence = true;
   currentTradeSequence = 1;
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopLoss = ask - (InpStopLossPoints * pointValue);
   double takeProfit = ask + (InpTakeProfitPoints * pointValue);
   // Для первой сделки используем базовый размер лота
   double lotSize = baseLotSize;
   
   if(InpDebugMode)
   {
   }
   
   if(trade.Buy(lotSize, _Symbol, 0, stopLoss, takeProfit))
   {
      lastTradeTicket = trade.ResultOrder();
   }
   else
   {
      isInBuySequence = false;
   }
}

//+------------------------------------------------------------------+
//| Функция начала последовательности продаж                         |
//+------------------------------------------------------------------+
void StartSellSequence()
{
   if(dayTradingComplete) return;
   
   isInSellSequence = true;
   currentTradeSequence = 1;
   
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLoss = bid + (InpStopLossPoints * pointValue);
   double takeProfit = bid - (InpTakeProfitPoints * pointValue);
   // Для первой сделки используем базовый размер лота
   double lotSize = baseLotSize;
   
   if(InpDebugMode)
   {
   }
   
   if(trade.Sell(lotSize, _Symbol, 0, stopLoss, takeProfit))
   {
      lastTradeTicket = trade.ResultOrder();
   }
   else
   {
      isInSellSequence = false;
   }
}

//+------------------------------------------------------------------+
//| Функция открытия противоположной позиции после убытка            |
//+------------------------------------------------------------------+
void OpenOppositePosition()
{
   if(dayTradingComplete) return;
   
   currentTradeSequence++;
   
   if(InpDebugMode)
   {
   }
   
   // Проверяем, не превышено ли максимальное количество сделок
   // currentTradeSequence = 1 (первая), 2 (вторая), 3 (третья)...
   // InpMaxAdditionalTrades = 1 означает максимум 2 сделки (1 первая + 1 дополнительная)
   if(currentTradeSequence > (InpMaxAdditionalTrades + 1))
   {
      dayTradingComplete = true;
      if(InpDebugMode)
      {
      }
      return;
   }
   
   // Проверяем, нужно ли переходить на динамические уровни
   // Логика настраивается параметром InpDynamicLevelsAfterStops:
   // 1 = после 1-го стопа (со 2-й сделки), 2 = после 2-го стопа (с 3-й сделки), 3 = после 3-го стопа (с 4-й сделки)
   if(currentTradeSequence > InpDynamicLevelsAfterStops)
   {
      // Используем часовые уровни
      CalculateHourlyLevels();
      waitingForHourlyBreakout = true;
      
      if(InpDebugMode)
      {
      }
   }
   else
   {
      // Для 2-й сделки используем обычную логику немедленного открытия
      double lotSize = baseLotSize * MathPow(InpLotMultiplier, currentTradeSequence - 1);
      
      // Ограничиваем максимальный размер лота
      double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      if(lotSize > maxLot) lotSize = maxLot;
      
      // Округляем до шага изменения размера лота
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      lotSize = MathFloor(lotSize / lotStep) * lotStep;
      
      if(isInBuySequence)
      {
         // Переключаемся на продажи
         isInBuySequence = false;
         isInSellSequence = true;
         
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double stopLoss = bid + (InpRecoveryStopLossPoints * pointValue);
         double takeProfit = bid - (InpRecoveryTakeProfitPoints * pointValue);
         
         if(InpDebugMode)
         {
         }
         
         if(trade.Sell(lotSize, _Symbol, 0, stopLoss, takeProfit))
         {
            lastTradeTicket = trade.ResultOrder();
         }
      }
      else if(isInSellSequence)
      {
         // Переключаемся на покупки
         isInSellSequence = false;
         isInBuySequence = true;
         
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double stopLoss = ask - (InpRecoveryStopLossPoints * pointValue);
         double takeProfit = ask + (InpRecoveryTakeProfitPoints * pointValue);
         
         if(InpDebugMode)
         {
         }
         
         if(trade.Buy(lotSize, _Symbol, 0, stopLoss, takeProfit))
         {
            lastTradeTicket = trade.ResultOrder();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Функция закрытия всех позиций                                    |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         trade.PositionClose(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| Функция обработки закрытия позиций                               |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   // Обрабатываем только сделки нашего советника
   if(trans.symbol != _Symbol) return;
   
   // Проверяем закрытие позиции
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong dealTicket = trans.deal;
      if(dealTicket > 0)
      {
         if(HistoryDealSelect(dealTicket))
         {
            long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
            if(dealMagic == InpMagicNumber)
            {
               long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
               double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
               
               if(dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL)
               {
                  if(InpDebugMode)
                  {
                  }
                  
                  if(dealProfit > 0)
                  {
                     // Прибыльная сделка - завершаем торговлю на день
                     dayTradingComplete = true;
                     ResetSequenceFlags();
                  }
                  else if(dealProfit < 0)
                  {
                     // Убыточная сделка - открываем противоположную
                     OpenOppositePosition();
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Функция сброса флагов последовательности                         |
//+------------------------------------------------------------------+
void ResetSequenceFlags()
{
   isInBuySequence = false;
   isInSellSequence = false;
   currentTradeSequence = 0;
   lastTradeTicket = 0;
   
   // Сбрасываем флаги динамических уровней
   waitingForHourlyBreakout = false;
   hourlyHigh = 0.0;
   hourlyLow = 0.0;
   hourlyBuyBreakoutTriggered = false;
   hourlySellBreakoutTriggered = false;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Проверяем время закрытия позиций (22:00)
   if(IsTimeToClosePositions())
   {
      CloseAllPositions();
      dayTradingComplete = true;
      return;
   }
   
   // Проверяем смену дня
   if(IsNewDay())
   {
      if(InpDebugMode)
      {
      }
      
      // Закрываем все открытые позиции при смене дня
      CloseAllPositions();
      
      // Инициализируем данные нового дня
      InitializeDailyData();
   }
   
   // Проверяем пробои уровней
   CheckBreakouts();
   
   // Проверяем пробои часовых уровней (для сделок начиная с 3-й)
   CheckHourlyBreakouts();
}