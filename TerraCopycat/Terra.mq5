//+------------------------------------------------------------------+
//| Terra.mq5                                                        |
//| Торговый советник Terra на основе ценовых движений                |
//+------------------------------------------------------------------+
//| Логика торговли:                                                 |
//| 1. Условия покупки (BUY):                                        |
//|    - Падение цены не менее чем на InpDropPoints пунктов за 4 бара |
//|    - Ни один из 4 последних баров не должен быть больше InpMaxBarSize |
//|    - Тейк-профит устанавливается на InpTakeProfit пунктов выше цены входа |
//| 2. Условия продажи (SELL):                                       |
//|    - Рост цены не менее чем на InpDropPoints пунктов за 4 бара    |
//|    - Ни один из 4 последних баров не должен быть больше InpMaxBarSize |
//|    - Тейк-профит устанавливается на InpTakeProfit пунктов ниже цены входа |
//| 3. Сетка ордеров (упрощенная логика):                            |
//|    - Для BUY: после закрытия каждого бара проверяем расстояние между текущей ценой |
//|      и ценой последнего ордера. Если оно > InpGridDistance пунктов, открываем новый ордер |
//|    - Для SELL: аналогичная логика для растущей цены              |
//|    - Макс. количество ордеров в сетке: InpMaxGridOrders          |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#property strict

// Параметры времени торговли
input int      InpStartHour = 2;            // Час начала торговли (по серверу)
input int      InpEndHour = 23;             // Час окончания торговли (по серверу)

// Входные параметры для определения условий входа
input int      InpDropPoints = 20;          // Минимальное падение за 4 бара для входа (в пунктах)
input int      InpMaxBarSize = 15;          // Максимальный размер бара (High-Low) в пунктах
input double   InpTakeProfit = 11.0;        // Размер тейк профита (в пунктах)
input double   InpTpMultiplier = 1.0;       // Множитель для тейк профита в зависимости от количества ордеров

// Параметры сетки ордеров
input int      InpGridDistance = 40;        // Расстояние между ордерами сетки (в пунктах)
input int      InpMaxGridOrders = 5;        // Максимальное количество ордеров в сетке (1-10)
input bool     InpUseGrid = true;          // Использовать сетку ордеров
input bool     InpAllowOppositePositions = false; // Разрешить открывать позиции в противоположном направлении

// Входные параметры для торговли
input double   InpLotSize = 0.1;            // Размер лота (фиксированный)
input bool     InpDynamicLot = true;        // Использовать динамический расчет лота
input double   InpDynamicLotRatio = 0.01;   // Размер лота на каждую $1000 баланса (0.01 = 1/100 лота)
input double   InpLotMultiplier = 1.0;      // Множитель для размера лота при усреднении
input int      InpMagicNumber = 789123;     // Уникальный идентификатор советника
input bool     InpDebugMode = true;         // Режим отладки (вывод дополнительных логов)

