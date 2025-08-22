//+------------------------------------------------------------------+
//|                                        EngulfingPatternDetector.mqh |
//|                                    Copyright 2023, TradingRobots |
//|                                             https://www.example.com |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Класс для определения паттернов поглощения                      |
//+------------------------------------------------------------------+
class CEngulfingPatternDetector
{
private:
   string            m_symbol;              // Торговый символ
   bool              m_debugMode;           // Режим отладки
   
   // Переменные для отслеживания найденных паттернов
   datetime          m_lastBullishEngulfingTime;  // Время последнего бычьего поглощения
   datetime          m_lastBearishEngulfingTime;  // Время последнего медвежьего поглощения
   double            m_currentHighPrice;         // Актуальная цена вверх (хай красного бара)
   double            m_currentLowPrice;          // Актуальная цена вниз (лоу зеленого бара)
   
public:
   // Конструктор
   CEngulfingPatternDetector(string symbol, bool debugMode = false);
   
   // Основные методы
   bool              DetectEngulfingPatterns(datetime currentBarTime);
   
   // Методы доступа к информации о паттернах
   datetime          LastBullishEngulfingTime() const { return m_lastBullishEngulfingTime; }
   datetime          LastBearishEngulfingTime() const { return m_lastBearishEngulfingTime; }
   double            CurrentHighPrice() const { return m_currentHighPrice; }
   double            CurrentLowPrice() const { return m_currentLowPrice; }
   
private:
   // Вспомогательные методы для определения паттернов
   bool              DetectClassicEngulfing(datetime currentBarTime);
   bool              DetectThreeCandleEngulfing(datetime currentBarTime);
   bool              DetectFourCandleEngulfing(datetime currentBarTime);
};

//+------------------------------------------------------------------+
//| Конструктор класса                                               |
//+------------------------------------------------------------------+
CEngulfingPatternDetector::CEngulfingPatternDetector(string symbol, bool debugMode = false)
{
   m_symbol = symbol;
   m_debugMode = debugMode;
   m_lastBullishEngulfingTime = 0;
   m_lastBearishEngulfingTime = 0;
   m_currentHighPrice = 0.0;
   m_currentLowPrice = 0.0;
}

