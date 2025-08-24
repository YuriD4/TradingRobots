//+------------------------------------------------------------------+
//|                                    TrendChangeSimpleConfig.mqh |
//|                                    Copyright 2023, TradingRobots |
//|                                             https://www.example.com |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Класс конфигурации упрощенного робота Trend Change              |
//+------------------------------------------------------------------+
class CTrendChangeSimpleConfig
{
private:
    // Входные параметры
    int               m_magicNumber;           // Магический номер
    double            m_lotSize;               // Базовый размер лота
    int               m_breakoutPoints;        // Количество пунктов для пробоя диапазона
    int               m_stopLossPoints;        // Фиксированный стоп-лосс в пунктах
    double            m_takeProfitMultiplier;  // Множитель тейк-профита относительно стоп-лосса
    int               m_maxReversals;          // Максимальное количество разворотов (0 = только одна сделка)
    double            m_lotScalingFactor;      // Коэффициент увеличения лота при развороте
    int               m_tradingStartHour;      // Начало торговли (часы)
    int               m_tradingEndHour;        // Окончание торговли (часы)
    bool              m_debugMode;             // Режим отладки
    bool              m_reverseOnBreakeven;    // Разворачиваться ли при закрытии по безубытку
    int               m_maxBreakoutReturnHours; // Максимальное время между пробоем и возвратом (часы)
    
public:
    // Конструктор
    CTrendChangeSimpleConfig(
        int magicNumber = 234567,
        double lotSize = 0.01,
        int breakoutPoints = 10,
        int stopLossPoints = 20,
        double takeProfitMultiplier = 2.0,
        int maxReversals = 3,
        double lotScalingFactor = 1.0,
        int tradingStartHour = 0,
        int tradingEndHour = 23,
        bool debugMode = true,
        bool reverseOnBreakeven = true,
        int maxBreakoutReturnHours = 3
    );
    
    // Методы доступа к параметрам
    int               MagicNumber() const { return m_magicNumber; }
    double            LotSize() const { return m_lotSize; }
    int               BreakoutPoints() const { return m_breakoutPoints; }
    int               StopLossPoints() const { return m_stopLossPoints; }
    double            TakeProfitMultiplier() const { return m_takeProfitMultiplier; }
    int               MaxReversals() const { return m_maxReversals; }
    double            LotScalingFactor() const { return m_lotScalingFactor; }
    int               TradingStartHour() const { return m_tradingStartHour; }
    int               TradingEndHour() const { return m_tradingEndHour; }
    bool              DebugMode() const { return m_debugMode; }
    bool              ReverseOnBreakeven() const { return m_reverseOnBreakeven; }
    int               MaxBreakoutReturnHours() const { return m_maxBreakoutReturnHours; }
};

//+------------------------------------------------------------------+
//| Конструктор класса                                               |
//+------------------------------------------------------------------+
CTrendChangeSimpleConfig::CTrendChangeSimpleConfig(
    int magicNumber,
    double lotSize,
    int breakoutPoints,
    int stopLossPoints,
    double takeProfitMultiplier,
    int maxReversals,
    double lotScalingFactor,
    int tradingStartHour,
    int tradingEndHour,
    bool debugMode,
    bool reverseOnBreakeven,
    int maxBreakoutReturnHours
)
{
    m_magicNumber = magicNumber;
    m_lotSize = lotSize;
    m_breakoutPoints = breakoutPoints;
    m_stopLossPoints = stopLossPoints;
    m_takeProfitMultiplier = takeProfitMultiplier;
    m_maxReversals = maxReversals;
    m_lotScalingFactor = lotScalingFactor;
    m_tradingStartHour = tradingStartHour;
    m_tradingEndHour = tradingEndHour;
    m_debugMode = debugMode;
    m_reverseOnBreakeven = reverseOnBreakeven;
    m_maxBreakoutReturnHours = maxBreakoutReturnHours;
}
//+------------------------------------------------------------------+