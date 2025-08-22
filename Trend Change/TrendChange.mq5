//+------------------------------------------------------------------+
//|                                                 TrendChange.mq5 |
//|                                    Copyright 2023, TradingRobots |
//|                                             https://www.example.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, TradingRobots"
#property link      "https://www.example.com"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include "TrendChangeConfig.mqh"
#include "TrendChangeUtils.mqh"
#include "EngulfingPatternDetector.mqh"
#include "TrendChangeDetector.mqh"
#include "TradingOperations.mqh"

// Входные параметры
input int      InpMagicNumber = 123456;          // Уникальный идентификатор советника
input double   InpLotSize = 0.01;                // Базовый размер лота
input double   InpTakeProfitMultiplier = 2.0;     // Множитель для тейк-профита относительно стоп-лосса
input int      InpMaxDistanceToDayLow = 20;      // Макс. расстояние до минимума дня для покупок в пунктах
input int      InpMaxDistanceToDayHigh = 20;     // Макс. расстояние до максимума дня для продаж в пунктах
input bool     InpUseTrailingStop = true;        // Использовать трейлинг-стоп
input bool     InpCloseOnOppositeSignal = true;  // Закрывать при противоположном сигнале
input int      InpTradingStartHour = 0;          // Начало торговли (часы)
input int      InpTradingEndHour = 23;           // Окончание торговли (часы)
input bool     InpForceCloseAfterHours = false;  // Принудительно закрывать позиции вне торговых часов
input bool     InpValidateTwoDayExtremes = true; // Проверять что экстремум диапазона является экстремумом за сегодня и вчера
input bool     InpUseDailyMartingale = true;     // Использовать дневной мартингейл
input double   InpMartingaleMultiplier = 2.0;    // Мультипликатор лота после неудачной сделки
input bool     InpDebugMode = true;              // Режим отладки

// Глобальные переменные
CTrade            trade;                          // Объект для торговых операций
CTrendChangeConfig* config;                       // Конфигурация робота
CTrendChangeUtils* utils;                        // Вспомогательные функции
CEngulfingPatternDetector* patternDetector;      // Детектор паттернов поглощения
CTrendChangeDetector* trendChangeDetector;       // Детектор смены тренда
CTradingOperations* tradingOps;                  // Торговые операции

// Глобальные переменные для отслеживания состояния
datetime           lastBarTime = 0;               // Время последнего обработанного бара
bool               hasOpenPosition = false;       // Флаг наличия открытой позиции
ulong              positionTicket = 0;            // Тикет текущей позиции
ENUM_POSITION_TYPE positionType = WRONG_VALUE;   // Тип текущей позиции
double             positionOpenPrice = 0.0;        // Цена открытия позиции
double             stopLossPrice = 0.0;           // Цена стоп-лосса
double             takeProfitPrice = 0.0;         // Цена тейк-профита
bool               trailingStopActivated = false; // Флаг активации трейлинг-стопа

// Глобальные переменные для дневного мартингейла
datetime           currentTradingDay = 0;         // Текущий торговый день
double             currentLotSize = 0.0;          // Текущий размер лота с учетом мартингейла
bool               lastTradeWasLoss = false;      // Флаг: последняя сделка была убыточной или в безубыток

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Создаем объекты
   config = new CTrendChangeConfig(
      InpMagicNumber,
      InpLotSize,
      InpTakeProfitMultiplier,
      InpMaxDistanceToDayLow,
      InpMaxDistanceToDayHigh,
      InpUseTrailingStop,
      InpCloseOnOppositeSignal,
      InpTradingStartHour,
      InpTradingEndHour,
      InpForceCloseAfterHours,
      InpValidateTwoDayExtremes,
      InpUseDailyMartingale,
      InpMartingaleMultiplier,
      InpDebugMode
   );
   
   // Инициализируем мартингейл
   InitializeMartingale();
   
   utils = new CTrendChangeUtils(_Symbol, config.DebugMode());
   patternDetector = new CEngulfingPatternDetector(_Symbol, config.DebugMode());
   trendChangeDetector = new CTrendChangeDetector(_Symbol, config, config.DebugMode());
   tradingOps = new CTradingOperations(_Symbol, config.MagicNumber(), GetPointer(trade), config.DebugMode());
   
   // Настраиваем торговый объект
   trade.SetExpertMagicNumber(config.MagicNumber());
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(10);
   
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Удаляем все графические объекты
   ObjectsDeleteAll(0, 0, -1);
   
   // При удалении советника закрываем все позиции
   if(reason == REASON_REMOVE || reason == REASON_PROGRAM || reason == REASON_CLOSE)
   {
      tradingOps.CloseAllPositions();
   }
   
   // Освобождаем память
   if(CheckPointer(config) == POINTER_DYNAMIC)
      delete config;
   if(CheckPointer(utils) == POINTER_DYNAMIC)
      delete utils;
   if(CheckPointer(patternDetector) == POINTER_DYNAMIC)
      delete patternDetector;
   if(CheckPointer(trendChangeDetector) == POINTER_DYNAMIC)
      delete trendChangeDetector;
   if(CheckPointer(tradingOps) == POINTER_DYNAMIC)
      delete tradingOps;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Проверяем, нужно ли принудительно закрывать позиции вне торговых часов
   if(config.ForceCloseAfterHours() && !utils.IsTradingTimeAllowed(config.TradingStartHour(), config.TradingEndHour()))
   {
      tradingOps.CloseAllPositions();
      ResetPositionTracking();
      return;
   }
   
   // Проверяем, разрешено ли торговать в текущее время
   if(!utils.IsTradingTimeAllowed(config.TradingStartHour(), config.TradingEndHour()))
   {
      return;
   }
   
   // Проверяем, сформирован ли новый бар
   datetime currentBarTime = iTime(_Symbol, _Period, 1);
   if(currentBarTime == lastBarTime)
      return; // Новый бар ещё не сформирован
   
   lastBarTime = currentBarTime;
   
   // Проверяем начало нового торгового дня для сброса мартингейла
   CheckNewTradingDay();
   
   // Для расчётов требуется минимум 5 баров
   int totalBars = Bars(_Symbol, _Period);
   if(totalBars < 5)
   {
      return;
   }
   
   // Обновляем информацию о текущей позиции
   UpdatePositionInfo();
   
   
   // Проверяем наличие сигнала смены тренда
   CheckTrendChangeSignal();
   
   // Если есть открытая позиция, управляем ею
   if(hasOpenPosition)
   {
      ManagePosition();
   }
}

