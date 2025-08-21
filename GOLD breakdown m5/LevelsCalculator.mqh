//+------------------------------------------------------------------+
//| LevelsCalculator.mqh                                             |
//| Модуль расчета уровней пробоя для GOLD Breakdown M5             |
//| Содержит логику расчета максимумов/минимумов предыдущего дня     |
//+------------------------------------------------------------------+

#property strict

//+------------------------------------------------------------------+
//| Класс для расчета уровней пробоя                                 |
//+------------------------------------------------------------------+
class CLevelsCalculator
{
private:
   string            m_symbol;              // Торговый символ
   bool              m_debugMode;           // Режим отладки
   
public:
   // Конструктор
   CLevelsCalculator(string symbol, bool debugMode = false);
   
   // Основные методы
   void              CalculatePreviousDayHighLow(double &prevDayHigh, double &prevDayLow);
   datetime          GetPreviousTradingDay(datetime currentTime);
   bool              AreBreakoutLevelsValid(double prevDayHigh, double prevDayLow);
};

//+------------------------------------------------------------------+
//| Конструктор класса                                               |
//+------------------------------------------------------------------+
CLevelsCalculator::CLevelsCalculator(string symbol, bool debugMode = false)
{
   m_symbol = symbol;
   m_debugMode = debugMode;
}

//+------------------------------------------------------------------+
//| Функция расчета максимума и минимума за период 16:00-20:00       |
//| предыдущего дня с проверкой на дневные экстремумы                |
//+------------------------------------------------------------------+
void CLevelsCalculator::CalculatePreviousDayHighLow(double &prevDayHigh, double &prevDayLow)
{
   // Получаем текущее время
   datetime currentTime = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   
   // Получаем дневные максимум и минимум предыдущего дня
   double dailyHigh = iHigh(m_symbol, PERIOD_D1, 1);
   double dailyLow = iLow(m_symbol, PERIOD_D1, 1);
   
   // Правильно рассчитываем предыдущий торговый день
   datetime prevTradingDay = GetPreviousTradingDay(currentTime);
   MqlDateTime prevDt;
   TimeToStruct(prevTradingDay, prevDt);
   
   // Формируем время начала и конца периода предыдущего торгового дня (16:00-20:00)
   datetime prevDayStart = StringToTime(StringFormat("%04d.%02d.%02d 16:00", prevDt.year, prevDt.mon, prevDt.day));
   datetime prevDayEnd = StringToTime(StringFormat("%04d.%02d.%02d 20:00", prevDt.year, prevDt.mon, prevDt.day));
   
   // Получаем данные за период 16:00-20:00 предыдущего дня (M5 = 5-минутные бары)
   double highArray[], lowArray[];
   datetime timeArray[];
   
   // Копируем данные за последние несколько дней, чтобы найти нужный период
   int barsCount = 500; // Достаточно баров для поиска нужного периода
   
   if(CopyHigh(m_symbol, PERIOD_M5, 0, barsCount, highArray) < 0 ||
      CopyLow(m_symbol, PERIOD_M5, 0, barsCount, lowArray) < 0 ||
      CopyTime(m_symbol, PERIOD_M5, 0, barsCount, timeArray) < 0)
   {
      // Если не удалось получить данные, используем fallback
      prevDayHigh = dailyHigh;
      prevDayLow = dailyLow;
      
      if(prevDayHigh <= 0 || prevDayLow <= 0)
      {
         prevDayHigh = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         prevDayLow = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      }
      return;
   }
   
   // Ищем максимум и минимум в период 16:00-20:00 предыдущего дня
   double sessionHigh = 0.0;
   double sessionLow = 999999.0;
   bool foundData = false;
   
   for(int i = 0; i < barsCount; i++)
   {
      // Проверяем, попадает ли время бара в нужный период
      if(timeArray[i] >= prevDayStart && timeArray[i] <= prevDayEnd)
      {
         foundData = true;
         
         if(highArray[i] > sessionHigh) sessionHigh = highArray[i];
         if(lowArray[i] < sessionLow) sessionLow = lowArray[i];
      }
   }
   
   // Если не нашли данные за нужный период, используем дневные уровни
   if(!foundData || sessionHigh <= 0 || sessionLow <= 0)
   {
      prevDayHigh = dailyHigh;
      prevDayLow = dailyLow;
      
      if(prevDayHigh <= 0 || prevDayLow <= 0)
      {
         prevDayHigh = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         prevDayLow = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      }
      return;
   }
   
   // Применяем фильтр: используем уровни сессии только если они совпадают с дневными экстремумами
   // Для HIGH: используем sessionHigh только если он равен dailyHigh
   // Для LOW: используем sessionLow только если он равен dailyLow
   
   double tolerance = 0.01; // Допуск для сравнения цен (1 пункт)
   
   // Проверяем HIGH
   if(MathAbs(sessionHigh - dailyHigh) <= tolerance)
   {
      prevDayHigh = sessionHigh; // Максимум сессии совпадает с дневным максимумом
   }
   else
   {
      prevDayHigh = 0.0; // Максимум сессии не является дневным максимумом - не торгуем пробой вверх
   }
   
   // Проверяем LOW
   if(MathAbs(sessionLow - dailyLow) <= tolerance)
   {
      prevDayLow = sessionLow; // Минимум сессии совпадает с дневным минимумом
   }
   else
   {
      prevDayLow = 999999.0; // Минимум сессии не является дневным минимумом - не торгуем пробой вниз
   }
   
   // Если ни один из уровней не подходит, НЕ торгуем вообще
   // Убираем fallback логику, которая противоречит основной фильтрации
   if(prevDayHigh <= 0 && prevDayLow >= 999999.0)
   {
      // Оставляем уровни недействительными - торговля не будет происходить
      if(m_debugMode)
      {
         Print("DEBUG: Ни один из уровней сессии 16:00-20:00 не совпадает с дневными экстремумами. Торговля отключена на сегодня.");
         Print("DEBUG: sessionHigh: ", (prevDayHigh <= 0 ? "недействителен" : DoubleToString(prevDayHigh, 2)),
               ", sessionLow: ", (prevDayLow >= 999999.0 ? "недействителен" : DoubleToString(prevDayLow, 2)));
      }
   }
   
   if(m_debugMode)
   {
      Print("DEBUG: Расчет уровней завершен. Итоговые уровни - High: ", prevDayHigh, ", Low: ", prevDayLow);
   }
}

