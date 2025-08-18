#ifndef __TELEGRAMHELPER_MQH__
#define __TELEGRAMHELPER_MQH__

// Заданные идентификаторы бота и каналов Telegram
string botID  = "7605936257:AAGwJkjnBVuJ0IxW8vCzpM2iwD-TIPF8EjQ";
string chatID = "-1002499921493";           // Канал для обычных сообщений (вливания)
string trendChangeChatID = "-1002633851129"; // Канал для сообщений о смене тренда (M30)
string closeClosingBarChatID = "-1002499921493"; // Канал для сообщений о барах близкого закрытия
string reserveTrendChatID = "-1002614415501"; // Резервный канал для H1, H4, D1 смены тренда

// Массивы таймфреймов для отправки уведомлений

// Таймфреймы для моделей вливания (поглощения)
static ENUM_TIMEFRAMES AbsorptionTimeframes[] = {
   PERIOD_D1
};

// Таймфреймы для моделей смены тренда
static ENUM_TIMEFRAMES TrendChangeTimeframes[] = {
   PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1
};

// Таймфреймы для моделей баров близкого закрытия
static ENUM_TIMEFRAMES CloseClosingBarTimeframes[] = {
   PERIOD_D1, PERIOD_W1
};

// Переменные для хранения времени последних оповещений (локально в модуле)
static datetime lastAlertTime = 0;
static datetime lastTrendChangeAlertTime = 0;
static datetime lastCloseClosingBarAlertTime = 0;

//+------------------------------------------------------------------+
//| Функция отправки сообщения в Telegram через WebRequest           |
//| Использует GET-запрос для отправки сообщения.                    |
//| Параметры определяют, в какой канал отправлять сообщение         |
//+------------------------------------------------------------------+
int SendTelegramMessage(string message, bool useTrendChannel = false, bool useCloseClosingBarChannel = false, bool useReserveTrendChannel = false)
{
    // Выбираем ID канала в зависимости от типа сообщения
    string targetChatID = chatID; // По умолчанию - канал для обычных сообщений
    
    if(useTrendChannel)
    {
        if(useReserveTrendChannel)
            targetChatID = reserveTrendChatID;
        else
            targetChatID = trendChangeChatID;
    }
    else if(useCloseClosingBarChannel)
        targetChatID = closeClosingBarChatID;
    // Параметр useWeeklyHighLowChannel удален, так как функциональность отключена
    
    // Формируем URL запроса
    string url = "https://api.telegram.org/bot" + botID + "/sendMessage?chat_id=" + targetChatID + "&text=" + message;
    string result;
    string cookie = NULL;
    char post[], resultt[];
    int res = WebRequest("GET", url, cookie, NULL, 10000, post, 10000, resultt, result);
    return res;
}