//+------------------------------------------------------------------+
//| Функция обновления информации о позиции                           |
//+------------------------------------------------------------------+
void UpdatePositionInfo()
{
   hasOpenPosition = false;
   positionTicket = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == config.MagicNumber())
      {
         hasOpenPosition = true;
         positionTicket = ticket;
         positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         stopLossPrice = PositionGetDouble(POSITION_SL);
         takeProfitPrice = PositionGetDouble(POSITION_TP);
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Функция проверки сигнала смены тренда                            |
//+------------------------------------------------------------------+
void CheckTrendChangeSignal()
{
   // Обрабатываем текущий бар в детекторе смены тренда
   datetime currentBarTime = iTime(_Symbol, _Period, 1);
   
   
   trendChangeDetector.ProcessBar(currentBarTime);
   
   // Определяем сигнал смены тренда
   bool uptrendSignal = trendChangeDetector.IsUptrendSignal();
   bool downtrendSignal = trendChangeDetector.IsDowntrendSignal();
   
   
   // Если есть сигнал на покупку и нет открытой позиции
   if(uptrendSignal && !hasOpenPosition)
   {
      // Проверяем фильтр расстояния до минимума дня
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double dayLow = iLow(_Symbol, PERIOD_D1, 0);
      double distanceToLow = utils.CalculateDistanceInPoints(currentPrice, dayLow);
      
      
      if(distanceToLow < config.MaxDistanceToDayLow())
      {
         OpenBuyPosition();
      }
   }
   
   // Если есть сигнал на продажу и нет открытой позиции
   if(downtrendSignal && !hasOpenPosition)
   {
      // Проверяем фильтр расстояния до максимума дня
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double dayHigh = iHigh(_Symbol, PERIOD_D1, 0);
      double distanceToHigh = utils.CalculateDistanceInPoints(dayHigh, currentPrice);
      
      
      if(distanceToHigh < config.MaxDistanceToDayHigh())
      {
         OpenSellPosition();
      }
   }
   
   // Если есть противоположный сигнал и включено правило закрытия
   if(hasOpenPosition && config.CloseOnOppositeSignal())
   {
      if((positionType == POSITION_TYPE_BUY && downtrendSignal) ||
         (positionType == POSITION_TYPE_SELL && uptrendSignal))
      {
         tradingOps.ClosePosition(positionTicket);
         ResetPositionTracking();
      }
   }
}

//+------------------------------------------------------------------+
//| Функция открытия позиции на покупку                               |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Рассчитываем стоп-лосс на основе минимума дня
   double dayLow = iLow(_Symbol, PERIOD_D1, 0);
   double stopLoss = dayLow - (2 * utils.GetPointValue()); // Минимум дня минус 2 пункта
   double stopLossPoints = utils.CalculateDistanceInPoints(ask, stopLoss);
   double takeProfitPoints = stopLossPoints * config.TakeProfitMultiplier();
   
   double takeProfit = ask + (takeProfitPoints * utils.GetPointValue());
   
   if(tradingOps.Buy(currentLotSize, _Symbol, stopLoss, takeProfit))
   {
      positionTicket = trade.ResultOrder();
      positionOpenPrice = ask;
      stopLossPrice = stopLoss;
      trailingStopActivated = false;
      
   }
}

