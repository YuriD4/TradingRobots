//+------------------------------------------------------------------+
//| ManipulationH4.mq5                                               |
//| Торговый эксперт для стратегии на H4 таймфрейме                  |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#property strict

// Входные параметры для торговли
input double   InpLotSize = 0.25;           // Размер лота
input int      InpStopLossPoints = 20;      // Стоп-лосс в пунктах от хай/лоу
input int      InpMaxStopLossPoints = 200;  // Максимальный стоп-лосс в пунктах
input double   InpTakeProfitMultiplier = 2.0; // Множитель тейк-профита относительно стоп-лосса
input int      InpPriceRisePoints = 100;    // Минимальный рост цены в пунктах для активации флага
input int      InpMinBarHeightPoints = 200; // Минимальная высота бара в пунктах
input int      InpMaxEntryDistancePoints = 100; // Максимальное расстояние от хай/лоу предыдущего бара для входа
input int      InpStartTradingHour = 18;    // Час начала торговли (0-23)
input int      InpEndTradingHour = 20;      // Час окончания торговли (0-23)

// Глобальные переменные для торговли
CTrade         trade;                        // Объект для торговых операций
bool           inBuyPosition = false;        // Флаг наличия позиции на покупку
bool           inSellPosition = false;       // Флаг наличия позиции на продажу
ulong          currentBuyTicket = 0;         // Тикет текущей позиции на покупку
ulong          currentSellTicket = 0;        // Тикет текущей позиции на продажу
int            pointCoef = 1;                // Коэффициент для правильного расчета пунктов

// Глобальные переменные для отслеживания условий входа
bool           sellFlagActive = false;       // Флаг для входа в продажу
bool           buyFlagActive = false;        // Флаг для входа в покупку
double         prevBarHigh = 0.0;            // Максимум предыдущего бара
double         prevBarLow = 0.0;             // Минимум предыдущего бара
datetime       currentBarOpenTime = 0;       // Время открытия текущего бара
datetime       lastM30CheckTime = 0;         // Время последней проверки на M30
bool           positionOpenedInCurrentBar = false; // Флаг открытия позиции в текущем баре

// Переменные для отслеживания "бара защиты"
bool           waitingForProtectionBarBuy = false;   // Ожидаем бар защиты для покупки
bool           waitingForProtectionBarSell = false;  // Ожидаем бар защиты для продажи
datetime       firstM30BarTimeBuy = 0;              // Время первого M30 бара для покупки
datetime       firstM30BarTimeSell = 0;             // Время первого M30 бара для продажи

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Настройка объекта торговли
   trade.SetExpertMagicNumber(123457);  // Устанавливаем уникальный идентификатор для сделок
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(100);     // Допустимое проскальзывание в пунктах
   
   // Определяем коэффициент для расчета пунктов в зависимости от валютной пары
   string symbolName = _Symbol;
   if(StringFind(symbolName, "JPY") != -1 || StringFind(symbolName, "jpy") != -1)
      pointCoef = 100; // Для йеновых пар
   else
      pointCoef = 10000; // Для всех остальных пар
   
   // Проверяем наличие открытых позиций при перезапуске советника
   CheckExistingPositions();
   
   // Инициализируем значения предыдущего бара
   prevBarHigh = iHigh(_Symbol, PERIOD_H4, 1);
   prevBarLow = iLow(_Symbol, PERIOD_H4, 1);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // При деинициализации удаляем все объекты стрелок, созданные экспертом
   ObjectsDeleteAll(0, 0, OBJ_ARROW);
   
   // Закрываем все открытые позиции при удалении советника с графика
   if(reason == REASON_REMOVE || reason == REASON_PROGRAM || reason == REASON_CLOSE)
   {
      CloseAllPositions();
   }
}

//+------------------------------------------------------------------+
//| Функция проверки существующих позиций                            |
//+------------------------------------------------------------------+
void CheckExistingPositions()
{
   inBuyPosition = false;
   inSellPosition = false;
   currentBuyTicket = 0;
   currentSellTicket = 0;
   
   // Проверяем все открытые позиции
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      // Проверяем, принадлежит ли позиция текущему символу и нашему эксперту
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
         PositionGetInteger(POSITION_MAGIC) == trade.RequestMagic())
      {
         // Определяем тип позиции (покупка или продажа)
         long positionType = PositionGetInteger(POSITION_TYPE);
         if(positionType == POSITION_TYPE_BUY)
         {
            inBuyPosition = true;
            currentBuyTicket = ticket;
         }
         else if(positionType == POSITION_TYPE_SELL)
         {
            inSellPosition = true;
            currentSellTicket = ticket;
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
      
      // Закрываем только позиции текущего символа и нашего эксперта
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
         PositionGetInteger(POSITION_MAGIC) == trade.RequestMagic())
      {
         trade.PositionClose(ticket);
      }
   }
   
   // Сбрасываем флаги позиций
   inBuyPosition = false;
   inSellPosition = false;
   currentBuyTicket = 0;
   currentSellTicket = 0;
}

