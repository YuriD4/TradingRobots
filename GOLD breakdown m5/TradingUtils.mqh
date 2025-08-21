//+------------------------------------------------------------------+
//| TradingUtils.mqh                                                 |
//| Вспомогательные функции для GOLD Breakdown M5                   |
//| Содержит утилитарные функции общего назначения                  |
//+------------------------------------------------------------------+

#property strict

//+------------------------------------------------------------------+
//| Класс вспомогательных торговых функций                           |
//+------------------------------------------------------------------+
class CTradingUtils
{
private:
   string            m_symbol;              // Торговый символ
   bool              m_debugMode;           // Режим отладки
   bool              m_mondayTradingEnabled; // Разрешена ли торговля в понедельник
   
public:
   // Конструктор
   CTradingUtils(string symbol, bool mondayTradingEnabled = true, bool debugMode = false);
   
   // Методы проверки времени и дня
   bool              IsMonday();
   bool              IsTradingAllowedToday();
   bool              IsTimeToClosePositions();
   bool              IsEnoughTimePassedAfterDayChange();
   
   // Методы расчета торговых параметров
   double            CalculateBaseLotSize();
   double            CalculatePointValue();
};

//+------------------------------------------------------------------+
//| Конструктор класса                                               |
//+------------------------------------------------------------------+
CTradingUtils::CTradingUtils(string symbol, bool mondayTradingEnabled = true, bool debugMode = false)
{
   m_symbol = symbol;
   m_mondayTradingEnabled = mondayTradingEnabled;
   m_debugMode = debugMode;
}

//+------------------------------------------------------------------+
//| Функция проверки, является ли текущий день понедельником         |
//+------------------------------------------------------------------+
bool CTradingUtils::IsMonday()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   // dt.day_of_week: 0=Sunday, 1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, 6=Saturday
   return (dt.day_of_week == 1);
}

//+------------------------------------------------------------------+
//| Функция проверки разрешения торговли в текущий день              |
//+------------------------------------------------------------------+
bool CTradingUtils::IsTradingAllowedToday()
{
   // Если торговля в понедельник отключена и сегодня понедельник
   if(!m_mondayTradingEnabled && IsMonday())
   {
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Функция проверки времени закрытия позиций (22:00)                |
//+------------------------------------------------------------------+
bool CTradingUtils::IsTimeToClosePositions()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   // Проверяем, наступило ли время 22:00 или позже
   if(dt.hour >= 22)
   {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Функция проверки времени после смены дня                         |
//+------------------------------------------------------------------+
bool CTradingUtils::IsEnoughTimePassedAfterDayChange()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   // Ждем минимум 5 минут после начала дня (00:05)
   // Это предотвращает немедленное открытие сделок при инициализации
   if(dt.hour == 0 && dt.min < 5)
   {
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Функция расчета базового размера лота                            |
//+------------------------------------------------------------------+
double CTradingUtils::CalculateBaseLotSize()
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double lotSize = (accountBalance / 1000.0) * 0.01; // 0.01 лота на каждую $1000
   
   // Ограничиваем минимальный и максимальный размер лота
   double minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
   
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   
   // Округляем до шага изменения размера лота
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Функция расчета правильного значения пункта для золота           |
//+------------------------------------------------------------------+
double CTradingUtils::CalculatePointValue()
{
   // Для золота с 2 знаками после запятой (2000.50):
   // 100 пунктов = 1.00 = $1
   // Значит 1 пункт = 0.01
   return _Point;
}