// Глобальные переменные для торговли
CTrade         trade;                        // Объект для торговых операций
int            orderCounter = 0;             // Счетчик открытых ордеров для сетки
double         lastBuyPrice = 0.0;           // Цена последнего ордера на покупку
double         lastSellPrice = 0.0;          // Цена последнего ордера на продажу
double         totalOrderVolume = 0.0;       // Общий объем открытых ордеров
double         averageEntryPrice = 0.0;      // Средняя цена входа для всех ордеров
int            pointCoef = 1;                // Коэффициент для правильного расчета пунктов

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Terra запущен.");
   
   // Настройка объекта торговли
   trade.SetExpertMagicNumber(InpMagicNumber);  // Устанавливаем уникальный идентификатор для сделок
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(10);      // Допустимое проскальзывание в пунктах
   
   // Определяем коэффициент для расчета пунктов в зависимости от валютной пары
   // Для йеновых пар 1 пункт - это третий знак после запятой
   string symbolName = _Symbol;
   if(StringFind(symbolName, "JPY") != -1 || StringFind(symbolName, "jpy") != -1)
      pointCoef = 100; // Для йеновых пар
   else
      pointCoef = 10000; // Для всех остальных пар
   
   if(InpDebugMode)
   {
      Print("*** DEBUG INFO ***");
      Print("Trading hours: ", InpStartHour, ":00 - ", InpEndHour, ":00 (server time)");
      Print("Symbol: ", _Symbol);
      Print("Point: ", _Point);
      Print("Point coefficient: ", pointCoef);
      Print("Lot multiplier: ", InpLotMultiplier);
      Print("Dynamic lot: ", InpDynamicLot ? "Yes" : "No");
      if(InpDynamicLot) Print("Dynamic lot ratio: ", InpDynamicLotRatio, " per $1000");
      Print("Take profit: ", InpTakeProfit, " points");
      Print("Take profit multiplier: ", InpTpMultiplier);
      Print("Minimum price movement for entry: ", InpDropPoints, " points");
      Print("Maximum bar size: ", InpMaxBarSize, " points");
      Print("Grid distance: ", InpGridDistance, " points");
      Print("Use grid: ", InpUseGrid ? "Yes" : "No");
      Print("Max grid orders: ", InpMaxGridOrders);
      Print("******************");
   }
   
   // Проверяем наличие открытых позиций при перезапуске советника
   UpdatePositionInfo();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // При деинициализации удаляем все объекты, созданные экспертом
   ObjectsDeleteAll(0, 0, OBJ_ARROW);
   
   // Закрываем все открытые позиции при удалении советника с графика
   if(reason == REASON_REMOVE || reason == REASON_PROGRAM || reason == REASON_CLOSE)
   {
      CloseAllPositions();
   }
}

//+------------------------------------------------------------------+
//| Функция обновления информации о позициях                         |
//+------------------------------------------------------------------+
void UpdatePositionInfo()
{
   orderCounter = 0;
   lastBuyPrice = 0.0;
   lastSellPrice = 0.0;
   totalOrderVolume = 0.0;
   double totalWeightedPrice = 0.0;
   
   // Переменные для отслеживания экстремальных цен для каждого типа позиций
   double lowestBuyPrice = 0.0;
   double highestSellPrice = 0.0;
   bool hasBuyPositions = false;
   bool hasSellPositions = false;
   
   // Проверяем все открытые позиции
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      // Проверяем, принадлежит ли позиция текущему символу и нашему эксперту
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         orderCounter++;
         
         double posVolume = PositionGetDouble(POSITION_VOLUME);
         double posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         totalOrderVolume += posVolume;
         totalWeightedPrice += posVolume * posPrice;
         
         // Отслеживаем экстремальные цены для каждого типа позиций
         if(posType == POSITION_TYPE_BUY)
         {
            hasBuyPositions = true;
            // Для BUY нам нужна самая низкая цена для корректного расчета расстояния сетки
            if(lowestBuyPrice == 0.0 || posPrice < lowestBuyPrice)
               lowestBuyPrice = posPrice;
         }
         else if(posType == POSITION_TYPE_SELL)
         {
            hasSellPositions = true;
            // Для SELL нам нужна самая высокая цена для корректного расчета расстояния сетки
            if(highestSellPrice == 0.0 || posPrice > highestSellPrice)
               highestSellPrice = posPrice;
         }
      }
   }
   
   // Обновляем lastBuyPrice и lastSellPrice
   if(hasBuyPositions)
      lastBuyPrice = lowestBuyPrice;
   
   if(hasSellPositions)
      lastSellPrice = highestSellPrice;
   
   // Рассчитываем среднюю цену входа
   if(totalOrderVolume > 0)
      averageEntryPrice = totalWeightedPrice / totalOrderVolume;
   else
      averageEntryPrice = 0.0;
   
   if(InpDebugMode && orderCounter > 0)
   {
      Print("Информация о позициях обновлена:");
      Print("  Кол-во ордеров: ", orderCounter);
      Print("  Общий объем: ", totalOrderVolume);
      Print("  Средняя цена входа: ", averageEntryPrice);
      if(hasBuyPositions) Print("  Последняя цена ордера BUY: ", lastBuyPrice);
      if(hasSellPositions) Print("  Последняя цена ордера SELL: ", lastSellPrice);
      if(hasBuyPositions) Print("  Тип позиций: BUY");
      if(hasSellPositions) Print("  Тип позиций: SELL");
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
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         trade.PositionClose(ticket);
         Print("Позиция закрыта: ", ticket);
      }
   }
   
   // Сбрасываем счетчики
   orderCounter = 0;
   lastBuyPrice = 0.0;
   lastSellPrice = 0.0;
   totalOrderVolume = 0.0;
   averageEntryPrice = 0.0;
}

