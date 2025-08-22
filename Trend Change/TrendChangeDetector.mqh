//+------------------------------------------------------------------+
//|                                          TrendChangeDetector.mqh |
//|                                    Copyright 2023, TradingRobots |
//|                                             https://www.example.com |
//+------------------------------------------------------------------+
#property strict

#include "EngulfingPatternDetector.mqh"

//+------------------------------------------------------------------+
//| Класс для определения сигналов смены тренда                     |
//+------------------------------------------------------------------+
class CTrendChangeDetector
{
private:
   string            m_symbol;              // Торговый символ
   bool              m_debugMode;           // Режим отладки
   CEngulfingPatternDetector* m_patternDetector; // Детектор паттернов
   
   // Параметры для отслеживания смены тренда
   int               m_maxBarsBetweenPatterns; // Максимальное количество баров между поглощениями
   datetime          m_lastUsedBullishEngulfingTime; // Время бычьего поглощения, уже использованного в модели смены тренда
   datetime          m_lastUsedBearishEngulfingTime; // Время медвежьего поглощения, уже использованного в модели смены тренда
   
   // Флаги сигналов
   bool              m_uptrendSignal;       // Сигнал на восходящий тренд
   bool              m_downtrendSignal;     // Сигнал на нисходящий тренд
   
public:
   // Конструктор и деструктор
   CTrendChangeDetector(string symbol, bool debugMode = false);
   ~CTrendChangeDetector();
   
   // Основные методы
   void              ProcessBar(datetime currentBarTime);
   
   // Методы доступа к сигналам
   bool              IsUptrendSignal() const { return m_uptrendSignal; }
   bool              IsDowntrendSignal() const { return m_downtrendSignal; }
   
   // Методы сброса сигналов
   void              ResetSignals();
   
private:
   // Вспомогательные методы
   bool              CheckUptrendCondition(datetime currentBarTime);
   bool              CheckDowntrendCondition(datetime currentBarTime);
   bool              IsDayLow(double price);
   bool              IsDayHigh(double price);
   bool              Is12HourLow(double price);
   bool              Is12HourHigh(double price);
};

//+------------------------------------------------------------------+
//| Конструктор класса                                               |
//+------------------------------------------------------------------+
CTrendChangeDetector::CTrendChangeDetector(string symbol, bool debugMode = false)
{
   m_symbol = symbol;
   m_debugMode = debugMode;
   m_patternDetector = new CEngulfingPatternDetector(symbol, debugMode);
   m_maxBarsBetweenPatterns = 15;
   m_lastUsedBullishEngulfingTime = 0;
   m_lastUsedBearishEngulfingTime = 0;
   m_uptrendSignal = false;
   m_downtrendSignal = false;
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
   
   // Проверяем, является ли это минимальной ценой текущего дня
   if(!IsDayLow(minPrice))
   {
      if(m_debugMode)
      {
         Print("DEBUG TrendChangeDetector: Uptrend check failed - minPrice is not day low");
      }
      return false;
   }
   
   if(m_debugMode)
   {
      Print("DEBUG TrendChangeDetector: Uptrend condition check PASSED: barsBetween=", barsBetween,
            ", close1=", close1, ", currentLowPrice=", currentLowPrice,
            ", minPrice=", minPrice);
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
   
   // Проверяем, является ли это максимальной ценой текущего дня
   if(!IsDayHigh(maxPrice))
      return false;
   
   // Дополнительная проверка: максимум диапазона должен быть самой высокой ценой за последние 12 часов
   if(!Is12HourHigh(maxPrice))
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Метод проверки, является ли цена минимумом дня                  |
//+------------------------------------------------------------------+
bool CTrendChangeDetector::IsDayLow(double price)
{
   datetime currentDay = iTime(m_symbol, PERIOD_D1, 0);
   int barsPerDay = PeriodSeconds(PERIOD_D1) / PeriodSeconds(_Period);
   
   for(int i = 0; i < barsPerDay; i++)
   {
      // Проверяем только бары текущего дня
      if(iTime(m_symbol, _Period, i) < currentDay)
         break;
         
      double dayLow = iLow(m_symbol, _Period, i);
      if(dayLow < price)
      {
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Метод проверки, является ли цена максимумом дня                  |
//+------------------------------------------------------------------+
bool CTrendChangeDetector::IsDayHigh(double price)
{
   datetime currentDay = iTime(m_symbol, PERIOD_D1, 0);
   int barsPerDay = PeriodSeconds(PERIOD_D1) / PeriodSeconds(_Period);
   
   for(int i = 0; i < barsPerDay; i++)
   {
      // Проверяем только бары текущего дня
      if(iTime(m_symbol, _Period, i) < currentDay)
         break;
         
      double dayHigh = iHigh(m_symbol, _Period, i);
      if(dayHigh > price)
      {
         if(m_debugMode)
         {
            Print("Price ", price, " is not day high. Found higher price: ", dayHigh);
         }
         return false;
      }
   }
   
   return true;
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
//| Метод проверки, является ли цена минимумом за последние 12 часов |
//+------------------------------------------------------------------+
bool CTrendChangeDetector::Is12HourLow(double price)
{
   // Получаем количество баров за 12 часов
   int barsIn12Hours = (12 * 3600) / PeriodSeconds(_Period);
   
   for(int i = 0; i < barsIn12Hours; i++)
   {
      double barLow = iLow(m_symbol, _Period, i);
      if(barLow < price)
      {
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Метод проверки, является ли цена максимумом за последние 12 часов |
//+------------------------------------------------------------------+
bool CTrendChangeDetector::Is12HourHigh(double price)
{
   // Получаем количество баров за 12 часов
   int barsIn12Hours = (12 * 3600) / PeriodSeconds(_Period);
   
   for(int i = 0; i < barsIn12Hours; i++)
   {
      double barHigh = iHigh(m_symbol, _Period, i);
      if(barHigh > price)
      {
         return false;
      }
   }
   
   return true;
}
//+------------------------------------------------------------------+