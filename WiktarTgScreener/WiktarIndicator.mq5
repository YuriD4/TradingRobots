#include "TelegramHelper.mqh"
#property strict


// Переменная lastAlertTime теперь хранится в TelegramHelper.mqh

//--- МОДЕЛЬ 1: ПОГЛОЩЕНИЕ И СМЕНА ТРЕНДА ---
// Глобальные переменные для отслеживания смены тренда
static datetime lastBearishEngulfingTime = 0;     // Время последнего медвежьего поглощения
static double   currentLowPrice = 0.0;            // Актуальная цена вниз
static datetime lastBullishEngulfingTime = 0;     // Время последнего бычьего поглощения
static double   currentHighPrice = 0.0;           // Актуальная цена вверх
static int      maxBarsBetweenPatterns = 15;      // Максимальное количество баров между поглощениями

// Переменные для отслеживания использованных паттернов в моделях смены тренда
static datetime lastUsedBullishEngulfingTime = 0; // Время бычьего поглощения, уже использованного в модели смены тренда
static datetime lastUsedBearishEngulfingTime = 0; // Время медвежьего поглощения, уже использованного в модели смены тренда

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("WiktarIndicator запущен.");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // При деинициализации удаляем все объекты стрелок, созданные экспертом
   ObjectsDeleteAll(0, 0, OBJ_ARROW);
}