//+------------------------------------------------------------------+
//| Функция проверки наличия позиций                                 |
//+------------------------------------------------------------------+
bool HasPositions(ENUM_POSITION_TYPE posType)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      // Проверяем, принадлежит ли позиция текущему символу, нашему эксперту и типу
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
         PositionGetInteger(POSITION_TYPE) == posType)
      {
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Функция проверки времени торговли                                |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentHour = dt.hour;
   
   // Проверяем, находится ли текущий час в диапазоне торговли
   if(InpStartHour <= InpEndHour)
   {
      // Обычный случай: например, с 2 до 23
      return (currentHour >= InpStartHour && currentHour <= InpEndHour);
   }
   else
   {
      // Случай через полночь: например, с 22 до 2
      return (currentHour >= InpStartHour || currentHour <= InpEndHour);
   }
}

//+------------------------------------------------------------------+
//| Функция расчета размера лота на основе баланса                   |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   double lotSize = InpLotSize; // По умолчанию используем фиксированный размер
   
   if(InpDynamicLot)
   {
      // Получаем текущий баланс счета
      double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      
      // Рассчитываем размер лота на основе баланса (каждая $1000 = InpDynamicLotRatio лота)
      lotSize = (accountBalance / 1000.0) * InpDynamicLotRatio;
      
      // Ограничиваем минимальный размер лота
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(lotSize < minLot)
         lotSize = minLot;
      
      // Ограничиваем максимальный размер лота
      double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      if(lotSize > maxLot)
         lotSize = maxLot;
      
      // Округляем до шага изменения размера лота
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      lotSize = MathFloor(lotSize / lotStep) * lotStep;
      
      if(InpDebugMode)
      {
         Print("Динамический расчет лота:");
         Print("  Баланс счета: $", accountBalance);
         Print("  Коэффициент: ", InpDynamicLotRatio, " лота на $1000");
         Print("  Расчетный размер лота: ", lotSize);
      }
   }
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Функция открытия позиции на покупку                              |
//+------------------------------------------------------------------+
bool OpenBuyPosition(double takeProfitPrice, bool isGrid = false)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double lotSize = CalculateLotSize(); // Рассчитываем базовый размер лота
   int prevOrderCounter = orderCounter; // Запоминаем текущее количество ордеров
   
   // Если это сетка, рассчитываем размер лота с учетом множителя
   // Для первого ордера используем базовый размер лота
   // Начиная со второго ордера применяем множитель
   if(isGrid)
   {
      if(orderCounter >= 1) // Для второго ордера и далее
      {
         double baseLot = CalculateLotSize(); // Используем динамический расчет лота
         lotSize = baseLot * MathPow(InpLotMultiplier, orderCounter - 1);
         if(InpDebugMode) Print("Сетка: расчет размера лота = ", baseLot, " * ", InpLotMultiplier, "^", (orderCounter - 1), " = ", lotSize);
      }
      else
      {
         // Для первого ордера используем базовый размер лота
         lotSize = CalculateLotSize();
         if(InpDebugMode) Print("Сетка: используем базовый размер лота = ", lotSize);
      }
   }
   
   if(InpDebugMode) Print("Открываем позицию BUY: Лот=", lotSize, ", цена=", ask, ", TP=", takeProfitPrice);
   
   // Открываем позицию на покупку
   if(trade.Buy(lotSize, _Symbol, 0, 0, takeProfitPrice))
   {
      Print("Открыта позиция на покупку: Лот=", lotSize, ", цена=", ask, ", TP=", takeProfitPrice);
      lastBuyPrice = ask;
      UpdatePositionInfo();
      
      // Проверяем, увеличился ли счетчик ордеров
      if(InpDebugMode) {
         Print("Счетчик ордеров до открытия: ", prevOrderCounter);
         Print("Счетчик ордеров после открытия: ", orderCounter);
         Print("Изменение счетчика: ", (orderCounter - prevOrderCounter));
      }
      
      return true;
   }
   else
   {
      Print("Ошибка открытия позиции на покупку: ", trade.ResultRetcode(), ", ", trade.ResultRetcodeDescription());
      return false;
   }
}