//+------------------------------------------------------------------+
//| Основной метод для определения паттернов поглощения              |
//+------------------------------------------------------------------+
bool CEngulfingPatternDetector::DetectEngulfingPatterns(datetime currentBarTime)
{
   
   // Проверяем классические паттерны поглощения
   if(DetectClassicEngulfing(currentBarTime))
   {
      if(m_debugMode)
      {
         Print("DEBUG EngulfingDetector: Classic engulfing pattern found");
      }
      return true;
   }
   
   // Проверяем трехсвечные паттерны поглощения
   if(DetectThreeCandleEngulfing(currentBarTime))
   {
      if(m_debugMode)
      {
         Print("DEBUG EngulfingDetector: Three-candle engulfing pattern found");
      }
      return true;
   }
   
   // Проверяем четырехсвечные паттерны поглощения
   if(DetectFourCandleEngulfing(currentBarTime))
   {
      if(m_debugMode)
      {
         Print("DEBUG EngulfingDetector: Four-candle engulfing pattern found");
      }
      return true;
   }
   
   if(m_debugMode)
   {
      Print("DEBUG EngulfingDetector: No engulfing patterns found");
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Метод для определения классических паттернов поглощения          |
//+------------------------------------------------------------------+
bool CEngulfingPatternDetector::DetectClassicEngulfing(datetime currentBarTime)
{
   // Получаем данные для баров
   double open1 = iOpen(m_symbol, _Period, 1);
   double close1 = iClose(m_symbol, _Period, 1);
   double high1 = iHigh(m_symbol, _Period, 1);
   double low1 = iLow(m_symbol, _Period, 1);
   
   double open2 = iOpen(m_symbol, _Period, 2);
   double close2 = iClose(m_symbol, _Period, 2);
   double high2 = iHigh(m_symbol, _Period, 2);
   double low2 = iLow(m_symbol, _Period, 2);
   
   double minGap = 0.5 * _Point;  // Уменьшили требование к зазору
   
   if(m_debugMode)
   {
      Print("DEBUG ClassicEngulfing: Bar1 O=", open1, " C=", close1, " H=", high1, " L=", low1);
      Print("DEBUG ClassicEngulfing: Bar2 O=", open2, " C=", close2, " H=", high2, " L=", low2);
      Print("DEBUG ClassicEngulfing: MinGap=", minGap);
      
      // Проверим все условия по отдельности
      bool bar2Bearish = (open2 > close2);
      bool bar1Bullish = (open1 < close1);
      bool openInRange = (open1 >= low2 && open1 <= high2);
      double gapAbove = (close1 - high2);
      bool hasGap = (gapAbove >= minGap);
      
      Print("DEBUG ClassicEngulfing: Bar2 bearish=", bar2Bearish, ", Bar1 bullish=", bar1Bullish,
            ", Open in range=", openInRange, ", Gap above=", gapAbove, ", Has gap=", hasGap);
   }
   
   // Проверяем бычье поглощение: бар 2 медвежий, бар 1 бычий
   if(open2 > close2 &&           // Бар 2 медвежий
      open1 < close1 &&           // Бар 1 бычий
      (open1 >= low2 && open1 <= high2) &&  // Цена открытия бара 1 в диапазоне бара 2
      ((close1 - high2) >= minGap))        // Закрытие бара 1 выше хая бара 2 с минимальным зазором
   {
      m_lastBullishEngulfingTime = currentBarTime;
      m_currentHighPrice = high2;  // Запоминаем актуальную цену вверх (хай красного бара)
      
      if(m_debugMode)
      {
         Print("DEBUG ClassicEngulfing: Classic bullish engulfing pattern detected at ", TimeToString(currentBarTime));
         Print("DEBUG ClassicEngulfing: Gap above = ", (close1 - high2));
      }
      
      return true;
   }
   
   // Проверяем медвежье поглощение: бар 2 бычий, бар 1 медвежий
   if(m_debugMode)
   {
      // Проверим все условия для медвежьего поглощения
      bool bar2Bullish = (open2 < close2);
      bool bar1Bearish = (open1 > close1);
      bool openInRange = (open1 >= low2 && open1 <= high2);
      double gapBelow = (low2 - close1);
      bool hasGap = (gapBelow >= minGap);
      
      Print("DEBUG ClassicEngulfing: Bear check - Bar2 bullish=", bar2Bullish, ", Bar1 bearish=", bar1Bearish,
            ", Open in range=", openInRange, ", Gap below=", gapBelow, ", Has gap=", hasGap);
   }
   
   if(open2 < close2 &&           // Бар 2 бычий
      open1 > close1 &&           // Бар 1 медвежий
      (open1 >= low2 && open1 <= high2) &&  // Цена открытия бара 1 в диапазоне бара 2
      ((low2 - close1) >= minGap))        // Закрытие бара 1 ниже лоу бара 2 с минимальным зазором
   {
      m_lastBearishEngulfingTime = currentBarTime;
      m_currentLowPrice = low2;    // Запоминаем актуальную цену вниз (лоу зеленого бара)
      
      if(m_debugMode)
      {
         Print("DEBUG ClassicEngulfing: Classic bearish engulfing pattern detected at ", TimeToString(currentBarTime));
         Print("DEBUG ClassicEngulfing: Gap below = ", (low2 - close1));
      }
      
      return true;
   }
   
   if(m_debugMode)
   {
      Print("DEBUG ClassicEngulfing: No classic engulfing pattern found");
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Метод для определения трехсвечных паттернов поглощения           |
//+------------------------------------------------------------------+
bool CEngulfingPatternDetector::DetectThreeCandleEngulfing(datetime currentBarTime)
{
   // Получаем данные для баров
   double open1 = iOpen(m_symbol, _Period, 1);
   double close1 = iClose(m_symbol, _Period, 1);
   double high1 = iHigh(m_symbol, _Period, 1);
   double low1 = iLow(m_symbol, _Period, 1);
   
   double open2 = iOpen(m_symbol, _Period, 2);
   double close2 = iClose(m_symbol, _Period, 2);
   double high2 = iHigh(m_symbol, _Period, 2);
   double low2 = iLow(m_symbol, _Period, 2);
   
   double open3 = iOpen(m_symbol, _Period, 3);
   double close3 = iClose(m_symbol, _Period, 3);
   double high3 = iHigh(m_symbol, _Period, 3);
   double low3 = iLow(m_symbol, _Period, 3);
   
   double minGap = 1.5 * _Point;
   
   // Проверяем бычье поглощение с одной промежуточной свечой
   if(open3 > close3 &&           // Бар 3 медвежий
      open1 < close1 &&           // Бар 1 бычий
      (open1 >= low3 && open1 <= high3) &&  // Цена открытия бара 1 в диапазоне бара 3
      ((close1 - high3) >= minGap))        // Закрытие бара 1 выше хая бара 3 с минимальным зазором
   {
      // Проверяем, что нет промежуточного бычьего поглощения
      bool adjacentBull = (open3 > close3 && open2 < close2 && 
                          (open2 >= low3 && open2 <= high3) && 
                          ((close2 - high3) >= minGap));
      
      if(!adjacentBull)
      {
         m_lastBullishEngulfingTime = currentBarTime;
         m_currentHighPrice = high3;  // Запоминаем актуальную цену вверх (хай красного бара)
         
         if(m_debugMode)
         {
            Print("Three-candle bullish engulfing pattern detected at ", TimeToString(currentBarTime));
         }
         
         return true;
      }
   }
   
   // Проверяем медвежье поглощение с одной промежуточной свечой
   if(open3 < close3 &&           // Бар 3 бычий
      open1 > close1 &&           // Бар 1 медвежий
      (open1 >= low3 && open1 <= high3) &&  // Цена открытия бара 1 в диапазоне бара 3
      ((low3 - close1) >= minGap))        // Закрытие бара 1 ниже лоу бара 3 с минимальным зазором
   {
      // Проверяем, что нет промежуточного медвежьего поглощения
      bool adjacentBear = (open3 < close3 && open2 > close2 && 
                           (open2 >= low3 && open2 <= high3) && 
                           ((low3 - close2) >= minGap));
      
      if(!adjacentBear)
      {
         m_lastBearishEngulfingTime = currentBarTime;
         m_currentLowPrice = low3;    // Запоминаем актуальную цену вниз (лоу зеленого бара)
         
         if(m_debugMode)
         {
            Print("Three-candle bearish engulfing pattern detected at ", TimeToString(currentBarTime));
         }
         
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Метод для определения четырехсвечных паттернов поглощения         |
//+------------------------------------------------------------------+
bool CEngulfingPatternDetector::DetectFourCandleEngulfing(datetime currentBarTime)
{
   // Получаем данные для баров
   double open1 = iOpen(m_symbol, _Period, 1);
   double close1 = iClose(m_symbol, _Period, 1);
   double high1 = iHigh(m_symbol, _Period, 1);
   double low1 = iLow(m_symbol, _Period, 1);
   
   double open2 = iOpen(m_symbol, _Period, 2);
   double close2 = iClose(m_symbol, _Period, 2);
   double high2 = iHigh(m_symbol, _Period, 2);
   double low2 = iLow(m_symbol, _Period, 2);
   
   double open3 = iOpen(m_symbol, _Period, 3);
   double close3 = iClose(m_symbol, _Period, 3);
   double high3 = iHigh(m_symbol, _Period, 3);
   double low3 = iLow(m_symbol, _Period, 3);
   
   double open4 = iOpen(m_symbol, _Period, 4);
   double close4 = iClose(m_symbol, _Period, 4);
   double high4 = iHigh(m_symbol, _Period, 4);
   double low4 = iLow(m_symbol, _Period, 4);
   
   double minGap = 1.5 * _Point;
   
   // Проверяем бычье поглощение с двумя промежуточными свечами
   if(open4 > close4 &&           // Бар 4 медвежий
      open1 < close1 &&           // Бар 1 бычий
      (open1 >= low4 && open1 <= high4) &&  // Цена открытия бара 1 в диапазоне бара 4
      ((close1 - high4) >= minGap))        // Закрытие бара 1 выше хая бара 4 с минимальным зазором
   {
      // Проверяем, что нет промежуточных бычьих поглощений
      bool intermediateBull1 = (open4 > close4 && open3 < close3 && 
                               (open3 >= low4 && open3 <= high4) && 
                               ((close3 - high4) >= minGap));
      
      bool intermediateBull2 = (open4 > close4 && open2 < close2 && 
                               (open2 >= low4 && open2 <= high4) && 
                               ((close2 - high4) >= minGap));
      
      // Проверяем, что нет промежуточного поглощения
      bool intermediateEngulf = (open3 > close3 && open2 < close2 && 
                                 (open2 >= low3 && open2 <= high3) && 
                                 ((close2 - high3) >= minGap));
      
      if(!intermediateBull1 && !intermediateBull2 && !intermediateEngulf)
      {
         m_lastBullishEngulfingTime = currentBarTime;
         m_currentHighPrice = high4;  // Запоминаем актуальную цену вверх (хай красного бара)
         
         if(m_debugMode)
         {
            Print("Four-candle bullish engulfing pattern detected at ", TimeToString(currentBarTime));
         }
         
         return true;
      }
   }
   
   // Проверяем медвежье поглощение с двумя промежуточными свечами
   if(open4 < close4 &&           // Бар 4 бычий
      open1 > close1 &&           // Бар 1 медвежий
      (open1 >= low4 && open1 <= high4) &&  // Цена открытия бара 1 в диапазоне бара 4
      ((low4 - close1) >= minGap))        // Закрытие бара 1 ниже лоу бара 4 с минимальным зазором
   {
      // Проверяем, что нет промежуточных медвежьих поглощений
      bool intermediateBear1 = (open4 < close4 && open3 > close3 && 
                                (open3 >= low4 && open3 <= high4) && 
                                ((low4 - close3) >= minGap));
      
      bool intermediateBear2 = (open4 < close4 && open2 > close2 && 
                                (open2 >= low4 && open2 <= high4) && 
                                ((low4 - close2) >= minGap));
      
      // Проверяем, что нет промежуточного поглощения
      bool intermediateEngulfBear = (open3 < close3 && open2 > close2 && 
                                     (open2 >= low3 && open2 <= high3) && 
                                     ((low3 - close2) >= minGap));
      
      if(!intermediateBear1 && !intermediateBear2 && !intermediateEngulfBear)
      {
         m_lastBearishEngulfingTime = currentBarTime;
         m_currentLowPrice = low4;    // Запоминаем актуальную цену вниз (лоу зеленого бара)
         
         
         return true;
      }
   }
   
   return false;
}
//+------------------------------------------------------------------+