//+------------------------------------------------------------------+
//| Функция открытия позиции на покупку                              |
//+------------------------------------------------------------------+
bool OpenBuyPosition(double stopLossPrice)
{
   // Проверяем, нет ли уже открытой позиции на покупку
   if(inBuyPosition) return false;
   
   // Рассчитываем тейк-профит как множитель от стоп-лосса
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopLossDistance = currentPrice - stopLossPrice;
   double takeProfitPrice = currentPrice + (stopLossDistance * InpTakeProfitMultiplier);
   
   // Открываем позицию на покупку
   if(trade.Buy(InpLotSize, _Symbol, 0, stopLossPrice, takeProfitPrice))
   {
      inBuyPosition = true;
      currentBuyTicket = trade.ResultOrder();
      return true;
   }
   else
   {
      return false;
   }
}

//+------------------------------------------------------------------+
//| Функция открытия позиции на продажу                              |
//+------------------------------------------------------------------+
bool OpenSellPosition(double stopLossPrice)
{
   // Проверяем, нет ли уже открытой позиции на продажу
   if(inSellPosition) return false;
   
   // Рассчитываем тейк-профит как множитель от стоп-лосса
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLossDistance = stopLossPrice - currentPrice;
   double takeProfitPrice = currentPrice - (stopLossDistance * InpTakeProfitMultiplier);
   
   // Открываем позицию на продажу
   if(trade.Sell(InpLotSize, _Symbol, 0, stopLossPrice, takeProfitPrice))
   {
      inSellPosition = true;
      currentSellTicket = trade.ResultOrder();
      return true;
   }
   else
   {
      return false;
   }
}