//+------------------------------------------------------------------+
//| МОДЕЛЬ 2: БАР БЛИЗКОГО ЗАКРЫТИЯ                                  |
//+------------------------------------------------------------------+
void CheckCloseClosingBar(datetime currentBarTime)
{
   // Получаем данные для последнего завершенного бара (индекс 1)
   double open1  = iOpen(_Symbol, _Period, 1);
   double close1 = iClose(_Symbol, _Period, 1);
   double high1  = iHigh(_Symbol, _Period, 1);
   double low1   = iLow(_Symbol, _Period, 1);
   
   // Определяем тип бара (бычий или медвежий)
   bool isBullish = close1 > open1;
   bool isBearish = close1 < open1;
   
   // Вычисляем размер бара в пунктах (делим на 10 для получения значения в пипсах)
   double barSize = (high1 - low1) / _Point / 10;
   
   // Расчет всех расстояний независимо от типа бара (делим на 10 для получения значения в пипсах)
   double openToLowDistance = (open1 - low1) / _Point / 10;
   double closeToHighDistance = (high1 - close1) / _Point / 10;
   double openToHighDistance = (high1 - open1) / _Point / 10;
   double closeToLowDistance = (close1 - low1) / _Point / 10;
   
   // Проверяем, является ли бар достаточно большим (минимум 60 пунктов)
   if(barSize >= 60)
   {
      bool isCloseClosingBar = false;
      double arrowPrice = 0.0;
      
      // Определяем пороговое значение в зависимости от таймфрейма
      int threshold = (_Period == PERIOD_W1) ? 30 : 10;

      // Проверяем условия для бычьего бара близкого закрытия
      if(isBullish)
      {
         // Проверяем условия с учетом порогового значения для текущего таймфрейма
         bool conditionCloseToHigh = closeToHighDistance <= threshold;
         
         if(conditionCloseToHigh)
         {
            isCloseClosingBar = true;
            arrowPrice = low1 - (1.0 * _Point); // Размещаем индикатор под баром
            
            // Отправляем сообщение о баре близкого закрытия (бычий)
            SendCloseClosingBarAlert(true, currentBarTime, arrowPrice);
         }
      }
      // Проверяем условия для медвежьего бара близкого закрытия
      else if(isBearish)
      {
         // Проверяем условия с учетом порогового значения для текущего таймфрейма
         bool conditionCloseToLow = closeToLowDistance <= threshold;
         
         if(conditionCloseToLow)
         {
            isCloseClosingBar = true;
            arrowPrice = high1 + (1.0 * _Point); // Размещаем индикатор над баром
            
            // Отправляем сообщение о баре близкого закрытия (медвежий)
            SendCloseClosingBarAlert(false, currentBarTime, arrowPrice);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Проверяем, сформирован ли новый бар.
   // В MQL5 индекс 0 – текущий (незавершённый) бар, индекс 1 – последний завершённый.
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, _Period, 1);
   if(currentBarTime == lastBarTime)
      return; // Новый бар ещё не сформирован
   lastBarTime = currentBarTime;
   
   // Для расчётов требуется минимум 5 баров (индексы 1,2,3,4 должны быть доступны)
   if(Bars(_Symbol, _Period) < 5)
      return;
      
   //--- МОДЕЛЬ 2: БАР БЛИЗКОГО ЗАКРЫТИЯ ---
   // Проверяем наличие бара с закрытием близким к экстремуму
   CheckCloseClosingBar(currentBarTime);
   
   //--- МОДЕЛЬ 3: ПОГЛОЩЕНИЕ (ENGULFING PATTERN) ---
   // Обнаружение паттернов поглощения разных типов (классический, трехсвечный, четырехсвечный)
   double minGap = 1.5 * _Point;
   bool bullishFound = false;
   bool bearishFound = false;
   double arrowPrice = 0.0;
   
   // Переменные для хранения диапазона свечей, входящих в паттерн
   int patternStartIndex = -1;
   int patternEndIndex   = -1;
   
   // Получаем данные для баров:
   double open1  = iOpen(_Symbol, _Period, 1);
   double close1 = iClose(_Symbol, _Period, 1);
   double high1  = iHigh(_Symbol, _Period, 1);
   double low1   = iLow(_Symbol, _Period, 1);
   
   double open2  = iOpen(_Symbol, _Period, 2);
   double close2 = iClose(_Symbol, _Period, 2);
   double high2  = iHigh(_Symbol, _Period, 2);
   double low2   = iLow(_Symbol, _Period, 2);
   
   double open3  = iOpen(_Symbol, _Period, 3);
   double close3 = iClose(_Symbol, _Period, 3);
   double high3  = iHigh(_Symbol, _Period, 3);
   double low3   = iLow(_Symbol, _Period, 3);
   
   double open4  = iOpen(_Symbol, _Period, 4);
   double close4 = iClose(_Symbol, _Period, 4);
   double high4  = iHigh(_Symbol, _Period, 4);
   double low4   = iLow(_Symbol, _Period, 4);
   
   // --- 3.1. Классический (двухсвечный) вариант поглощения ---
   // Бычье поглощение: бар 2 медвежий, бар 1 бычий
   if(open2 > close2 &&
      open1 < close1 &&
      (open1 >= low2 && open1 <= high2) &&
      ((close1 - high2) >= minGap))
   {
      bullishFound = true;
      arrowPrice = low1 - (0.5 * _Point);
      patternStartIndex = 2;
      patternEndIndex   = 1;
   }
   
   // Медвежье поглощение: бар 2 бычий, бар 1 медвежий
   if(!bullishFound &&
      open2 < close2 &&
      open1 > close1 &&
      (open1 >= low2 && open1 <= high2) &&
      ((low2 - close1) >= minGap))
   {
      bearishFound = true;
      arrowPrice = high1 + (0.5 * _Point);
      patternStartIndex = 2;
      patternEndIndex   = 1;
   }
   
   // --- 3.2. Расширенный вариант поглощения с одной промежуточной свечой (трёхсвечный) ---
   if(!bullishFound)
   {
      bool adjacentBull = false;
      if(open3 > close3 &&
         open2 < close2 &&
         (open2 >= low3 && open2 <= high3) &&
         ((close2 - high3) >= minGap))
      {
         adjacentBull = true;
      }
      if(!adjacentBull)
      {
         if(open3 > close3 &&
            open1 < close1 &&
            (open1 >= low3 && open1 <= high3) &&
            ((close1 - high3) >= minGap))
         {
            bullishFound = true;
            arrowPrice = low1 - (0.5 * _Point);
            patternStartIndex = 3;
            patternEndIndex   = 1;
         }
      }
   }
   
   if(!bearishFound)
   {
      bool adjacentBear = false;
      if(open3 < close3 &&
         open2 > close2 &&
         (open2 >= low3 && open2 <= high3) &&
         ((low3 - close2) >= minGap))
      {
         adjacentBear = true;
      }
      if(!adjacentBear)
      {
         if(open3 < close3 &&
            open1 > close1 &&
            (open1 >= low3 && open1 <= high3) &&
            ((low3 - close1) >= minGap))
         {
            bearishFound = true;
            arrowPrice = high1 + (0.5 * _Point);
            patternStartIndex = 3;
            patternEndIndex   = 1;
         }
      }
   }
   
   // --- 3.3. Расширенный вариант поглощения с двумя промежуточными свечами (четырёхсвечный) ---
   if(!bullishFound)
   {
      if(open4 > close4 &&
         open1 < close1 &&
         (open1 >= low4 && open1 <= high4) &&
         ((close1 - high4) >= minGap))
      {
         bool intermediateBull = false;
         if(open4 > close4 &&
            open3 < close3 &&
            (open3 >= low4 && open3 <= high4) &&
            ((close3 - high4) >= minGap))
            intermediateBull = true;
         if(open4 > close4 &&
            open2 < close2 &&
            (open2 >= low4 && open2 <= high4) &&
            ((close2 - high4) >= minGap))
            intermediateBull = true;
         bool intermediateEngulf = false;
         if(open3 > close3 &&
            open2 < close2 &&
            (open2 >= low3 && open2 <= high3) &&
            ((close2 - high3) >= minGap))
            intermediateEngulf = true;
         if(!intermediateBull && !intermediateEngulf)
         {
            bullishFound = true;
            arrowPrice = low1 - (0.5 * _Point);
            patternStartIndex = 4;
            patternEndIndex   = 1;
         }
      }
   }
   
   if(!bearishFound)
   {
      if(open4 < close4 &&
         open1 > close1 &&
         (open1 >= low4 && open1 <= high4) &&
         ((low4 - close1) >= minGap))
      {
         bool intermediateBear = false;
         if(open4 < close4 &&
            open3 > close3 &&
            (open3 >= low4 && open3 <= high4) &&
            ((low4 - close3) >= minGap))
            intermediateBear = true;
         if(open4 < close4 &&
            open2 > close2 &&
            (open2 >= low4 && open2 <= high4) &&
            ((low4 - close2) >= minGap))
            intermediateBear = true;
         bool intermediateEngulfBear = false;
         if(open3 < close3 &&
            open2 > close2 &&
            (open2 >= low3 && open2 <= high3) &&
            ((low3 - close2) >= minGap))
            intermediateEngulfBear = true;
         if(!intermediateBear && !intermediateEngulfBear)
         {
            bearishFound = true;
            arrowPrice = high1 + (0.5 * _Point);
            patternStartIndex = 4;
            patternEndIndex   = 1;
         }
      }
   }
   
   // --- 3.4. Обработка найденных паттернов поглощения ---
   if(bullishFound || bearishFound)
   {
      bool trendChangeDetected = false;
      
      //--- МОДЕЛЬ 1: ОБНАРУЖЕНИЕ СМЕНЫ ТРЕНДА ---
      // Обновление информации о последнем поглощении для отслеживания смены тренда
      if(bullishFound)
      {
         lastBullishEngulfingTime = currentBarTime;
         currentHighPrice = high2;  // Запоминаем актуальную цену вверх (хай красного бара)
         
         // Проверяем, было ли медвежье поглощение недавно (в пределах maxBarsBetweenPatterns баров)
         // и не было ли оно уже использовано в модели смены тренда
         if(lastBearishEngulfingTime != 0 && lastBearishEngulfingTime != lastUsedBearishEngulfingTime)
         {
            int barsBetween = iBarShift(_Symbol, _Period, lastBearishEngulfingTime) - iBarShift(_Symbol, _Period, currentBarTime);
            
            if(barsBetween > 0 && barsBetween <= maxBarsBetweenPatterns)
            {
               // Проверяем условие: закрытие зеленого бара выше, чем актуальная цена вниз
               if(close1 > currentLowPrice)
               {
                  // Находим минимальную цену среди всех баров в паттерне и между ними
                  double minPrice = low1;
                  datetime startTime = lastBearishEngulfingTime;
                  datetime endTime = currentBarTime;
                  int startIdx = iBarShift(_Symbol, _Period, startTime);
                  int endIdx = iBarShift(_Symbol, _Period, endTime);
                  
                  for(int i = endIdx; i <= startIdx; i++)
                  {
                     double barLow = iLow(_Symbol, _Period, i);
                     if(barLow < minPrice)
                        minPrice = barLow;
                  }
                  
                  // Проверяем, является ли это минимальной ценой текущего дня
                  bool isMinOfDay = true;
                  datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
                  int barsPerDay = PeriodSeconds(PERIOD_D1) / PeriodSeconds(_Period);
                  
                  for(int i = 0; i < barsPerDay; i++)
                  {
                     // Проверяем только бары текущего дня
                     if(iTime(_Symbol, _Period, i) < currentDay)
                        break;
                        
                     double dayLow = iLow(_Symbol, _Period, i);
                     if(dayLow < minPrice)
                     {
                        isMinOfDay = false;
                        break;
                     }
                  }
                  
                  // Если все условия выполнены и минимальная цена модели является минимальной ценой дня, фиксируем смену тренда вверх
                  if(isMinOfDay)
                  {
                     // Отправляем сообщение о смене тренда вверх
                     SendTrendChangeAlert(true, currentBarTime, arrowPrice);
                     trendChangeDetected = true;
                     
                     // Отмечаем паттерны как использованные в модели смены тренда
                     lastUsedBearishEngulfingTime = lastBearishEngulfingTime;
                     lastUsedBullishEngulfingTime = currentBarTime; // текущее бычье поглощение
                  }
               }
            }
         }
      }
      else if(bearishFound)
      {
         lastBearishEngulfingTime = currentBarTime;
         currentLowPrice = low2;  // Запоминаем актуальную цену вниз (лоу зеленого бара)
         
         // Проверяем, было ли бычье поглощение недавно (в пределах maxBarsBetweenPatterns баров)
         // и не было ли оно уже использовано в модели смены тренда
         if(lastBullishEngulfingTime != 0 && lastBullishEngulfingTime != lastUsedBullishEngulfingTime)
         {
            int barsBetween = iBarShift(_Symbol, _Period, lastBullishEngulfingTime) - iBarShift(_Symbol, _Period, currentBarTime);
            
            if(barsBetween > 0 && barsBetween <= maxBarsBetweenPatterns)
            {
               // Проверяем условие: закрытие красного бара ниже, чем актуальная цена вверх
               if(close1 < currentHighPrice)
               {
                  // Находим максимальную цену среди всех баров в паттерне и между ними
                  double maxPrice = high1;
                  datetime startTime = lastBullishEngulfingTime;
                  datetime endTime = currentBarTime;
                  int startIdx = iBarShift(_Symbol, _Period, startTime);
                  int endIdx = iBarShift(_Symbol, _Period, endTime);
                  
                  for(int i = endIdx; i <= startIdx; i++)
                  {
                     double barHigh = iHigh(_Symbol, _Period, i);
                     if(barHigh > maxPrice)
                        maxPrice = barHigh;
                  }
                  
                  // Проверяем, является ли это максимальной ценой текущего дня
                  bool isMaxOfDay = true;
                  datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
                  int barsPerDay = PeriodSeconds(PERIOD_D1) / PeriodSeconds(_Period);
                  
                  for(int i = 0; i < barsPerDay; i++)
                  {
                     // Проверяем только бары текущего дня
                     if(iTime(_Symbol, _Period, i) < currentDay)
                        break;
                        
                     double dayHigh = iHigh(_Symbol, _Period, i);
                     if(dayHigh > maxPrice)
                     {
                        isMaxOfDay = false;
                        break;
                     }
                  }
                  
                  // Если все условия выполнены и максимальная цена модели является максимальной ценой дня, фиксируем смену тренда вниз
                  if(isMaxOfDay)
                  {
                     // Отправляем сообщение о смене тренда вниз
                     SendTrendChangeAlert(false, currentBarTime, arrowPrice);
                     trendChangeDetected = true;
                     
                     // Отмечаем паттерны как использованные в модели смены тренда
                     lastUsedBullishEngulfingTime = lastBullishEngulfingTime;
                     lastUsedBearishEngulfingTime = currentBarTime; // текущее медвежье поглощение
                  }
               }
            }
         }
      }
      
      // Отправляем обычное сообщение о вливании только если не было смены тренда
      if(!trendChangeDetected)
      {
         SendAlertAndDraw(bullishFound, bearishFound, currentBarTime, arrowPrice);
      }
   }
}
