//+------------------------------------------------------------------+
//|                                          TrendChangeDetector.mqh |
//|                                    Copyright 2023, TradingRobots |
//|                                             https://www.example.com |
//+------------------------------------------------------------------+
#property strict

#include "EngulfingPatternDetector.mqh"
#include "TrendChangeConfig.mqh"

//+------------------------------------------------------------------+
//| Класс для определения сигналов смены тренда                     |
//+------------------------------------------------------------------+
class CTrendChangeDetector
{
private:
   string            m_symbol;              // Торговый символ
   bool              m_debugMode;           // Режим отладки
   CTrendChangeConfig* m_config;           // Конфигурация
   CEngulfingPatternDetector* m_patternDetector; // Детектор паттернов
   
   // Параметры для отслеживания смены тренда
   int               m_maxBarsBetweenPatterns; // Максимальное количество баров между поглощениями
   datetime          m_lastUsedBullishEngulfingTime; // Время бычьего поглощения, уже использованного в модели смены тренда
   datetime          m_lastUsedBearishEngulfingTime; // Время медвежьего поглощения, уже использованного в модели смены тренда
   
   // Флаги сигналов
   bool              m_uptrendSignal;       // Сигнал на восходящий тренд
   bool              m_downtrendSignal;     // Сигнал на нисходящий тренд
   datetime          m_lastRangeDrawDay;    // Последний день, когда рисовался диапазон
   
   // Данные для расчета стоп-лосса
   double            m_lastPatternLow;      // Минимум последней модели смены тренда
   double            m_lastPatternHigh;     // Максимум последней модели смены тренда
   
public:
   // Конструктор и деструктор
   CTrendChangeDetector(string symbol, CTrendChangeConfig* config, bool debugMode = false);
   ~CTrendChangeDetector();
   
   // Основные методы
   void              ProcessBar(datetime currentBarTime);
   
   // Методы доступа к сигналам
   bool              IsUptrendSignal() const { return m_uptrendSignal; }
   bool              IsDowntrendSignal() const { return m_downtrendSignal; }
   
   // Методы сброса сигналов
   void              ResetSignals();
   
   // Методы для получения данных паттерна
   double            GetLastPatternLow() const { return m_lastPatternLow; }
   double            GetLastPatternHigh() const { return m_lastPatternHigh; }
   
private:
   // Вспомогательные методы
   bool              CheckUptrendCondition(datetime currentBarTime);
   bool              CheckDowntrendCondition(datetime currentBarTime);
   bool              CheckEngulfingCandlesCrossPreviousDayRange(datetime bullishTime, datetime bearishTime, bool isUptrendCheck);
   void              GetPreviousDayRange(double &highPrice, double &lowPrice);
   void              DrawPreviousDayRange(double highPrice, double lowPrice);
   void              DrawTrendChangePattern(datetime bullishTime, datetime bearishTime, bool isUptrend);
   void              CheckAndDrawDailyRange();
};

//+------------------------------------------------------------------+
//| Конструктор класса                                               |
//+------------------------------------------------------------------+
CTrendChangeDetector::CTrendChangeDetector(string symbol, CTrendChangeConfig* config, bool debugMode = false)
{
   m_symbol = symbol;
   m_debugMode = debugMode;
   m_config = config;
   m_patternDetector = new CEngulfingPatternDetector(symbol, debugMode);
   m_maxBarsBetweenPatterns = 15;
   m_lastUsedBullishEngulfingTime = 0;
   m_lastUsedBearishEngulfingTime = 0;
   m_uptrendSignal = false;
   m_downtrendSignal = false;
   m_lastRangeDrawDay = 0;
   m_lastPatternLow = 0.0;
   m_lastPatternHigh = 0.0;
}

//+------------------------------------------------------------------+
//| Деструктор класса                                                |
//+------------------------------------------------------------------+
CTrendChangeDetector::~CTrendChangeDetector()
{
   if(CheckPointer(m_patternDetector) == POINTER_DYNAMIC)
      delete m_patternDetector;
}