//+------------------------------------------------------------------+
//| Функция кодирования URL (чтобы избежать ошибок в Telegram API)    |
//+------------------------------------------------------------------+
string UrlEncode(string text)
{
   uchar bytes[];
   StringToCharArray(text, bytes);
   string encoded = "";
   for(int i = 0; i < ArraySize(bytes) - 1; i++)
   {
      uchar c = bytes[i];
      if( (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') ||
          (c >= 'a' && c <= 'z') || c == '-' || c == '_' ||
          c == '.' || c == '~')
         encoded += CharToString(c);
      else
         encoded += "%" + StringFormat("%02X", c);
   }
   return encoded;
}

//+------------------------------------------------------------------+
//| Функция получения строкового представления таймфрейма            |
//+------------------------------------------------------------------+
string GetTimeFrameString()
{
   int period = Period();
   switch(period)
   {
      case PERIOD_M1:   return "M1";
      case PERIOD_M5:   return "M5";
      case PERIOD_M15:  return "M15";
      case PERIOD_M30:  return "M30";
      case PERIOD_H1:   return "H1";
      case PERIOD_H4:   return "H4";
      case PERIOD_D1:   return "D1";
      case PERIOD_W1:   return "W1";
      case PERIOD_MN1:  return "MN";
      default:          return IntegerToString(period);
   }
}

//+------------------------------------------------------------------+
//| Функция проверки, содержится ли таймфрейм в массиве              |
//+------------------------------------------------------------------+
bool IsTimeframeInArray(ENUM_TIMEFRAMES timeframe, ENUM_TIMEFRAMES &timeframes[])
{
   for(int i = 0; i < ArraySize(timeframes); i++)
   {
      if(timeframes[i] == timeframe)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Функция отправки сообщений в Telegram и рисования стрелок         |
//| Принимает параметры, необходимые для формирования сообщения и     |
//| создания графических объектов.                                   |
//+------------------------------------------------------------------+
void SendAlertAndDraw(bool bullishFound, bool bearishFound, datetime currentBarTime, double arrowPrice)
{
    // Если сообщение для данного бара уже отправлено, выходим
    if(currentBarTime == lastAlertTime)
       return;
    
    string symbolName = _Symbol;
    string tf = GetTimeFrameString();
    string msg;
    
    // Проверяем, есть ли текущий таймфрейм в массиве для моделей вливания
    bool sendToTelegram = IsTimeframeInArray(Period(), AbsorptionTimeframes);
    
    if(bullishFound)
    {
       msg = "Вливание 🔼 - " + symbolName + " (" + tf + ")";
       Print("Готовимся отправить сообщение: ", msg);
       
       // Отправляем сообщение только если таймфрейм в списке разрешенных
       if(sendToTelegram)
          SendTelegramMessage(msg);
       else
          Print(tf + " timeframe: Telegram notification skipped for engulfing pattern");
       
       // Убрали создание объекта стрелки для бычьего паттерна
    }
    else if(bearishFound)
    {
       msg = "Вливание 🔽 - " + symbolName + " (" + tf + ")";
       Print("Готовимся отправить сообщение: ", msg);
       
       // Отправляем сообщение только если таймфрейм в списке разрешенных
       if(sendToTelegram)
          SendTelegramMessage(msg);
       else
          Print(tf + " timeframe: Telegram notification skipped for engulfing pattern");
       
       // Убрали создание объекта стрелки для медвежьего паттерна
    }
    lastAlertTime = currentBarTime;
}

//+------------------------------------------------------------------+
//| Функция отправки сообщений о смене тренда в Telegram и            |
//| рисования специальных индикаторов на графике                     |
//+------------------------------------------------------------------+
void SendTrendChangeAlert(bool uptrend, datetime currentBarTime, double arrowPrice)
{
    // Если сообщение для данного бара уже отправлено, выходим
    if(currentBarTime == lastTrendChangeAlertTime)
       return;
    
    string symbolName = _Symbol;
    string tf = GetTimeFrameString();
    string msg;
    
    // Проверяем, есть ли текущий таймфрейм в массиве для моделей смены тренда
    bool sendToTelegram = IsTimeframeInArray(Period(), TrendChangeTimeframes);
    
    if(uptrend)
    {
       msg = "СМЕНА ТРЕНДА ⬆️ - " + symbolName + " (" + tf + ")";
       Print("Готовимся отправить сообщение о смене тренда вверх: ", msg);
       
       // Определяем, использовать ли резервный канал на основе таймфрейма
       bool useReserveChannel = (Period() == PERIOD_H1 || Period() == PERIOD_H4 || Period() == PERIOD_D1);
       
       // Отправляем сообщение только если таймфрейм в списке разрешенных
       if(sendToTelegram)
          SendTelegramMessage(msg, true, false, useReserveChannel);
       else
          Print(tf + " timeframe: Telegram notification skipped for trend change");
       
       // Создание текстового объекта "CT" для смены тренда вверх
       string objName = "TrendUpChange_" + TimeToString(currentBarTime, TIME_DATE|TIME_SECONDS);
       if(!ObjectCreate(0, objName, OBJ_TEXT, 0, currentBarTime, arrowPrice))
          Print("Ошибка создания текстового объекта смены тренда: ", GetLastError());
       else
       {
          // Устанавливаем свойства для текстового объекта
          ObjectSetString(0, objName, OBJPROP_TEXT, "CT"); // Текст "CT" (английские буквы)
          ObjectSetInteger(0, objName, OBJPROP_COLOR, clrLime);
          ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 12); // Увеличенный размер шрифта
          ObjectSetInteger(0, objName, OBJPROP_BACK, false);   // Не на заднем плане
          ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false); // Не выбираемая
          ObjectSetInteger(0, objName, OBJPROP_HIDDEN, false);   // Не скрыта в списке объектов
          ObjectSetInteger(0, objName, OBJPROP_ZORDER, 200);     // Высокий приоритет для отображения поверх других элементов
          ChartRedraw(0);  // Принудительно перерисовываем график
       }
    }
    else
    {
       msg = "СМЕНА ТРЕНДА ⬇️ - " + symbolName + " (" + tf + ")";
       Print("Готовимся отправить сообщение о смене тренда вниз: ", msg);
       
       // Определяем, использовать ли резервный канал на основе таймфрейма
       bool useReserveChannel = (Period() == PERIOD_H1 || Period() == PERIOD_H4 || Period() == PERIOD_D1);
       
       // Отправляем сообщение только если таймфрейм в списке разрешенных
       if(sendToTelegram)
          SendTelegramMessage(msg, true, false, useReserveChannel);
       else
          Print(tf + " timeframe: Telegram notification skipped for trend change");
       
       // Создание текстового объекта "CT" для смены тренда вниз
       string objName = "TrendDownChange_" + TimeToString(currentBarTime, TIME_DATE|TIME_SECONDS);
       if(!ObjectCreate(0, objName, OBJ_TEXT, 0, currentBarTime, arrowPrice))
          Print("Ошибка создания текстового объекта смены тренда: ", GetLastError());
       else
       {
          // Устанавливаем свойства для текстового объекта
          ObjectSetString(0, objName, OBJPROP_TEXT, "CT"); // Текст "CT" (английские буквы)
          ObjectSetInteger(0, objName, OBJPROP_COLOR, clrRed);
          ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 12); // Увеличенный размер шрифта
          ObjectSetInteger(0, objName, OBJPROP_BACK, false);   // Не на заднем плане
          ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false); // Не выбираемая
          ObjectSetInteger(0, objName, OBJPROP_HIDDEN, false);   // Не скрыта в списке объектов
          ObjectSetInteger(0, objName, OBJPROP_ZORDER, 200);     // Высокий приоритет для отображения поверх других элементов
          ChartRedraw(0);  // Принудительно перерисовываем график
       }
    }
    lastTrendChangeAlertTime = currentBarTime;
}