//+------------------------------------------------------------------+
//| Функция открытия позиции на продажу                              |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Рассчитываем стоп-лосс на основе максимума дня
   double dayHigh = iHigh(_Symbol, PERIOD_D1, 0);
   double stopLoss = dayHigh + (2 * utils.GetPointValue()); // Максимум дня плюс 2 пункта
   double stopLossPoints = utils.CalculateDistanceInPoints(stopLoss, bid);
   double takeProfitPoints = stopLossPoints * config.TakeProfitMultiplier();
   
   double takeProfit = bid - (takeProfitPoints * utils.GetPointValue());
   
   if(tradingOps.Sell(currentLotSize, _Symbol, stopLoss, takeProfit))
   {
      positionTicket = trade.ResultOrder();
      positionOpenPrice = bid;
      stopLossPrice = stopLoss;
      trailingStopActivated = false;
      
   }
}

//+------------------------------------------------------------------+
//| Функция управления позицией                                      |
//+------------------------------------------------------------------+
void ManagePosition()
{
   if(!hasOpenPosition) return;
   
   // Переносим стоп-лосс на безубыток только один раз
   if(config.UseTrailingStop() && !trailingStopActivated)
   {
      double currentPrice = (positionType == POSITION_TYPE_BUY) ?
                            SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                            SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      // Рассчитываем размер изначального стоп-лосса в пунктах
      double originalStopLossPoints;
      if(positionType == POSITION_TYPE_BUY)
      {
         originalStopLossPoints = utils.CalculateDistanceInPoints(positionOpenPrice, stopLossPrice);
      }
      else
      {
         originalStopLossPoints = utils.CalculateDistanceInPoints(stopLossPrice, positionOpenPrice);
      }
      
      // Рассчитываем текущую прибыль в пунктах
      double currentProfitPoints;
      if(positionType == POSITION_TYPE_BUY)
      {
         currentProfitPoints = utils.CalculateDistanceInPoints(currentPrice, positionOpenPrice);
      }
      else
      {
         currentProfitPoints = utils.CalculateDistanceInPoints(positionOpenPrice, currentPrice);
      }
      
      
      // Если прибыль >= размеру стоп-лосса, переносим стоп на цену открытия (безубыток)
      if(currentProfitPoints >= originalStopLossPoints)
      {
         double newStopLoss = positionOpenPrice; // Просто цена открытия
         
         if(tradingOps.ModifyStopLoss(positionTicket, newStopLoss))
         {
            stopLossPrice = newStopLoss;
            trailingStopActivated = true; // Отмечаем, что уже перенесли
            
            // При переносе стопа на безубыток считаем это как потенциальный убыток для мартингейла
            lastTradeWasLoss = true;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Функция сброса отслеживания позиции                              |
//+------------------------------------------------------------------+
void ResetPositionTracking()
{
   // Проверяем результат сделки перед сбросом
   if(positionTicket > 0)
      CheckTradeResult();
   
   hasOpenPosition = false;
   positionTicket = 0;
   positionType = WRONG_VALUE;
   positionOpenPrice = 0.0;
   stopLossPrice = 0.0;
   takeProfitPrice = 0.0;
   trailingStopActivated = false;
   
   // Обновляем мартингейл после закрытия позиции
   UpdateMartingale();
}

//+------------------------------------------------------------------+
//| Функция инициализации мартингейла                                |
//+------------------------------------------------------------------+
void InitializeMartingale()
{
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   currentTradingDay = today;
   currentLotSize = config.LotSize();
   lastTradeWasLoss = false;
}

//+------------------------------------------------------------------+
//| Функция проверки нового торгового дня                           |
//+------------------------------------------------------------------+
void CheckNewTradingDay()
{
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   
   if(today != currentTradingDay)
   {
      // Новый день - сбрасываем мартингейл
      currentTradingDay = today;
      currentLotSize = config.LotSize();
      lastTradeWasLoss = false;
   }
}

//+------------------------------------------------------------------+
//| Функция обновления мартингейла после закрытия сделки            |
//+------------------------------------------------------------------+
void UpdateMartingale()
{
   if(!config.UseDailyMartingale())
      return;
   
   if(lastTradeWasLoss)
   {
      // Увеличиваем лот после убыточной/безубыточной сделки
      currentLotSize *= config.MartingaleMultiplier();
   }
   else
   {
      // Сбрасываем к базовому размеру после прибыльной сделки
      currentLotSize = config.LotSize();
   }
   
   // Сбрасываем флаг
   lastTradeWasLoss = false;
}

//+------------------------------------------------------------------+
//| Функция проверки результата закрытой сделки                     |
//+------------------------------------------------------------------+
void CheckTradeResult()
{
   // Проверяем историю сделок для определения результата последней сделки
   if(!HistorySelectByPosition(positionTicket))
      return;
   
   int totalDeals = HistoryDealsTotal();
   if(totalDeals < 2) // Нужно минимум 2 сделки (открытие и закрытие)
      return;
   
   // Получаем последнюю сделку закрытия
   ulong dealTicket = HistoryDealGetTicket(totalDeals - 1);
   if(dealTicket <= 0)
      return;
   
   if(HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == positionTicket)
   {
      double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      
      double totalResult = profit + swap + commission;
      
      // Считаем сделку убыточной, если результат <= 0
      lastTradeWasLoss = (totalResult <= 0.0);
   }
}
//+------------------------------------------------------------------+