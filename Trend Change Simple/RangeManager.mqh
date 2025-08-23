//+------------------------------------------------------------------+
//|                                                 RangeManager.mqh |
//|                                    Copyright 2023, TradingRobots |
//|                                             https://www.example.com |
//+------------------------------------------------------------------+
#property strict

#include "TrendChangeSimpleUtils.mqh"

//+------------------------------------------------------------------+
//| Класс для управления ценовыми диапазонами                       |
//+------------------------------------------------------------------+
class CRangeManager
{
private:
    string            m_symbol;              // Торговый символ
    bool              m_debugMode;           // Режим отладки
    CTrendChangeSimpleUtils* m_utils;        // Утилиты
    
    // Данные диапазона
    double            m_rangeHigh;           // Верхняя граница диапазона
    double            m_rangeLow;            // Нижняя граница диапазона
    datetime          m_rangeDate;           // Дата диапазона
    bool              m_rangeValid;          // Флаг валидности диапазона
    
    // Состояние пробоев
    bool              m_upBreakoutDetected;  // Обнаружен пробой вверх
    bool              m_downBreakoutDetected; // Обнаружен пробой вниз
    double            m_upBreakoutPrice;     // Цена пробоя вверх
    double            m_downBreakoutPrice;   // Цена пробоя вниз
    
public:
    // Конструктор и деструктор
    CRangeManager(string symbol, CTrendChangeSimpleUtils* utils, bool debugMode = false);
    ~CRangeManager();
    
    // Основные методы
    bool              UpdateRange();
    bool              CheckBreakout(double currentPrice, int breakoutPoints);
    void              ResetBreakouts();
    
    // Методы доступа к данным
    double            GetRangeHigh() const { return m_rangeHigh; }
    double            GetRangeLow() const { return m_rangeLow; }
    bool              IsRangeValid() const { return m_rangeValid; }
    bool              IsUpBreakoutDetected() const { return m_upBreakoutDetected; }
    bool              IsDownBreakoutDetected() const { return m_downBreakoutDetected; }
    double            GetUpBreakoutPrice() const { return m_upBreakoutPrice; }
    double            GetDownBreakoutPrice() const { return m_downBreakoutPrice; }
    
    // Вспомогательные методы
    void              DrawRange();
    
private:
    // Внутренние методы
    bool              CalculatePreviousDayRange(double &highPrice, double &lowPrice);
    bool              IsNewDay();
};

//+------------------------------------------------------------------+
//| Конструктор класса                                               |
//+------------------------------------------------------------------+
CRangeManager::CRangeManager(string symbol, CTrendChangeSimpleUtils* utils, bool debugMode = false)
{
    m_symbol = symbol;
    m_utils = utils;
    m_debugMode = debugMode;
    
    m_rangeHigh = 0.0;
    m_rangeLow = 0.0;
    m_rangeDate = 0;
    m_rangeValid = false;
    
    m_upBreakoutDetected = false;
    m_downBreakoutDetected = false;
    m_upBreakoutPrice = 0.0;
    m_downBreakoutPrice = 0.0;
    
    // Инициализируем диапазон при создании
    UpdateRange();
}

//+------------------------------------------------------------------+
//| Деструктор класса                                                |
//+------------------------------------------------------------------+
CRangeManager::~CRangeManager()
{
    // Очищаем графические объекты при удалении
    ObjectsDeleteAll(0, "Range_");
}

//+------------------------------------------------------------------+
//| Обновление диапазона                                             |
//+------------------------------------------------------------------+
bool CRangeManager::UpdateRange()
{
    // Проверяем, нужно ли обновлять диапазон (новый день)
    if(!IsNewDay() && m_rangeValid)
        return true;
    
    double highPrice, lowPrice;
    
    // Вычисляем диапазон предыдущего дня с 16:00 до 00:00
    if(CalculatePreviousDayRange(highPrice, lowPrice))
    {
        m_rangeHigh = highPrice;
        m_rangeLow = lowPrice;
        m_rangeDate = iTime(m_symbol, PERIOD_D1, 0);
        m_rangeValid = true;
        
        // Сбрасываем состояние пробоев для нового дня
        ResetBreakouts();
        
        // Рисуем новый диапазон
        DrawRange();
        
        if(m_debugMode)
        {
            Print("DEBUG RangeManager: Range updated for ", m_utils.TimeToString(m_rangeDate),
                  ". High=", m_rangeHigh, ", Low=", m_rangeLow);
        }
        
        return true;
    }
    else
    {
        m_rangeValid = false;
        
        if(m_debugMode)
        {
            Print("DEBUG RangeManager: Failed to calculate range for current day");
        }
        
        return false;
    }
}