//+------------------------------------------------------------------+
//| Основной метод для обработки бара                                 |
//+------------------------------------------------------------------+
void CTrendChangeDetector::ProcessBar(datetime currentBarTime)
{
   // Сбрасываем сигналы (они действительны только один бар)
   ResetSignals();
   
   // Проверяем и рисуем диапазон прошлого дня (один раз в день)
   CheckAndDrawDailyRange();
   
   // Определяем паттерны поглощения
   bool patternFound = m_patternDetector.DetectEngulfingPatterns(currentBarTime);
   
   
   if(patternFound)
   {
      // Проверяем условия для смены тренда
      if(CheckUptrendCondition(currentBarTime))
      {
         m_uptrendSignal = true;
         
         // Отмечаем паттерны как использованные
         m_lastUsedBearishEngulfingTime = m_patternDetector.LastBearishEngulfingTime();
         m_lastUsedBullishEngulfingTime = m_patternDetector.LastBullishEngulfingTime();
         
         if(m_debugMode)
         {
            Print("DEBUG TrendChangeDetector: Uptrend signal detected at ", TimeToString(currentBarTime));
         }
      }
      else if(CheckDowntrendCondition(currentBarTime))
      {
         m_downtrendSignal = true;
         
         // Отмечаем паттерны как использованные
         m_lastUsedBullishEngulfingTime = m_patternDetector.LastBullishEngulfingTime();
         m_lastUsedBearishEngulfingTime = m_patternDetector.LastBearishEngulfingTime();
         
         if(m_debugMode)
         {
            Print("DEBUG TrendChangeDetector: Downtrend signal detected at ", TimeToString(currentBarTime));
         }
      }
      else if(m_debugMode)
      {
         Print("DEBUG TrendChangeDetector: Pattern found but conditions not met");
      }
   }
}

