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
#include "LevelsCalculator.mqh"
#include "TradingUtils.mqh"
#include "TradingOperations.mqh"
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
input bool     InpTradeMondayEnabled = true;    // Разрешить торговлю в понедельник
input bool     InpDebugMode = true;             // Режим отладки

// Глобальные переменные для торговли
CTrade         trade;                           // Объект для торговых операций
CLevelsCalculator* levelsCalculator;            // Калькулятор уровней
CTradingUtils* tradingUtils;                    // Вспомогательные функции
CTradingOperations* tradingOperations;          // Торговые операции
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
   
   // Создаем объекты для работы с уровнями, утилитами и торговыми операциями
   levelsCalculator = new CLevelsCalculator(_Symbol, InpDebugMode);
   tradingUtils = new CTradingUtils(_Symbol, InpTradeMondayEnabled, InpDebugMode);
   tradingOperations = new CTradingOperations(_Symbol, InpMagicNumber, GetPointer(trade), InpDebugMode);
   
   // Рассчитываем правильное значение пункта для золота
   pointValue = tradingUtils.CalculatePointValue();
   
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
      tradingOperations.CloseAllPositions();
   }
   
   // Освобождаем память
   if(CheckPointer(levelsCalculator) == POINTER_DYNAMIC)
      delete levelsCalculator;
   if(CheckPointer(tradingUtils) == POINTER_DYNAMIC)
      delete tradingUtils;
   if(CheckPointer(tradingOperations) == POINTER_DYNAMIC)
      delete tradingOperations;
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
   levelsCalculator.CalculatePreviousDayHighLow(prevDayHigh, prevDayLow);
   
   // Сбрасываем флаги
   ResetDailyFlags();
   
   // Рассчитываем базовый размер лота
   baseLotSize = tradingUtils.CalculateBaseLotSize();
   
   if(InpDebugMode)
   {
      Print("DEBUG: Инициализация дня завершена. prevDayHigh: ", prevDayHigh,
            ", prevDayLow: ", prevDayLow, ", baseLotSize: ", baseLotSize);
   }
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
      double lotSize = tradingOperations.CalculateLotSize(baseLotSize, InpLotMultiplier, currentTradeSequence);
      tradingOperations.OpenNextTradeInSequence(true, lotSize, pointValue, InpRecoveryStopLossPoints, InpRecoveryTakeProfitPoints, lastTradeTicket, waitingForHourlyBreakout);
      
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
      double lotSize = tradingOperations.CalculateLotSize(baseLotSize, InpLotMultiplier, currentTradeSequence);
      tradingOperations.OpenNextTradeInSequence(false, lotSize, pointValue, InpRecoveryStopLossPoints, InpRecoveryTakeProfitPoints, lastTradeTicket, waitingForHourlyBreakout);
      
      waitingForHourlyBreakout = false;
   }
}


//+------------------------------------------------------------------+
//| Функция проверки пробоя уровней                                  |
//+------------------------------------------------------------------+
void CheckBreakouts()
{
   if(dayTradingComplete) return;
   
   // Проверяем, разрешена ли торговля в текущий день
   if(!tradingUtils.IsTradingAllowedToday()) return;
   
   // Валидация уровней - если уровни недействительны, не торгуем
   if(!levelsCalculator.AreBreakoutLevelsValid(prevDayHigh, prevDayLow))
   {
      if(InpDebugMode)
      {
         Print("DEBUG: Уровни пробоя недействительны. Торговля пропущена.");
      }
      return;
   }
   
   // Проверяем, прошло ли достаточно времени после смены дня
   if(!tradingUtils.IsEnoughTimePassedAfterDayChange())
   {
      if(InpDebugMode)
      {
         Print("DEBUG: Недостаточно времени прошло после смены дня. Ожидание...");
      }
      return;
   }
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_LAST);
   double buyBreakoutLevel = prevDayHigh + (InpBreakoutPoints * pointValue);
   double sellBreakoutLevel = prevDayLow - (InpBreakoutPoints * pointValue);
   
   if(InpDebugMode)
   {
      Print("DEBUG: Текущая цена: ", currentPrice,
            ", Уровень пробоя вверх: ", buyBreakoutLevel,
            ", Уровень пробоя вниз: ", sellBreakoutLevel);
   }
   
   // Проверяем пробой максимума (сигнал на покупку)
   if(!buyBreakoutTriggered && currentPrice > buyBreakoutLevel)
   {
      buyBreakoutTriggered = true;
      if(InpDebugMode)
      {
         Print("DEBUG: Пробой максимума! Цена: ", currentPrice, " > ", buyBreakoutLevel);
      }
      
      // Если нет активных последовательностей, начинаем новую
      if(!isInBuySequence && !isInSellSequence)
      {
         if(tradingOperations.StartBuySequence(baseLotSize, pointValue, InpStopLossPoints, InpTakeProfitPoints, lastTradeTicket))
         {
            isInBuySequence = true;
            currentTradeSequence = 1;
         }
      }
   }
   
   // Проверяем пробой минимума (сигнал на продажу)
   if(!sellBreakoutTriggered && currentPrice < sellBreakoutLevel)
   {
      sellBreakoutTriggered = true;
      if(InpDebugMode)
      {
         Print("DEBUG: Пробой минимума! Цена: ", currentPrice, " < ", sellBreakoutLevel);
      }
      
      // Если нет активных последовательностей, начинаем новую
      if(!isInBuySequence && !isInSellSequence)
      {
         if(tradingOperations.StartSellSequence(baseLotSize, pointValue, InpStopLossPoints, InpTakeProfitPoints, lastTradeTicket))
         {
            isInSellSequence = true;
            currentTradeSequence = 1;
         }
      }
   }
}



//+------------------------------------------------------------------+
//| Функция открытия противоположной позиции после убытка            |
//+------------------------------------------------------------------+
void OpenOppositePosition()
{
   if(dayTradingComplete) return;
   
   // Проверяем, разрешена ли торговля в текущий день
   if(!tradingUtils.IsTradingAllowedToday()) return;
   
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
      double lotSize = tradingOperations.CalculateLotSize(baseLotSize, InpLotMultiplier, currentTradeSequence);
      tradingOperations.OpenOppositePosition(isInBuySequence, isInSellSequence, lotSize, pointValue, InpRecoveryStopLossPoints, InpRecoveryTakeProfitPoints, lastTradeTicket);
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
   if(tradingUtils.IsTimeToClosePositions())
   {
      tradingOperations.CloseAllPositions();
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
      tradingOperations.CloseAllPositions();
      
      // Инициализируем данные нового дня
      InitializeDailyData();
   }
   
   // Проверяем пробои уровней
   CheckBreakouts();
   
   // Проверяем пробои часовых уровней (для сделок начиная с 3-й)
   CheckHourlyBreakouts();
}