//+------------------------------------------------------------------+
//| Функция открытия позиции на продажу                              |
//+------------------------------------------------------------------+
bool OpenSellPosition(double takeProfitPrice, bool isGrid = false)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double lotSize = CalculateLotSize(); // Рассчитываем базовый размер лота
   int prevOrderCounter = orderCounter; // Запоминаем текущее количество ордеров
   
   // Если это сетка, рассчитываем размер лота с учетом множителя
   // Для первого ордера используем базовый размер лота
   // Начиная со второго ордера применяем множитель
   if(isGrid)
   {
      if(orderCounter >= 1) // Для второго ордера и далее
      {
         double baseLot = CalculateLotSize(); // Используем динамический расчет лота
         lotSize = baseLot * MathPow(InpLotMultiplier, orderCounter - 1);
         if(InpDebugMode) Print("Сетка: расчет размера лота = ", baseLot, " * ", InpLotMultiplier, "^", (orderCounter - 1), " = ", lotSize);
      }
      else
      {
         // Для первого ордера используем базовый размер лота
         lotSize = CalculateLotSize();
         if(InpDebugMode) Print("Сетка: используем базовый размер лота = ", lotSize);
      }
   }
   
   if(InpDebugMode) Print("Открываем позицию SELL: Лот=", lotSize, ", цена=", bid, ", TP=", takeProfitPrice);
   
   // Открываем позицию на продажу
   if(trade.Sell(lotSize, _Symbol, 0, 0, takeProfitPrice))
   {
      Print("Открыта позиция на продажу: Лот=", lotSize, ", цена=", bid, ", TP=", takeProfitPrice);
      lastSellPrice = bid;
      UpdatePositionInfo();
      
      // Проверяем, увеличился ли счетчик ордеров
      if(InpDebugMode) {
         Print("Счетчик ордеров до открытия: ", prevOrderCounter);
         Print("Счетчик ордеров после открытия: ", orderCounter);
         Print("Изменение счетчика: ", (orderCounter - prevOrderCounter));
      }
      
      return true;
   }
   else
   {
      Print("Ошибка открытия позиции на продажу: ", trade.ResultRetcode(), ", ", trade.ResultRetcodeDescription());
      return false;
   }
}

