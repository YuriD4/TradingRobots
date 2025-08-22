//+------------------------------------------------------------------+
//|                                               TrendChangeUtils.mqh |
//|                                    Copyright 2023, TradingRobots |
//|                                             https://www.example.com |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Класс вспомогательных функций для робота Trend Change            |
//+------------------------------------------------------------------+
class CTrendChangeUtils
{
private:
   string            m_symbol;              // Торговый символ
   bool              m_debugMode;           // Режим отладки
   double            m_pointValue;          // Значение пункта для символа
   
public:
   // Конструктор
   CTrendChangeUtils(string symbol, bool debugMode = false);
   
   // Методы проверки времени
   bool              IsTimeToClosePositions(int closeHour);
   bool              IsTradingTimeAllowed(int startHour, int endHour);
   
   // Методы расчета торговых параметров
   double            GetPointValue();
   double            CalculateDistanceInPoints(double price1, double price2);
   
   // Вспомогательные методы
   bool              IsYenPair();
};

//+------------------------------------------------------------------+
//| Конструктор класса                                               |
//+------------------------------------------------------------------+
CTrendChangeUtils::CTrendChangeUtils(string symbol, bool debugMode = false)
{
   m_symbol = symbol;
   m_debugMode = debugMode;
   m_pointValue = GetPointValue();
}

//+------------------------------------------------------------------+
//| Функция проверки времени закрытия позиций                       |
//+------------------------------------------------------------------+
bool CTrendChangeUtils::IsTimeToClosePositions(int closeHour)
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   // Проверяем, наступило ли указанное время или позже
   if(dt.hour >= closeHour)
   {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Функция проверки разрешенного времени для торговли               |
//+------------------------------------------------------------------+
bool CTrendChangeUtils::IsTradingTimeAllowed(int startHour, int endHour)
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentHour = dt.hour;
   
   // Обработка случая, когда конец торговли на следующий день
   if(endHour < startHour)
   {
      if(currentHour >= startHour || currentHour < endHour)
      {
         return true;
      }
   }
   else
   {
      if(currentHour >= startHour && currentHour < endHour)
      {
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Функция получения правильного значения пункта                   |
//+------------------------------------------------------------------+
double CTrendChangeUtils::GetPointValue()
{
   // Для пар с йеной (JPY) пункт - это 0.01 (третий знак после запятой)
   // Для остальных пар пункт - это 0.0001 (четвертый знак после запятой)
   if(IsYenPair())
   {
      return 0.01;
   }
   else
   {
      return 0.0001;
   }
}

//+------------------------------------------------------------------+
//| Функция расчета расстояния в пунктах                             |
//+------------------------------------------------------------------+
double CTrendChangeUtils::CalculateDistanceInPoints(double price1, double price2)
{
   double distance = MathAbs(price1 - price2);
   double points = distance / m_pointValue;
   
   
   return points;
}

//+------------------------------------------------------------------+
//| Функция проверки, является ли пара парой с йеной                |
//+------------------------------------------------------------------+
bool CTrendChangeUtils::IsYenPair()
{
   // Проверяем, содержит ли символ "JPY"
   return (StringFind(m_symbol, "JPY") >= 0);
}
//+------------------------------------------------------------------+