//+------------------------------------------------------------------+
//| Метод проверки условий для восходящего тренда                     |
//+------------------------------------------------------------------+
bool CTrendChangeDetector::CheckUptrendCondition(datetime currentBarTime)
{
   if(m_debugMode)
   {
      Print("DEBUG TrendChangeDetector: Checking uptrend condition for ", TimeToString(currentBarTime));
   }
   
   // Получаем время последнего бычьего поглощения
   datetime bullishTime = m_patternDetector.LastBullishEngulfingTime();
   if(m_debugMode)
   {
      Print("DEBUG TrendChangeDetector: Last bullish time = ", TimeToString(bullishTime), ", current = ", TimeToString(currentBarTime));
   }
   
   if(bullishTime == 0 || bullishTime != currentBarTime)
   {
      if(m_debugMode)
      {
         Print("DEBUG TrendChangeDetector: Uptrend check failed - bullish time mismatch");
      }
      return false;
   }
   
   // Проверяем, было ли медвежье поглощение недавно
   datetime bearishTime = m_patternDetector.LastBearishEngulfingTime();
   if(m_debugMode)
   {
      Print("DEBUG TrendChangeDetector: Last bearish time = ", TimeToString(bearishTime), ", last used = ", TimeToString(m_lastUsedBearishEngulfingTime));
   }
   
   if(bearishTime == 0 || bearishTime == m_lastUsedBearishEngulfingTime)
   {
      if(m_debugMode)
      {
         Print("DEBUG TrendChangeDetector: Uptrend check failed - no recent bearish or already used");
      }
      return false;
   }
   
   // Проверяем количество баров между поглощениями
   int barsBetween = iBarShift(m_symbol, _Period, bearishTime) - iBarShift(m_symbol, _Period, bullishTime);
   if(m_debugMode)
   {
      Print("DEBUG TrendChangeDetector: Bars between patterns = ", barsBetween, " (max allowed = ", m_maxBarsBetweenPatterns, ")");
   }
   
   if(barsBetween <= 0 || barsBetween > m_maxBarsBetweenPatterns)
   {
      if(m_debugMode)
      {
         Print("DEBUG TrendChangeDetector: Uptrend check failed - invalid bars between patterns");
      }
      return false;
   }
   
   // Получаем данные для проверки условий
   double close1 = iClose(m_symbol, _Period, 1);  // Закрытие бычьего бара
   double currentLowPrice = m_patternDetector.CurrentLowPrice();  // Актуальная цена вниз
   
   if(m_debugMode)
   {
      Print("DEBUG TrendChangeDetector: close1 = ", close1, ", currentLowPrice = ", currentLowPrice);
   }
   
   // Проверяем условие: закрытие бычьего бара выше, чем актуальная цена вниз
   if(close1 <= currentLowPrice)
   {
      if(m_debugMode)
      {
         Print("DEBUG TrendChangeDetector: Uptrend check failed - close1 <= currentLowPrice");
      }
      return false;
   }
   
   // НОВОЕ УСЛОВИЕ: Закрытие бычьего поглощения должно быть минимум на 1 пункт выше максимума медвежьего
   int bearishIdx = iBarShift(m_symbol, _Period, bearishTime);
   double bearishHigh = iHigh(m_symbol, _Period, bearishIdx);
   double minPriceGap = _Point; // 1 пункт
   
   if(close1 < (bearishHigh + minPriceGap))
   {
      if(m_debugMode)
      {
         Print("DEBUG TrendChangeDetector: Uptrend check failed - bullish close (", close1,
               ") not enough above bearish high (", bearishHigh, ") + 1 point = ", (bearishHigh + minPriceGap));
      }
      return false;
   }
   
   // Находим минимальную цену среди всех баров в паттерне и между ними
   datetime startTime = bearishTime;
   datetime endTime = bullishTime;
   int startIdx = iBarShift(m_symbol, _Period, startTime);
   int endIdx = iBarShift(m_symbol, _Period, endTime);
   
   double minPrice = iLow(m_symbol, _Period, endIdx); // Инициализируем первым значением
   for(int i = endIdx; i <= startIdx; i++)
   {
      double barLow = iLow(m_symbol, _Period, i);
      if(barLow < minPrice)
         minPrice = barLow;
   }
   
   if(m_debugMode)
   {
      Print("DEBUG TrendChangeDetector: minPrice in range = ", minPrice);
   }
   
   
   // Проверка экстремума дня: минимум модели должен быть минимумом текущего дня
   double dayLow = iLow(m_symbol, PERIOD_D1, 0);
   if(minPrice > dayLow)
   {
      if(m_debugMode)
      {
         Print("DEBUG TrendChangeDetector: Uptrend check failed - pattern low (", minPrice,
               ") is not day's low (", dayLow, ")");
      }
      return false;
   }
   
   // Новая проверка: для uptrend должна быть пробита нижняя граница диапазона прошлого дня
   if(!CheckEngulfingCandlesCrossPreviousDayRange(bullishTime, bearishTime, true))
   {
      if(m_debugMode)
      {
         Print("DEBUG TrendChangeDetector: Uptrend check failed - lower boundary of previous day range not broken");
      }
      return false;
   }
   
   // Сохраняем минимум модели для расчета стоп-лосса
   m_lastPatternLow = minPrice;
   
   // Отрисовываем визуальные элементы для успешной смены тренда
   DrawTrendChangePattern(bullishTime, bearishTime, true);
   
   if(m_debugMode)
   {
      Print("DEBUG TrendChangeDetector: Uptrend condition check PASSED: barsBetween=", barsBetween,
            ", close1=", close1, ", currentLowPrice=", currentLowPrice,
            ", minPrice=", minPrice, ", saved pattern low=", m_lastPatternLow);
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Метод проверки условий для нисходящего тренда                   |
//+------------------------------------------------------------------+
bool CTrendChangeDetector::CheckDowntrendCondition(datetime currentBarTime)
{
   // Получаем время последнего медвежьего поглощения
   datetime bearishTime = m_patternDetector.LastBearishEngulfingTime();
   if(bearishTime == 0 || bearishTime != currentBarTime)
      return false;
   
   // Проверяем, было ли бычье поглощение недавно
   datetime bullishTime = m_patternDetector.LastBullishEngulfingTime();
   if(bullishTime == 0 || bullishTime == m_lastUsedBullishEngulfingTime)
      return false;
   
   // Проверяем количество баров между поглощениями
   int barsBetween = iBarShift(m_symbol, _Period, bullishTime) - iBarShift(m_symbol, _Period, bearishTime);
   if(barsBetween <= 0 || barsBetween > m_maxBarsBetweenPatterns)
      return false;
   
   // Получаем данные для проверки условий
   double close1 = iClose(m_symbol, _Period, 1);  // Закрытие медвежьего бара
   double currentHighPrice = m_patternDetector.CurrentHighPrice();  // Актуальная цена вверх
   
   // Проверяем условие: закрытие медвежьего бара ниже, чем актуальная цена вверх
   if(close1 >= currentHighPrice)
      return false;
   
   // НОВОЕ УСЛОВИЕ: Закрытие медвежьего поглощения должно быть минимум на 1 пункт ниже минимума бычьего
   int bullishIdx = iBarShift(m_symbol, _Period, bullishTime);
   double bullishLow = iLow(m_symbol, _Period, bullishIdx);
   double minPriceGap = _Point; // 1 пункт
   
   if(close1 > (bullishLow - minPriceGap))
   {
      if(m_debugMode)
      {
         Print("DEBUG TrendChangeDetector: Downtrend check failed - bearish close (", close1,
               ") not enough below bullish low (", bullishLow, ") - 1 point = ", (bullishLow - minPriceGap));
      }
      return false;
   }
   
   // Находим максимальную цену среди всех баров в паттерне и между ними
   datetime startTime = bullishTime;
   datetime endTime = bearishTime;
   int startIdx = iBarShift(m_symbol, _Period, startTime);
   int endIdx = iBarShift(m_symbol, _Period, endTime);
   
   double maxPrice = iHigh(m_symbol, _Period, endIdx); // Инициализируем первым значением
   for(int i = endIdx; i <= startIdx; i++)
   {
      double barHigh = iHigh(m_symbol, _Period, i);
      if(barHigh > maxPrice)
         maxPrice = barHigh;
   }
   
   
   // Проверка экстремума дня: максимум модели должен быть максимумом текущего дня
   double dayHigh = iHigh(m_symbol, PERIOD_D1, 0);
   if(maxPrice < dayHigh)
   {
      if(m_debugMode)
      {
         Print("DEBUG TrendChangeDetector: Downtrend check failed - pattern high (", maxPrice,
               ") is not day's high (", dayHigh, ")");
      }
      return false;
   }
   
   // Новая проверка: для downtrend должна быть пробита верхняя граница диапазона прошлого дня
   if(!CheckEngulfingCandlesCrossPreviousDayRange(bullishTime, bearishTime, false))
   {
      if(m_debugMode)
      {
         Print("DEBUG TrendChangeDetector: Downtrend check failed - upper boundary of previous day range not broken");
      }
      return false;
   }
   
   // Сохраняем максимум модели для расчета стоп-лосса
   m_lastPatternHigh = maxPrice;
   
   // Отрисовываем визуальные элементы для успешной смены тренда
   DrawTrendChangePattern(bullishTime, bearishTime, false);
   
   if(m_debugMode)
   {
      Print("DEBUG TrendChangeDetector: Downtrend condition check PASSED: barsBetween=", barsBetween,
            ", close1=", close1, ", currentHighPrice=", currentHighPrice,
            ", maxPrice=", maxPrice, ", saved pattern high=", m_lastPatternHigh);
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Метод проверки пересечения свечей поглощения с диапазоном прошлого дня |
//+------------------------------------------------------------------+
bool CTrendChangeDetector::CheckEngulfingCandlesCrossPreviousDayRange(datetime bullishTime, datetime bearishTime, bool isUptrendCheck)
{
   // Получаем диапазон прошлого дня с 16:00 до 00:00
   double prevDayHigh, prevDayLow;
   GetPreviousDayRange(prevDayHigh, prevDayLow);
   
   if(prevDayHigh == 0 || prevDayLow == 0)
   {
      if(m_debugMode)
      {
         Print("DEBUG TrendChangeDetector: Failed to get previous day range");
      }
      return false;
   }
   
   if(m_debugMode)
   {
      Print("DEBUG TrendChangeDetector: Previous day range (16:00-00:00): High=", prevDayHigh, ", Low=", prevDayLow);
   }
   
   
   if(isUptrendCheck)
   {
      // Для uptrend: ищем прошивание нижней границы медвежьими свечами
      if(bearishTime > 0)
      {
         int bearishIdx = iBarShift(m_symbol, _Period, bearishTime);
         double bearishLow = iLow(m_symbol, _Period, bearishIdx);
         double bearishHigh = iHigh(m_symbol, _Period, bearishIdx);
         
         // Свеча должна прошивать нижнюю границу: лоу ниже границы, хай внутри диапазона
         if(bearishLow < prevDayLow && bearishHigh >= prevDayLow)
         {
            if(m_debugMode)
            {
               Print("DEBUG TrendChangeDetector: Bearish engulfing pierces lower boundary, allowing uptrend: ",
                     "Low=", bearishLow, " < ", prevDayLow, ", High=", bearishHigh, " >= ", prevDayLow);
            }
            return true;
         }
         else if(m_debugMode)
         {
            Print("DEBUG TrendChangeDetector: Bearish candle doesn't pierce boundary properly: ",
                  "Low=", bearishLow, " < ", prevDayLow, " = ", (bearishLow < prevDayLow),
                  ", High=", bearishHigh, " >= ", prevDayLow, " = ", (bearishHigh >= prevDayLow));
         }
      }
      
      if(m_debugMode)
      {
         Print("DEBUG TrendChangeDetector: Lower boundary not properly pierced, uptrend not allowed");
      }
      return false;
   }
   else
   {
      // Для downtrend: ищем прошивание верхней границы бычьими свечами
      if(bullishTime > 0)
      {
         int bullishIdx = iBarShift(m_symbol, _Period, bullishTime);
         double bullishHigh = iHigh(m_symbol, _Period, bullishIdx);
         double bullishLow = iLow(m_symbol, _Period, bullishIdx);
         
         // Свеча должна прошивать верхнюю границу: хай выше границы, лоу внутри диапазона
         if(bullishHigh > prevDayHigh && bullishLow <= prevDayHigh)
         {
            if(m_debugMode)
            {
               Print("DEBUG TrendChangeDetector: Bullish engulfing pierces upper boundary, allowing downtrend: ",
                     "High=", bullishHigh, " > ", prevDayHigh, ", Low=", bullishLow, " <= ", prevDayHigh);
            }
            return true;
         }
         else if(m_debugMode)
         {
            Print("DEBUG TrendChangeDetector: Bullish candle doesn't pierce boundary properly: ",
                  "High=", bullishHigh, " > ", prevDayHigh, " = ", (bullishHigh > prevDayHigh),
                  ", Low=", bullishLow, " <= ", prevDayHigh, " = ", (bullishLow <= prevDayHigh));
         }
      }
      
      if(m_debugMode)
      {
         Print("DEBUG TrendChangeDetector: Upper boundary not properly pierced, downtrend not allowed");
      }
      return false;
   }
}

//+------------------------------------------------------------------+
//| Метод получения диапазона прошлого дня с 16:00 до 00:00         |
//+------------------------------------------------------------------+
void CTrendChangeDetector::GetPreviousDayRange(double &highPrice, double &lowPrice)
{
   highPrice = 0;
   lowPrice = 0;
   
   // Получаем время начала вчерашнего дня
   datetime yesterday = iTime(m_symbol, PERIOD_D1, 1);
   
   // Создаем временные структуры для 16:00 вчера и 00:00 сегодня
   MqlDateTime dt_start, dt_end;
   TimeToStruct(yesterday, dt_start);
   dt_start.hour = 16;
   dt_start.min = 0;
   dt_start.sec = 0;
   datetime startTime = StructToTime(dt_start);
   
   TimeToStruct(yesterday, dt_end);
   dt_end.hour = 23;
   dt_end.min = 59;
   dt_end.sec = 59;
   datetime endTime = StructToTime(dt_end);
   
   if(m_debugMode)
   {
      Print("DEBUG TrendChangeDetector: Previous day range period: ", TimeToString(startTime), " to ", TimeToString(endTime));
   }
   
   // Ищем максимум и минимум в указанном диапазоне времени
   bool foundData = false;
   int totalBars = Bars(m_symbol, _Period);
   
   for(int i = 0; i < totalBars; i++)
   {
      datetime barTime = iTime(m_symbol, _Period, i);
      
      // Прекращаем поиск, если достигли времени раньше нужного диапазона
      if(barTime < startTime)
         break;
      
      // Проверяем, попадает ли бар в нужный временной диапазон
      if(barTime >= startTime && barTime <= endTime)
      {
         double barHigh = iHigh(m_symbol, _Period, i);
         double barLow = iLow(m_symbol, _Period, i);
         
         if(!foundData)
         {
            highPrice = barHigh;
            lowPrice = barLow;
            foundData = true;
         }
         else
         {
            if(barHigh > highPrice)
               highPrice = barHigh;
            if(barLow < lowPrice)
               lowPrice = barLow;
         }
      }
   }
   
   if(m_debugMode)
   {
      Print("DEBUG TrendChangeDetector: Found previous day range data: ", foundData ? "Yes" : "No");
      if(foundData)
         Print("DEBUG TrendChangeDetector: Previous day range: High=", highPrice, ", Low=", lowPrice);
   }
}

//+------------------------------------------------------------------+
//| Метод отрисовки диапазона прошлого дня                           |
//+------------------------------------------------------------------+
void CTrendChangeDetector::DrawPreviousDayRange(double highPrice, double lowPrice)
{
   // Получаем текущее время для позиционирования линий
   datetime currentTime = iTime(m_symbol, _Period, 0);
   datetime startTime = currentTime;
   datetime endTime = currentTime + PeriodSeconds(_Period) * 3; // Линии на 3 свечи вправо
   
   // Создаем уникальные имена объектов
   string highLineName = "PrevDayHigh_" + TimeToString(currentTime, TIME_SECONDS);
   string lowLineName = "PrevDayLow_" + TimeToString(currentTime, TIME_SECONDS);
   string rangeName = "PrevDayRange_" + TimeToString(currentTime, TIME_SECONDS);
   
   
   // Создаем линию максимума прошлого дня (приглушенный коричневый)
   ObjectCreate(0, highLineName, OBJ_TREND, 0, startTime, highPrice, endTime, highPrice);
   ObjectSetInteger(0, highLineName, OBJPROP_COLOR, C'139,69,19');  // Коричневый
   ObjectSetInteger(0, highLineName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, highLineName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, highLineName, OBJPROP_RAY_RIGHT, false);
   ObjectSetString(0, highLineName, OBJPROP_TOOLTIP, "Previous Day High (16:00-00:00): " + DoubleToString(highPrice, _Digits));
   
   // Создаем линию минимума прошлого дня (приглушенный коричневый)
   ObjectCreate(0, lowLineName, OBJ_TREND, 0, startTime, lowPrice, endTime, lowPrice);
   ObjectSetInteger(0, lowLineName, OBJPROP_COLOR, C'139,69,19');  // Коричневый
   ObjectSetInteger(0, lowLineName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, lowLineName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lowLineName, OBJPROP_RAY_RIGHT, false);
   ObjectSetString(0, lowLineName, OBJPROP_TOOLTIP, "Previous Day Low (16:00-00:00): " + DoubleToString(lowPrice, _Digits));
   
   // Создаем прямоугольник для выделения диапазона (приглушенный желто-серый)
   ObjectCreate(0, rangeName, OBJ_RECTANGLE, 0, startTime, highPrice, endTime, lowPrice);
   ObjectSetInteger(0, rangeName, OBJPROP_COLOR, C'245,245,220');  // Бежевый
   ObjectSetInteger(0, rangeName, OBJPROP_FILL, true);
   ObjectSetInteger(0, rangeName, OBJPROP_BACK, true);
   ObjectSetString(0, rangeName, OBJPROP_TOOLTIP, "Previous Day Range (16:00-00:00)");
   
   if(m_debugMode)
   {
      Print("DEBUG TrendChangeDetector: Drew previous day range visualization");
   }
}

//+------------------------------------------------------------------+
//| Метод отрисовки паттерна смены тренда                            |
//+------------------------------------------------------------------+
void CTrendChangeDetector::DrawTrendChangePattern(datetime bullishTime, datetime bearishTime, bool isUptrend)
{
   // Определяем временной диапазон паттерна
   datetime startTime = (bullishTime < bearishTime) ? bullishTime : bearishTime;
   datetime endTime = (bullishTime > bearishTime) ? bullishTime : bearishTime;
   
   int startIdx = iBarShift(m_symbol, _Period, startTime);
   int endIdx = iBarShift(m_symbol, _Period, endTime);
   
   // Находим максимум и минимум в диапазоне паттерна
   double patternHigh = iHigh(m_symbol, _Period, endIdx);
   double patternLow = iLow(m_symbol, _Period, endIdx);
   
   for(int i = endIdx; i <= startIdx; i++)
   {
      double barHigh = iHigh(m_symbol, _Period, i);
      double barLow = iLow(m_symbol, _Period, i);
      if(barHigh > patternHigh) patternHigh = barHigh;
      if(barLow < patternLow) patternLow = barLow;
   }
   
   // Расширяем диапазон для лучшей видимости
   double range = patternHigh - patternLow;
   patternHigh += range * 0.1;
   patternLow -= range * 0.1;
   
   // Создаем уникальное имя объекта
   string rectName = "TrendChange_" + (isUptrend ? "UP_" : "DOWN_") + TimeToString(endTime, TIME_SECONDS);
   
   // Создаем прямоугольник для выделения смены тренда (приглушенные цвета)
   ObjectCreate(0, rectName, OBJ_RECTANGLE, 0, startTime, patternHigh, endTime, patternLow);
   ObjectSetInteger(0, rectName, OBJPROP_COLOR, isUptrend ? C'34,139,34' : C'178,34,34');  // Темно-зеленый / Темно-красный
   ObjectSetInteger(0, rectName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, rectName, OBJPROP_FILL, false);
   ObjectSetInteger(0, rectName, OBJPROP_BACK, false);
   ObjectSetString(0, rectName, OBJPROP_TOOLTIP, "Trend Change Pattern: " + (isUptrend ? "UPTREND" : "DOWNTREND"));
   
   if(m_debugMode)
   {
      Print("DEBUG TrendChangeDetector: Drew trend change pattern: ", isUptrend ? "UPTREND" : "DOWNTREND");
   }
}

//+------------------------------------------------------------------+
//| Метод проверки и рисования дневного диапазона                   |
//+------------------------------------------------------------------+
void CTrendChangeDetector::CheckAndDrawDailyRange()
{
   // Получаем текущий день
   datetime today = iTime(m_symbol, PERIOD_D1, 0);
   
   // Проверяем, рисовали ли мы уже диапазон для этого дня
   if(m_lastRangeDrawDay == today)
      return; // Уже рисовали для этого дня
   
   // Получаем диапазон прошлого дня
   double prevDayHigh, prevDayLow;
   GetPreviousDayRange(prevDayHigh, prevDayLow);
   
   // Если диапазон найден, рисуем его
   if(prevDayHigh > 0 && prevDayLow > 0)
   {
      DrawPreviousDayRange(prevDayHigh, prevDayLow);
      m_lastRangeDrawDay = today; // Отмечаем, что нарисовали для этого дня
   }
}

//+------------------------------------------------------------------+
//| Метод сброса сигналов                                            |
//+------------------------------------------------------------------+
void CTrendChangeDetector::ResetSignals()
{
   m_uptrendSignal = false;
   m_downtrendSignal = false;
}

//+------------------------------------------------------------------+