//+------------------------------------------------------------------+
//| Проверка пробоя диапазона                                        |
//+------------------------------------------------------------------+
bool CRangeManager::CheckBreakout(double currentPrice, int breakoutPoints)
{
    if(!m_rangeValid)
        return false;
    
    double breakoutDistance = m_utils.PointsToPrice(breakoutPoints);
    
    // Проверяем пробой вверх
    if(!m_upBreakoutDetected && currentPrice > (m_rangeHigh + breakoutDistance))
    {
        m_upBreakoutDetected = true;
        m_upBreakoutPrice = currentPrice;
        
        if(m_debugMode)
        {
            Print("DEBUG RangeManager: UP breakout detected at price ", currentPrice,
                  " (range high=", m_rangeHigh, ", breakout distance=", breakoutDistance, ")");
        }
        
        return true;
    }
    
    // Проверяем пробой вниз
    if(!m_downBreakoutDetected && currentPrice < (m_rangeLow - breakoutDistance))
    {
        m_downBreakoutDetected = true;
        m_downBreakoutPrice = currentPrice;
        
        if(m_debugMode)
        {
            Print("DEBUG RangeManager: DOWN breakout detected at price ", currentPrice,
                  " (range low=", m_rangeLow, ", breakout distance=", breakoutDistance, ")");
        }
        
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Сброс состояния пробоев                                          |
//+------------------------------------------------------------------+
void CRangeManager::ResetBreakouts()
{
    m_upBreakoutDetected = false;
    m_downBreakoutDetected = false;
    m_upBreakoutPrice = 0.0;
    m_downBreakoutPrice = 0.0;
    
    if(m_debugMode)
    {
        Print("DEBUG RangeManager: Breakout states reset");
    }
}

//+------------------------------------------------------------------+
//| Вычисление диапазона предыдущего дня с 16:00 до 00:00           |
//+------------------------------------------------------------------+
bool CRangeManager::CalculatePreviousDayRange(double &highPrice, double &lowPrice)
{
    highPrice = 0;
    lowPrice = 0;
    
    // Получаем время начала вчерашнего дня (16:00)
    datetime yesterday = iTime(m_symbol, PERIOD_D1, 1);
    
    // Время начала: 16:00 вчерашнего дня
    MqlDateTime dt_start;
    TimeToStruct(yesterday, dt_start);
    dt_start.hour = 16;
    dt_start.min = 0;
    dt_start.sec = 0;
    datetime startTime = StructToTime(dt_start);
    
    // Время окончания: 00:00 сегодняшнего дня (на самом деле это полночь между вчерашним и сегодняшним днем)
    // Это на 8 часов больше, чем 16:00 вчерашнего дня
    datetime endTime = startTime + 8 * 3600; // 8 часов в секундах
    
    if(m_debugMode)
    {
        Print("DEBUG RangeManager: Calculating range for period: ", 
              m_utils.TimeToString(startTime), " to ", m_utils.TimeToString(endTime));
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
        if(barTime >= startTime && barTime < endTime)
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
        Print("DEBUG RangeManager: Range calculation result: ", foundData ? "Success" : "Failed");
        if(foundData)
            Print("DEBUG RangeManager: High=", highPrice, ", Low=", lowPrice);
    }
    
    return foundData;
}

//+------------------------------------------------------------------+
//| Проверка нового дня                                              |
//+------------------------------------------------------------------+
bool CRangeManager::IsNewDay()
{
    datetime currentDay = iTime(m_symbol, PERIOD_D1, 0);
    return (currentDay != m_rangeDate);
}

//+------------------------------------------------------------------+
//| Отрисовка диапазона                                              |
//+------------------------------------------------------------------+
void CRangeManager::DrawRange()
{
    if(!m_rangeValid)
        return;
    
    // Удаляем старые объекты
    ObjectsDeleteAll(0, "Range_");
    
    // Получаем текущее время для позиционирования линий
    datetime currentTime = iTime(m_symbol, _Period, 0);
    datetime endTime = currentTime + PeriodSeconds(_Period) * 10; // Линии на 10 баров вправо
    
    // Создаем уникальные имена объектов
    string highLineName = "Range_High_" + IntegerToString(m_rangeDate);
    string lowLineName = "Range_Low_" + IntegerToString(m_rangeDate);
    string rangeName = "Range_Rect_" + IntegerToString(m_rangeDate);
    
    // Создаем линию максимума диапазона
    ObjectCreate(0, highLineName, OBJ_TREND, 0, currentTime, m_rangeHigh, endTime, m_rangeHigh);
    ObjectSetInteger(0, highLineName, OBJPROP_COLOR, clrBlue);
    ObjectSetInteger(0, highLineName, OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, highLineName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, highLineName, OBJPROP_RAY_RIGHT, false);
    ObjectSetString(0, highLineName, OBJPROP_TOOLTIP, "Range High: " + DoubleToString(m_rangeHigh, _Digits));
    
    // Создаем линию минимума диапазона
    ObjectCreate(0, lowLineName, OBJ_TREND, 0, currentTime, m_rangeLow, endTime, m_rangeLow);
    ObjectSetInteger(0, lowLineName, OBJPROP_COLOR, clrRed);
    ObjectSetInteger(0, lowLineName, OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, lowLineName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, lowLineName, OBJPROP_RAY_RIGHT, false);
    ObjectSetString(0, lowLineName, OBJPROP_TOOLTIP, "Range Low: " + DoubleToString(m_rangeLow, _Digits));
    
    // Создаем прямоугольник для выделения диапазона
    ObjectCreate(0, rangeName, OBJ_RECTANGLE, 0, currentTime, m_rangeHigh, endTime, m_rangeLow);
    ObjectSetInteger(0, rangeName, OBJPROP_COLOR, clrLightGray);
    ObjectSetInteger(0, rangeName, OBJPROP_FILL, true);
    ObjectSetInteger(0, rangeName, OBJPROP_BACK, true);
    ObjectSetString(0, rangeName, OBJPROP_TOOLTIP, "Previous Day Range (16:00-00:00)");
    
    if(m_debugMode)
    {
        Print("DEBUG RangeManager: Range visualization drawn");
    }
}
//+------------------------------------------------------------------+