//+------------------------------------------------------------------+
//| Функция проверки окончания текущего бара                         |
//+------------------------------------------------------------------+
bool IsCurrentBarEnding()
{
   datetime currentTime = TimeCurrent();
   datetime barEndTime = currentBarOpenTime + PeriodSeconds(PERIOD_H4);
   
   // Проверяем, осталось ли менее 1 минуты до окончания бара
   if(barEndTime - currentTime <= 60)
   {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Функция проверки разрешенного времени для торговли               |
//+------------------------------------------------------------------+
bool IsAllowedTradingTime()
{
   MqlDateTime currentTime;
   TimeToStruct(TimeCurrent(), currentTime);
   
   // Проверяем, находится ли текущее время в разрешенном диапазоне для торговли
   if(currentTime.hour >= InpStartTradingHour && currentTime.hour < InpEndTradingHour)
   {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Функция проверки, является ли лоу предыдущего бара самым низким  |
//| значением текущего дня                                           |
//+------------------------------------------------------------------+
bool IsPrevBarLowLowestOfDay()
{
   // Получаем время предыдущего бара
   datetime prevBarTime = iTime(_Symbol, PERIOD_H4, 1);
   
   // Преобразуем время в структуру для получения даты
   MqlDateTime prevBarMqlTime;
   TimeToStruct(prevBarTime, prevBarMqlTime);
   
   // Создаем время начала текущего дня (00:00)
   MqlDateTime dayStartMqlTime;
   dayStartMqlTime.year = prevBarMqlTime.year;
   dayStartMqlTime.mon = prevBarMqlTime.mon;
   dayStartMqlTime.day = prevBarMqlTime.day;
   dayStartMqlTime.hour = 0;
   dayStartMqlTime.min = 0;
   dayStartMqlTime.sec = 0;
   
   datetime dayStartTime = StructToTime(dayStartMqlTime);
   
   // Получаем лоу предыдущего бара
   double prevBarLowValue = iLow(_Symbol, PERIOD_H4, 1);
   
   // Проверяем все бары текущего дня до предыдущего бара
   int barIndex = 2; // Начинаем с бара перед предыдущим
   datetime barTime = iTime(_Symbol, PERIOD_H4, barIndex);
   
   // Проходим по всем барам текущего дня
   while(barTime >= dayStartTime)
   {
      double barLow = iLow(_Symbol, PERIOD_H4, barIndex);
      
      // Если нашли бар с более низким лоу, то предыдущий бар не является самым низким
      if(barLow < prevBarLowValue)
      {
         return false;
      }
      
      // Переходим к следующему бару
      barIndex++;
      barTime = iTime(_Symbol, PERIOD_H4, barIndex);
   }
   
   // Если мы дошли до этой точки, значит лоу предыдущего бара - самое низкое значение дня
   return true;
}

//+------------------------------------------------------------------+
//| Функция проверки, является ли хай предыдущего бара самым высоким |
//| значением текущего дня                                           |
//+------------------------------------------------------------------+
bool IsPrevBarHighHighestOfDay()
{
   // Получаем время предыдущего бара
   datetime prevBarTime = iTime(_Symbol, PERIOD_H4, 1);
   
   // Преобразуем время в структуру для получения даты
   MqlDateTime prevBarMqlTime;
   TimeToStruct(prevBarTime, prevBarMqlTime);
   
   // Создаем время начала текущего дня (00:00)
   MqlDateTime dayStartMqlTime;
   dayStartMqlTime.year = prevBarMqlTime.year;
   dayStartMqlTime.mon = prevBarMqlTime.mon;
   dayStartMqlTime.day = prevBarMqlTime.day;
   dayStartMqlTime.hour = 0;
   dayStartMqlTime.min = 0;
   dayStartMqlTime.sec = 0;
   
   datetime dayStartTime = StructToTime(dayStartMqlTime);
   
   // Получаем хай предыдущего бара
   double prevBarHighValue = iHigh(_Symbol, PERIOD_H4, 1);
   
   // Проверяем все бары текущего дня до предыдущего бара
   int barIndex = 2; // Начинаем с бара перед предыдущим
   datetime barTime = iTime(_Symbol, PERIOD_H4, barIndex);
   
   // Проходим по всем барам текущего дня
   while(barTime >= dayStartTime)
   {
      double barHigh = iHigh(_Symbol, PERIOD_H4, barIndex);
      
      // Если нашли бар с более высоким хаем, то предыдущий бар не является самым высоким
      if(barHigh > prevBarHighValue)
      {
         return false;
      }
      
      // Переходим к следующему бару
      barIndex++;
      barTime = iTime(_Symbol, PERIOD_H4, barIndex);
   }
   
   // Если мы дошли до этой точки, значит хай предыдущего бара - самое высокое значение дня
   return true;
}

//+------------------------------------------------------------------+
//| Функция проверки, соответствует ли высота предыдущего бара       |
//| минимальному требованию                                          |
//+------------------------------------------------------------------+
bool IsPrevBarHeightSufficient()
{
   // Получаем хай и лоу предыдущего бара
   double high = iHigh(_Symbol, PERIOD_H4, 1);
   double low = iLow(_Symbol, PERIOD_H4, 1);
   
   // Рассчитываем высоту бара в пунктах
   double barHeight = (high - low) / (_Point * pointCoef / 1000);
   
   // Проверяем, соответствует ли высота минимальному требованию
   return (barHeight >= InpMinBarHeightPoints);
}

//+------------------------------------------------------------------+
//| Функция проверки, закрылся ли M30 бар выше лоу предыдущего H4 бара |
//+------------------------------------------------------------------+
bool IsM30BarClosedAbovePrevH4Low()
{
   // Получаем цену закрытия последнего завершенного M30 бара
   double m30ClosePrice = iClose(_Symbol, PERIOD_M30, 1);
   
   // Проверяем, закрылся ли M30 бар выше лоу предыдущего H4 бара
   return (m30ClosePrice > prevBarLow);
}

//+------------------------------------------------------------------+
//| Функция проверки, закрылся ли M30 бар ниже хая предыдущего H4 бара |
//+------------------------------------------------------------------+
bool IsM30BarClosedBelowPrevH4High()
{
   // Получаем цену закрытия последнего завершенного M30 бара
   double m30ClosePrice = iClose(_Symbol, PERIOD_M30, 1);
   
   // Проверяем, закрылся ли M30 бар ниже хая предыдущего H4 бара
   return (m30ClosePrice < prevBarHigh);
}

//+------------------------------------------------------------------+
//| Функция проверки, пора ли выполнять проверку на M30 таймфрейме    |
//+------------------------------------------------------------------+
bool IsTimeToCheckM30()
{
   datetime currentTime = TimeCurrent();
   
   // Получаем время открытия текущего M30 бара
   datetime currentM30Time = iTime(_Symbol, PERIOD_M30, 0);
   
   // Если прошло 30 минут с момента последней проверки или начался новый M30 бар
   if(currentTime - lastM30CheckTime >= 30 * 60 || currentM30Time > lastM30CheckTime)
   {
      lastM30CheckTime = currentTime;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Функция проверки условий "бара защиты" для покупки              |
//+------------------------------------------------------------------+
bool IsProtectionBarValidForBuy()
{
   // Получаем данные текущего M30 бара (индекс 0 - текущий незакрытый, индекс 1 - последний закрытый)
   double m30Open = iOpen(_Symbol, PERIOD_M30, 1);
   double m30Close = iClose(_Symbol, PERIOD_M30, 1);
   double m30Low = iLow(_Symbol, PERIOD_M30, 1);
   
   // Проверяем условия "бара защиты" для покупки:
   // 1. Open этого M30 бара > Low H4
   // 2. Close этого M30 бара > Low H4
   // 3. Low этого M30 бара < Low предыдущего H4 бара
   if(m30Open > prevBarLow && m30Close > prevBarLow && m30Low < prevBarLow)
   {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Функция проверки условий "бара защиты" для продажи              |
//+------------------------------------------------------------------+
bool IsProtectionBarValidForSell()
{
   // Получаем данные текущего M30 бара (индекс 1 - последний закрытый)
   double m30Open = iOpen(_Symbol, PERIOD_M30, 1);
   double m30Close = iClose(_Symbol, PERIOD_M30, 1);
   double m30High = iHigh(_Symbol, PERIOD_M30, 1);
   
   // Проверяем условия "бара защиты" для продажи:
   // 1. Open этого M30 бара < High H4
   // 2. Close этого M30 бара < High H4
   // 3. High этого M30 бара > High предыдущего H4 бара
   if(m30Open < prevBarHigh && m30Close < prevBarHigh && m30High > prevBarHigh)
   {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Обновляем информацию о текущих позициях
   CheckExistingPositions();
   
   // Проверяем, сформирован ли новый бар
   datetime currentBarTime = iTime(_Symbol, PERIOD_H4, 0);
   if(currentBarTime != currentBarOpenTime)
   {
      // Если начался новый бар, закрываем все позиции
      if(currentBarOpenTime != 0 && (inBuyPosition || inSellPosition))
      {
         CloseAllPositions();
      }
      
      // Обновляем время открытия текущего бара
      currentBarOpenTime = currentBarTime;
      
      // Обновляем значения предыдущего бара
      prevBarHigh = iHigh(_Symbol, PERIOD_H4, 1);
      prevBarLow = iLow(_Symbol, PERIOD_H4, 1);
      
      // Проверяем дополнительные условия для предыдущего бара
      bool isSufficientHeight = IsPrevBarHeightSufficient();
      double barHeight = (prevBarHigh - prevBarLow) / _Point;
      
      // Сбрасываем флаги
      sellFlagActive = false;
      buyFlagActive = false;
      positionOpenedInCurrentBar = false; // Сбрасываем флаг открытия позиции в новом баре
      
      // Сбрасываем флаги "бара защиты"
      waitingForProtectionBarBuy = false;
      waitingForProtectionBarSell = false;
      firstM30BarTimeBuy = 0;
      firstM30BarTimeSell = 0;
      
   }
   
   // Получаем текущие цены
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_LAST);
   double currentHigh = iHigh(_Symbol, PERIOD_H4, 0);
   double currentLow = iLow(_Symbol, PERIOD_H4, 0);
   
   // Проверяем условия для активации флагов
   
   // Для продажи: если цена поднялась выше хая предыдущего бара минимум на InpPriceRisePoints пунктов
   if(!sellFlagActive && currentHigh > prevBarHigh + (InpPriceRisePoints * _Point * pointCoef / 1000))
   {
      sellFlagActive = true;
   }
   
   // Для покупки: если цена опустилась ниже лоу предыдущего бара минимум на InpPriceRisePoints пунктов
   if(!buyFlagActive && currentLow < prevBarLow - (InpPriceRisePoints * _Point * pointCoef / 1000))
   {
      buyFlagActive = true;
   }
   
   // Проверяем условия для входа в позицию только каждые 30 минут
   if(IsTimeToCheckM30())
   {
      // ЛОГИКА ДЛЯ ПРОДАЖИ с "баром защиты"
      if(sellFlagActive && !inSellPosition && !positionOpenedInCurrentBar
         && IsPrevBarHeightSufficient())
      {
         // Если еще не ждем бар защиты, проверяем первый M30 бар
         if(!waitingForProtectionBarSell)
         {
            // Проверяем, закрылся ли первый M30 бар ниже хая предыдущего H4 бара
            if(IsM30BarClosedBelowPrevH4High())
            {
               // Активируем ожидание "бара защиты"
               waitingForProtectionBarSell = true;
               firstM30BarTimeSell = iTime(_Symbol, PERIOD_M30, 1);
            }
         }
         else
         {
            // Ждем "бар защиты" - проверяем, появился ли новый M30 бар после первого
            datetime currentM30Time = iTime(_Symbol, PERIOD_M30, 1);
            if(currentM30Time > firstM30BarTimeSell)
            {
               // Проверяем условия "бара защиты" для продажи
               if(IsProtectionBarValidForSell())
               {
                  // Проверяем остальные условия для входа
                  if(currentPrice < prevBarHigh && IsAllowedTradingTime()
                     && (prevBarHigh - currentPrice) / (_Point * pointCoef / 1000) <= InpMaxEntryDistancePoints)
                  {
                     // Рассчитываем стоп-лосс
                     double stopLossPrice = currentHigh + (InpStopLossPoints * _Point * pointCoef / 1000);
                     double stopLossDistance = stopLossPrice - currentPrice;
                     
                     // Если стоп-лосс больше максимального, ограничиваем его
                     if(stopLossDistance > (InpMaxStopLossPoints * _Point * pointCoef / 1000))
                     {
                        stopLossPrice = currentPrice + (InpMaxStopLossPoints * _Point * pointCoef / 1000);
                     }
                     
                     // Открываем позицию на продажу
                     if(OpenSellPosition(stopLossPrice))
                     {
                        positionOpenedInCurrentBar = true;
                        sellFlagActive = false;
                        waitingForProtectionBarSell = false;
                     }
                  }
               }
               else
               {
                  // "Бар защиты" не прошел проверку - сбрасываем ожидание
                  waitingForProtectionBarSell = false;
                  sellFlagActive = false;
               }
            }
         }
      }
      
      // ЛОГИКА ДЛЯ ПОКУПКИ с "баром защиты"
      if(buyFlagActive && !inBuyPosition && !positionOpenedInCurrentBar
         && IsPrevBarHeightSufficient())
      {
         // Если еще не ждем бар защиты, проверяем первый M30 бар
         if(!waitingForProtectionBarBuy)
         {
            // Проверяем, закрылся ли первый M30 бар выше лоу предыдущего H4 бара
            if(IsM30BarClosedAbovePrevH4Low())
            {
               // Активируем ожидание "бара защиты"
               waitingForProtectionBarBuy = true;
               firstM30BarTimeBuy = iTime(_Symbol, PERIOD_M30, 1);
            }
         }
         else
         {
            // Ждем "бар защиты" - проверяем, появился ли новый M30 бар после первого
            datetime currentM30Time = iTime(_Symbol, PERIOD_M30, 1);
            if(currentM30Time > firstM30BarTimeBuy)
            {
               // Проверяем условия "бара защиты" для покупки
               if(IsProtectionBarValidForBuy())
               {
                  // Проверяем остальные условия для входа
                  if(currentPrice > prevBarLow && IsAllowedTradingTime()
                     && (currentPrice - prevBarLow) / (_Point * pointCoef / 1000) <= InpMaxEntryDistancePoints)
                  {
                     // Рассчитываем стоп-лосс
                     double stopLossPrice = currentLow - (InpStopLossPoints * _Point * pointCoef / 1000);
                     double stopLossDistance = currentPrice - stopLossPrice;
                     
                     // Если стоп-лосс больше максимального, ограничиваем его
                     if(stopLossDistance > (InpMaxStopLossPoints * _Point * pointCoef / 1000))
                     {
                        stopLossPrice = currentPrice - (InpMaxStopLossPoints * _Point * pointCoef / 1000);
                     }
                     
                     // Открываем позицию на покупку
                     if(OpenBuyPosition(stopLossPrice))
                     {
                        positionOpenedInCurrentBar = true;
                        buyFlagActive = false;
                        waitingForProtectionBarBuy = false;
                     }
                  }
               }
               else
               {
                  // "Бар защиты" не прошел проверку - сбрасываем ожидание
                  waitingForProtectionBarBuy = false;
                  buyFlagActive = false;
               }
            }
         }
      }
   }
   
   // Проверяем, не заканчивается ли текущий бар
   if(IsCurrentBarEnding() && (inBuyPosition || inSellPosition))
   {
      CloseAllPositions();
   }
}
