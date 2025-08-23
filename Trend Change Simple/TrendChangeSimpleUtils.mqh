//+------------------------------------------------------------------+
//|                                        TrendChangeSimpleUtils.mqh |
//|                                    Copyright 2023, TradingRobots |
//|                                             https://www.example.com |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Класс вспомогательных функций для упрощенного Trend Change      |
//+------------------------------------------------------------------+
class CTrendChangeSimpleUtils
{
private:
    string            m_symbol;              // Торговый символ
    bool              m_debugMode;           // Режим отладки
    double            m_pointValue;          // Значение пункта для символа
    
public:
    // Конструктор
    CTrendChangeSimpleUtils(string symbol, bool debugMode = false);
    
    // Методы проверки времени
    bool              IsTradingTimeAllowed(int startHour, int endHour);
    
    // Методы расчета торговых параметров
    double            GetPointValue();
    double            CalculateDistanceInPoints(double price1, double price2);
    double            PointsToPrice(double points);
    
    // Вспомогательные методы
    bool              IsYenPair();
    string            TimeToString(datetime time);
};

//+------------------------------------------------------------------+
//| Конструктор класса                                               |
//+------------------------------------------------------------------+
CTrendChangeSimpleUtils::CTrendChangeSimpleUtils(string symbol, bool debugMode = false)
{
    m_symbol = symbol;
    m_debugMode = debugMode;
    m_pointValue = GetPointValue();
}

//+------------------------------------------------------------------+
//| Функция проверки разрешенного времени для торговли               |
//+------------------------------------------------------------------+
bool CTrendChangeSimpleUtils::IsTradingTimeAllowed(int startHour, int endHour)
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
double CTrendChangeSimpleUtils::GetPointValue()
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
double CTrendChangeSimpleUtils::CalculateDistanceInPoints(double price1, double price2)
{
    double distance = MathAbs(price1 - price2);
    double points = distance / m_pointValue;
    
    return points;
}

//+------------------------------------------------------------------+
//| Функция конвертации пунктов в цену                               |
//+------------------------------------------------------------------+
double CTrendChangeSimpleUtils::PointsToPrice(double points)
{
    return points * m_pointValue;
}

//+------------------------------------------------------------------+
//| Функция проверки, является ли пара парой с йеной                |
//+------------------------------------------------------------------+
bool CTrendChangeSimpleUtils::IsYenPair()
{
    // Проверяем, содержит ли символ "JPY"
    return (StringFind(m_symbol, "JPY") >= 0);
}

//+------------------------------------------------------------------+
//| Функция преобразования времени в строку                          |
//+------------------------------------------------------------------+
string CTrendChangeSimpleUtils::TimeToString(datetime time)
{
    return ::TimeToString(time, TIME_DATE | TIME_MINUTES);
}
//+------------------------------------------------------------------+