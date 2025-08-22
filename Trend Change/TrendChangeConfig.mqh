//+------------------------------------------------------------------+
//|                                              TrendChangeConfig.mqh |
//|                                    Copyright 2023, TradingRobots |
//|                                             https://www.example.com |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Класс конфигурации робота Trend Change                           |
//+------------------------------------------------------------------+
class CTrendChangeConfig
{
private:
   // Входные параметры
   int               m_magicNumber;           // Магический номер
   double            m_lotSize;               // Базовый размер лота
   double            m_takeProfitMultiplier;   // Множитель для тейк-профита
   int               m_maxDistanceToDayLow;    // Макс. расстояние до минимума дня в пунктах
   int               m_maxDistanceToDayHigh;   // Макс. расстояние до максимума дня в пунктах
   bool              m_useTrailingStop;        // Использовать трейлинг-стоп
   bool              m_closeOnOppositeSignal;  // Закрывать при противоположном сигнале
   int               m_tradingStartHour;       // Начало торгового времени (часы)
   int               m_tradingEndHour;         // Конец торгового времени (часы)
   bool              m_forceCloseAfterHours;   // Принудительно закрывать позиции вне торговых часов
   bool              m_validateTwoDayExtremes; // Проверять что экстремум диапазона является экстремумом за сегодня и вчера
   bool              m_useDailyMartingale;     // Использовать дневной мартингейл
   double            m_martingaleMultiplier;   // Мультипликатор лота для мартингейла
   bool              m_debugMode;             // Режим отладки
   
public:
   // Конструктор
   CTrendChangeConfig(
      int magicNumber = 123456,
      double lotSize = 0.01,
      double takeProfitMultiplier = 2.0,
      int maxDistanceToDayLow = 20,
      int maxDistanceToDayHigh = 20,
      bool useTrailingStop = true,
      bool closeOnOppositeSignal = true,
      int tradingStartHour = 0,
      int tradingEndHour = 23,
      bool forceCloseAfterHours = false,
      bool validateTwoDayExtremes = true,
      bool useDailyMartingale = true,
      double martingaleMultiplier = 2.0,
      bool debugMode = true
   );
   
   // Методы доступа к параметрам
   int               MagicNumber() const { return m_magicNumber; }
   double            LotSize() const { return m_lotSize; }
   double            TakeProfitMultiplier() const { return m_takeProfitMultiplier; }
   int               MaxDistanceToDayLow() const { return m_maxDistanceToDayLow; }
   int               MaxDistanceToDayHigh() const { return m_maxDistanceToDayHigh; }
   bool              UseTrailingStop() const { return m_useTrailingStop; }
   bool              CloseOnOppositeSignal() const { return m_closeOnOppositeSignal; }
   int               TradingStartHour() const { return m_tradingStartHour; }
   int               TradingEndHour() const { return m_tradingEndHour; }
   bool              ForceCloseAfterHours() const { return m_forceCloseAfterHours; }
   bool              ValidateTwoDayExtremes() const { return m_validateTwoDayExtremes; }
   bool              UseDailyMartingale() const { return m_useDailyMartingale; }
   double            MartingaleMultiplier() const { return m_martingaleMultiplier; }
   bool              DebugMode() const { return m_debugMode; }
};

//+------------------------------------------------------------------+
//| Конструктор класса                                               |
//+------------------------------------------------------------------+
CTrendChangeConfig::CTrendChangeConfig(
   int magicNumber,
   double lotSize,
   double takeProfitMultiplier,
   int maxDistanceToDayLow,
   int maxDistanceToDayHigh,
   bool useTrailingStop,
   bool closeOnOppositeSignal,
   int tradingStartHour,
   int tradingEndHour,
   bool forceCloseAfterHours,
   bool validateTwoDayExtremes,
   bool useDailyMartingale,
   double martingaleMultiplier,
   bool debugMode
)
{
   // Установка значений из параметров
   m_magicNumber = magicNumber;
   m_lotSize = lotSize;
   m_takeProfitMultiplier = takeProfitMultiplier;
   m_maxDistanceToDayLow = maxDistanceToDayLow;
   m_maxDistanceToDayHigh = maxDistanceToDayHigh;
   m_useTrailingStop = useTrailingStop;
   m_closeOnOppositeSignal = closeOnOppositeSignal;
   m_tradingStartHour = tradingStartHour;
   m_tradingEndHour = tradingEndHour;
   m_forceCloseAfterHours = forceCloseAfterHours;
   m_validateTwoDayExtremes = validateTwoDayExtremes;
   m_useDailyMartingale = useDailyMartingale;
   m_martingaleMultiplier = martingaleMultiplier;
   m_debugMode = debugMode;
}
//+------------------------------------------------------------------+