//+------------------------------------------------------------------+
//| Функция получения предыдущего торгового дня                      |
//+------------------------------------------------------------------+
datetime CLevelsCalculator::GetPreviousTradingDay(datetime currentTime)
{
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   
   // Определяем количество дней для отступа назад
   int daysBack = 1;
   
   // Если сегодня понедельник (1), берем пятницу (отступаем на 3 дня)
   if(dt.day_of_week == 1) // Monday
   {
      daysBack = 3;
   }
   // Если сегодня воскресенье (0), берем пятницу (отступаем на 2 дня)
   else if(dt.day_of_week == 0) // Sunday
   {
      daysBack = 2;
   }
   
   // Отступаем назад на нужное количество дней
   datetime prevDay = currentTime - (daysBack * 24 * 60 * 60);
   
   return prevDay;
}

//+------------------------------------------------------------------+
//| Функция проверки валидности уровней пробоя                       |
//+------------------------------------------------------------------+
bool CLevelsCalculator::AreBreakoutLevelsValid(double prevDayHigh, double prevDayLow)
{
   // Проверяем, что хотя бы один из уровней действителен
   bool highValid = (prevDayHigh > 0.0 && prevDayHigh < 999999.0);
   bool lowValid = (prevDayLow > 0.0 && prevDayLow < 999999.0);
   
   if(m_debugMode && (!highValid || !lowValid))
   {
      Print("DEBUG: Валидация уровней - High: ", prevDayHigh, " (валиден: ", highValid,
            "), Low: ", prevDayLow, " (валиден: ", lowValid, ")");
   }
   
   return (highValid || lowValid);
}