//+------------------------------------------------------------------+
//| Функция расчёта и обновления тейк-профита для сетки              |
//+------------------------------------------------------------------+
void UpdateTakeProfit()
{
   UpdatePositionInfo();
   
   if(orderCounter == 0) return;
   
   // Целевая прибыль в абсолютном выражении (10 пунктов = 1 пипс)
   // Умножаем на количество ордеров и на множитель TP
   double targetProfitPoints = InpTakeProfit * orderCounter * InpTpMultiplier;
   double targetProfitPrice = targetProfitPoints * _Point * 10; // Перевод в абсолютное значение цены
   
   if(InpDebugMode) {
      Print("Расчет целевой прибыли:");
      Print("  Базовый TP = ", InpTakeProfit, " пунктов");
      Print("  Количество ордеров = ", orderCounter);
      Print("  Множитель TP = ", InpTpMultiplier);
      Print("  Итоговый TP = ", targetProfitPoints, " пунктов");
   }
   double newTakeProfit = 0.0;
   
   // Определяем тип позиции (покупка или продажа)
   bool isBuy = false;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         break;
      }
   }
   
   // Рассчитываем целевую прибыль для одного ордера с базовым размером лота
   double baseLotSize = CalculateLotSize();
   double singleOrderProfit = baseLotSize * targetProfitPoints * 10; // Прибыль в пунктах * 10 (для перевода в пипсы)
   
   // Рассчитываем новый тейк-профит в зависимости от типа позиции
   if(isBuy)
   {
      // Для позиций на покупку
      // Формула: TP = averageEntryPrice + (singleOrderProfit / totalOrderVolume)
      newTakeProfit = averageEntryPrice + (singleOrderProfit * _Point / totalOrderVolume);
      
      if(InpDebugMode) {
         Print("Расчет нового TP для BUY:");
         Print("  Средняя цена входа = ", averageEntryPrice);
         Print("  Целевая прибыль для одного ордера (", baseLotSize, " лот) = ", singleOrderProfit, " пунктов");
         Print("  Общий объем ордеров = ", totalOrderVolume);
         Print("  Новый TP = ", averageEntryPrice, " + (", singleOrderProfit, " * ", _Point, " / ", totalOrderVolume, ") = ", newTakeProfit);
      }
   }
   else
   {
      // Для позиций на продажу
      // Формула: TP = averageEntryPrice - (singleOrderProfit / totalOrderVolume)
      newTakeProfit = averageEntryPrice - (singleOrderProfit * _Point / totalOrderVolume);
      
      if(InpDebugMode) {
         Print("Расчет нового TP для SELL:");
         Print("  Средняя цена входа = ", averageEntryPrice);
         Print("  Целевая прибыль для одного ордера (", baseLotSize, " лот) = ", singleOrderProfit, " пунктов");
         Print("  Общий объем ордеров = ", totalOrderVolume);
         Print("  Новый TP = ", averageEntryPrice, " - (", singleOrderProfit, " * ", _Point, " / ", totalOrderVolume, ") = ", newTakeProfit);
      }
   }
   
   // Обновляем тейк-профит для всех позиций
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         if(trade.PositionModify(ticket, 0, newTakeProfit))
         {
            Print("Тейк-профит обновлен для позиции: ", ticket, ", новый TP=", newTakeProfit);
         }
         else
         {
            Print("Ошибка обновления тейк-профита: ", trade.ResultRetcode(), ", ", trade.ResultRetcodeDescription());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Функция проверки условий для сетки (на покупку)                  |
//+------------------------------------------------------------------+
bool CheckGridConditionsBuy()
{
   if(InpDebugMode) {
      Print("Проверка условий сетки BUY - начало проверки");
      Print("  Сетка включена: ", (InpUseGrid ? "ДА" : "НЕТ"));
      Print("  Текущее количество ордеров: ", orderCounter, " из ", InpMaxGridOrders);
   }
   
   if(!InpUseGrid || orderCounter >= InpMaxGridOrders || lastBuyPrice == 0) {
      if(InpDebugMode && !InpUseGrid) Print("Сетка для BUY отключена параметром");
      if(InpDebugMode && orderCounter >= InpMaxGridOrders) Print("Достигнут максимум ордеров для сетки BUY: ", orderCounter, "/", InpMaxGridOrders);
      if(InpDebugMode && lastBuyPrice == 0) Print("Нет открытых позиций BUY для создания сетки");
      return false;
   }
   
   // Рассчитываем фиксированный порог для сетки в пунктах
   double gridDistancePoints = InpGridDistance; // в пунктах
   // Переводим в цену
   double gridDistancePrice = gridDistancePoints * _Point * 10; // 10 пунктов = 1 пипс
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   if(InpDebugMode) {
      Print("Проверка условий сетки BUY:");
      Print("  Расстояние для сетки = ", gridDistancePoints, " пунктов (", gridDistancePrice, ")");
      Print("  Последняя цена ордера BUY = ", lastBuyPrice);
      Print("  Текущая цена ask = ", ask);
      Print("  Разница = ", lastBuyPrice - ask);
      Print("  Условие: ", (lastBuyPrice - ask >= gridDistancePrice ? "ВЫПОЛНЕНО" : "НЕ ВЫПОЛНЕНО"));
   }
   
   // Проверяем, опустилась ли цена на заданное расстояние от последнего ордера
   if(lastBuyPrice - ask >= gridDistancePrice)
   {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Функция проверки условий для сетки (на продажу)                  |
//+------------------------------------------------------------------+
bool CheckGridConditionsSell()
{
   if(InpDebugMode) {
      Print("Проверка условий сетки SELL - начало проверки");
      Print("  Сетка включена: ", (InpUseGrid ? "ДА" : "НЕТ"));
      Print("  Текущее количество ордеров: ", orderCounter, " из ", InpMaxGridOrders);
   }
   
   if(!InpUseGrid || orderCounter >= InpMaxGridOrders || lastSellPrice == 0) {
      if(InpDebugMode && !InpUseGrid) Print("Сетка для SELL отключена параметром");
      if(InpDebugMode && orderCounter >= InpMaxGridOrders) Print("Достигнут максимум ордеров для сетки SELL: ", orderCounter, "/", InpMaxGridOrders);
      if(InpDebugMode && lastSellPrice == 0) Print("Нет открытых позиций SELL для создания сетки");
      return false;
   }
   
   // Рассчитываем фиксированный порог для сетки в пунктах
   double gridDistancePoints = InpGridDistance; // в пунктах
   // Переводим в цену
   double gridDistancePrice = gridDistancePoints * _Point * 10; // 10 пунктов = 1 пипс
   
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   if(InpDebugMode) {
      Print("Проверка условий сетки SELL:");
      Print("  Расстояние для сетки = ", gridDistancePoints, " пунктов (", gridDistancePrice, ")");
      Print("  Последняя цена ордера SELL = ", lastSellPrice);
      Print("  Текущая цена bid = ", bid);
      Print("  Разница = ", bid - lastSellPrice);
      Print("  Условие: ", (bid - lastSellPrice >= gridDistancePrice ? "ВЫПОЛНЕНО" : "НЕ ВЫПОЛНЕНО"));
   }
   
   // Проверяем, поднялась ли цена на заданное расстояние от последнего ордера
   if(bid - lastSellPrice >= gridDistancePrice)
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
   // Проверяем время торговли
   if(!IsTradingTime())
   {
      if(InpDebugMode)
      {
         static datetime lastTimeMessage = 0;
         datetime currentTime = TimeCurrent();
         // Выводим сообщение только раз в час
         if(currentTime - lastTimeMessage >= 3600)
         {
            MqlDateTime dt;
            TimeToStruct(currentTime, dt);
            Print("Торговля запрещена в текущее время. Текущий час: ", dt.hour,
                  ", разрешенное время: ", InpStartHour, ":00 - ", InpEndHour, ":00");
            lastTimeMessage = currentTime;
         }
      }
      return;
   }
   
   // Обновляем информацию о текущих позициях
   UpdatePositionInfo();
   
   // Проверяем, сформирован ли новый бар
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   bool isNewBar = (currentBarTime > lastBarTime);
   
   if(isNewBar)
   {
      lastBarTime = currentBarTime;
      
      if(InpDebugMode) {
         Print("--- Новый бар сформирован ---");
      }
      
      // Проверяем условия для сетки существующих позиций только при закрытии свечи
      if(InpDebugMode && (HasPositions(POSITION_TYPE_BUY) || HasPositions(POSITION_TYPE_SELL))) {
         Print("Проверка условий для сетки при закрытии свечи...");
      }
      
      // Проверяем условия для сетки BUY
      if(HasPositions(POSITION_TYPE_BUY) && CheckGridConditionsBuy())
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double takeProfitPrice = ask + (InpTakeProfit * _Point * 10); // 10 пунктов = 1 пипс
         
         if(OpenBuyPosition(takeProfitPrice, true))
         {
            Print("Открыт ордер BUY для сетки, номер ордера: ", orderCounter);
            Print("Текущее количество ордеров: ", orderCounter, " из ", InpMaxGridOrders);
            UpdateTakeProfit();
         }
      }
      
      // Проверяем условия для сетки SELL
      if(HasPositions(POSITION_TYPE_SELL) && CheckGridConditionsSell())
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double takeProfitPrice = bid - (InpTakeProfit * _Point * 10); // 10 пунктов = 1 пипс
         
         if(OpenSellPosition(takeProfitPrice, true))
         {
            Print("Открыт ордер SELL для сетки, номер ордера: ", orderCounter);
            Print("Текущее количество ордеров: ", orderCounter, " из ", InpMaxGridOrders);
            UpdateTakeProfit();
         }
      }
   }
   
   // Для расчётов требуется минимум 5 баров (индексы 0,1,2,3,4 должны быть доступны)
   if(Bars(_Symbol, _Period) < 5) {
      if(InpDebugMode) Print("Недостаточно баров для анализа. Требуется минимум 5, доступно: ", Bars(_Symbol, _Period));
      return;
   }
   
   // Проверяем условия для входа в новую позицию только на новом баре
   if(isNewBar)
   {
      // Анализируем 4 полностью закрытых бара (индексы 1,2,3,4)
      
      // Находим самый высокий High и самый низкий Low за последние 4 бара
      double highestHigh = MathMax(
                           MathMax(iHigh(_Symbol, _Period, 1), iHigh(_Symbol, _Period, 2)),
                           MathMax(iHigh(_Symbol, _Period, 3), iHigh(_Symbol, _Period, 4))
                           );
      double lowestLow = MathMin(
                         MathMin(iLow(_Symbol, _Period, 1), iLow(_Symbol, _Period, 2)),
                         MathMin(iLow(_Symbol, _Period, 3), iLow(_Symbol, _Period, 4))
                         );
      
      // Проверяем размер каждого бара (High-Low) в пунктах
      double barSize1 = (iHigh(_Symbol, _Period, 1) - iLow(_Symbol, _Period, 1)) / _Point;
      double barSize2 = (iHigh(_Symbol, _Period, 2) - iLow(_Symbol, _Period, 2)) / _Point;
      double barSize3 = (iHigh(_Symbol, _Period, 3) - iLow(_Symbol, _Period, 3)) / _Point;
      double barSize4 = (iHigh(_Symbol, _Period, 4) - iLow(_Symbol, _Period, 4)) / _Point;
      
      // Конвертируем размеры баров в пункты (пипсы)
      double barSizePoints1 = barSize1 / 10; // 10 пунктов = 1 пипс
      double barSizePoints2 = barSize2 / 10;
      double barSizePoints3 = barSize3 / 10;
      double barSizePoints4 = barSize4 / 10;
      
      // Проверяем, что ни один из баров не превышает максимальный размер
      bool barsNotTooBig = (barSizePoints1 <= InpMaxBarSize && barSizePoints2 <= InpMaxBarSize && 
                            barSizePoints3 <= InpMaxBarSize && barSizePoints4 <= InpMaxBarSize);
      
      // Рассчитываем диапазон цены за 4 бара в пунктах
      double priceRange = (highestHigh - lowestLow) / _Point;
      double priceRangeInPoints = priceRange / 10; // 10 пунктов = 1 пипс
      
      // Для определения направления движения цены используем закрытие баров
      double close1 = iClose(_Symbol, _Period, 1);
      double close2 = iClose(_Symbol, _Period, 2);
      double close3 = iClose(_Symbol, _Period, 3);
      double close4 = iClose(_Symbol, _Period, 4);
      
      // Проверяем, падала ли цена на протяжении 4 баров (close4 > close3 > close2 > close1)
      bool priceGoingDown = (close4 > close3 && close3 > close2 && close2 > close1);
      
      // Проверяем, росла ли цена на протяжении 4 баров (close4 < close3 < close2 < close1)
      bool priceGoingUp = (close4 < close3 && close3 < close2 && close2 < close1);
      
      // Для логов также рассчитаем общее изменение цены
      double priceChange = (close4 - close1) / _Point;
      double priceChangeInPoints = priceChange / 10; // 10 пунктов = 1 пипс
      
      if(InpDebugMode) {
         Print("Анализ условий для входа в рынок:");
         Print("  Highest High = ", highestHigh, ", Lowest Low = ", lowestLow);
         Print("  Диапазон цены за 4 бара = ", priceRange, " пунктов");
         Print("  Диапазон цены за 4 бара (в пунктах) = ", priceRangeInPoints, " пунктов");
         Print("  Close[1] = ", close1, ", Close[4] = ", close4);
         Print("  Close[1] = ", close1, ", Close[2] = ", close2, ", Close[3] = ", close3, ", Close[4] = ", close4);
         Print("  Цена падает на протяжении 4 баров: ", (priceGoingDown ? "ДА" : "НЕТ"));
         Print("  Цена растет на протяжении 4 баров: ", (priceGoingUp ? "ДА" : "НЕТ"));
         Print("  Общее изменение цены = ", priceChangeInPoints, " пунктов (", (priceChangeInPoints > 0 ? "ВВЕРХ" : "ВНИЗ"), ")");
         Print("  Размеры баров (в пунктах):");
         Print("    Bar[1]: ", barSizePoints1, " (max: ", InpMaxBarSize, ")");
         Print("    Bar[2]: ", barSizePoints2, " (max: ", InpMaxBarSize, ")");
         Print("    Bar[3]: ", barSizePoints3, " (max: ", InpMaxBarSize, ")");
         Print("    Bar[4]: ", barSizePoints4, " (max: ", InpMaxBarSize, ")");
         Print("  Допустимый размер баров: ", (barsNotTooBig ? "ДА" : "НЕТ"));
         Print("  Требуемый диапазон для входа = ", InpDropPoints, " пунктов");
         Print("  Открыта ли позиция BUY: ", (HasPositions(POSITION_TYPE_BUY) ? "ДА" : "НЕТ"));
         Print("  Открыта ли позиция SELL: ", (HasPositions(POSITION_TYPE_SELL) ? "ДА" : "НЕТ"));
      }
      
      // Проверяем, есть ли открытые позиции в противоположном направлении
      bool hasOppositePositions = HasPositions(POSITION_TYPE_SELL);
      
      // Проверяем условия для входа на покупку (цена падала на протяжении 4 баров)
      if(priceRangeInPoints >= InpDropPoints && priceGoingDown && barsNotTooBig && !HasPositions(POSITION_TYPE_BUY) && 
         (InpAllowOppositePositions || !hasOppositePositions))
      {
         if(InpDebugMode) Print("*** СИГНАЛ НА ПОКУПКУ! Диапазон цены = ", priceRangeInPoints, " пунктов, цена падала 4 бара подряд ***");
         
         // Рассчитываем тейк-профит (в абсолютных значениях)
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double takeProfitPrice = ask + (InpTakeProfit * _Point * 10); // 10 пунктов = 1 пипс
         
         // Открываем позицию на покупку
         if(OpenBuyPosition(takeProfitPrice))
         {
            Print("Сигнал на покупку: Падение цены за 4 бара = ", MathAbs(priceChangeInPoints), " пунктов");
         }
      }
      else if(hasOppositePositions && !InpAllowOppositePositions && priceGoingDown && priceRangeInPoints >= InpDropPoints && barsNotTooBig) {
         if(InpDebugMode) Print("Сигнал на покупку обнаружен, но есть открытые позиции SELL. Ожидаем их закрытия.");
      }
      
      // Проверяем, есть ли открытые позиции в противоположном направлении
      hasOppositePositions = HasPositions(POSITION_TYPE_BUY);
      
      // Проверяем условия для входа на продажу (цена росла на протяжении 4 баров)
      if(priceRangeInPoints >= InpDropPoints && priceGoingUp && barsNotTooBig && !HasPositions(POSITION_TYPE_SELL) && 
         (InpAllowOppositePositions || !hasOppositePositions))
      {
         if(InpDebugMode) Print("*** СИГНАЛ НА ПРОДАЖУ! Диапазон цены = ", priceRangeInPoints, " пунктов, цена росла 4 бара подряд ***");
         
         // Рассчитываем тейк-профит (в абсолютных значениях)
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double takeProfitPrice = bid - (InpTakeProfit * _Point * 10); // 10 пунктов = 1 пипс
         
         // Открываем позицию на продажу
         if(OpenSellPosition(takeProfitPrice))
         {
            Print("Сигнал на продажу: Рост цены за 4 бара = ", priceChangeInPoints, " пунктов");
         }
      }
      else if(hasOppositePositions && !InpAllowOppositePositions && priceGoingUp && priceRangeInPoints >= InpDropPoints && barsNotTooBig) {
         if(InpDebugMode) Print("Сигнал на продажу обнаружен, но есть открытые позиции BUY. Ожидаем их закрытия.");
      }
      else if(InpDebugMode) {
         if(priceRangeInPoints < InpDropPoints)
            Print("Недостаточный диапазон цены для входа. Текущий: ", priceRangeInPoints, ", требуется: ", InpDropPoints);
         if(!barsNotTooBig)
            Print("Размер одного или нескольких баров превышает допустимый: ", InpMaxBarSize);
      }
   }
}