//+------------------------------------------------------------------+
//| Функция отправки сообщений о барах близкого закрытия в Telegram и |
//| рисования специальных индикаторов на графике                     |
//+------------------------------------------------------------------+
void SendCloseClosingBarAlert(bool bullish, datetime currentBarTime, double arrowPrice)
{
    // Если сообщение для данного бара уже отправлено, выходим
    if(currentBarTime == lastCloseClosingBarAlertTime)
       return;
    
    string symbolName = _Symbol;
    string tf = GetTimeFrameString();
    string msg;
    
    // Проверяем, есть ли текущий таймфрейм в массиве для моделей баров близкого закрытия
    bool sendToTelegram = IsTimeframeInArray(Period(), CloseClosingBarTimeframes);
    
    if(bullish)
    {
       msg = "БАР БЛИЗКОГО ЗАКРЫТИЯ 🟢 - " + symbolName + " (" + tf + ")";
       Print("Готовимся отправить сообщение о баре близкого закрытия (бычий): ", msg);
       
       // Отправляем сообщение только если таймфрейм в списке разрешенных
       if(sendToTelegram)
          SendTelegramMessage(msg, false, true); // Отправляем в канал для баров близкого закрытия
       else
          Print(tf + " timeframe: Telegram notification skipped for close closing bar");
       
       // Создание текстового объекта "ББЗ" для бара близкого закрытия (бычий)
       string objName = "BullishCloseClosingBar_" + TimeToString(currentBarTime, TIME_DATE|TIME_SECONDS);
       if(!ObjectCreate(0, objName, OBJ_TEXT, 0, currentBarTime, arrowPrice))
          Print("Ошибка создания текстового объекта бара близкого закрытия: ", GetLastError());
       else
       {
          // Устанавливаем свойства для текстового объекта
          ObjectSetString(0, objName, OBJPROP_TEXT, "ББЗ"); // Текст "ББЗ" (русские буквы)
          ObjectSetInteger(0, objName, OBJPROP_COLOR, clrLime);
          ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 12); // Увеличенный размер шрифта
          ObjectSetInteger(0, objName, OBJPROP_BACK, false);   // Не на заднем плане
          ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false); // Не выбираемая
          ObjectSetInteger(0, objName, OBJPROP_HIDDEN, false);   // Не скрыта в списке объектов
          ObjectSetInteger(0, objName, OBJPROP_ZORDER, 150);     // Приоритет для отображения
          ChartRedraw(0);  // Принудительно перерисовываем график
       }
    }
    else
    {
       msg = "БАР БЛИЗКОГО ЗАКРЫТИЯ 🔴 - " + symbolName + " (" + tf + ")";
       Print("Готовимся отправить сообщение о баре близкого закрытия (медвежий): ", msg);
       
       // Отправляем сообщение только если таймфрейм в списке разрешенных
       if(sendToTelegram)
          SendTelegramMessage(msg, false, true); // Отправляем в канал для баров близкого закрытия
       else
          Print(tf + " timeframe: Telegram notification skipped for close closing bar");
       
       // Создание текстового объекта "ББЗ" для бара близкого закрытия (медвежий)
       string objName = "BearishCloseClosingBar_" + TimeToString(currentBarTime, TIME_DATE|TIME_SECONDS);
       if(!ObjectCreate(0, objName, OBJ_TEXT, 0, currentBarTime, arrowPrice))
          Print("Ошибка создания текстового объекта бара близкого закрытия: ", GetLastError());
       else
       {
          // Устанавливаем свойства для текстового объекта
          ObjectSetString(0, objName, OBJPROP_TEXT, "ББЗ"); // Текст "ББЗ" (русские буквы)
          ObjectSetInteger(0, objName, OBJPROP_COLOR, clrRed);
          ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 12); // Увеличенный размер шрифта
          ObjectSetInteger(0, objName, OBJPROP_BACK, false);   // Не на заднем плане
          ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false); // Не выбираемая
          ObjectSetInteger(0, objName, OBJPROP_HIDDEN, false);   // Не скрыта в списке объектов
          ObjectSetInteger(0, objName, OBJPROP_ZORDER, 150);     // Приоритет для отображения
          ChartRedraw(0);  // Принудительно перерисовываем график
       }
    }
    lastCloseClosingBarAlertTime = currentBarTime;
}

// Функция SendWeeklyHighLowAlert удалена, так как функциональность отключена

#endif // __TELEGRAMHELPER_MQH__
