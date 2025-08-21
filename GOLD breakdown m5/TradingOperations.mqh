//+------------------------------------------------------------------+
//| TradingOperations.mqh                                            |
//| Модуль торговых операций для GOLD Breakdown M5                  |
//| Содержит логику открытия и закрытия позиций                     |
//+------------------------------------------------------------------+

#property strict
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Класс торговых операций                                          |
//+------------------------------------------------------------------+
class CTradingOperations
{
private:
   string            m_symbol;              // Торговый символ
   int               m_magicNumber;         // Магический номер
   bool              m_debugMode;           // Режим отладки
   CTrade*           m_trade;               // Указатель на объект торговли
   
public:
   // Конструктор
   CTradingOperations(string symbol, int magicNumber, CTrade* tradeObject, bool debugMode = false);
   
   // Основные торговые операции
   bool              StartBuySequence(double lotSize, double pointValue, int stopLossPoints, int takeProfitPoints, ulong &lastTicket);
   bool              StartSellSequence(double lotSize, double pointValue, int stopLossPoints, int takeProfitPoints, ulong &lastTicket);
   bool              OpenNextTradeInSequence(bool isInBuySequence, double lotSize, double pointValue, 
                                           int recoveryStopLossPoints, int recoveryTakeProfitPoints, 
                                           ulong &lastTicket, bool &waitingForHourlyBreakout);
   bool              OpenOppositePosition(bool &isInBuySequence, bool &isInSellSequence, double lotSize, 
                                        double pointValue, int recoveryStopLossPoints, int recoveryTakeProfitPoints, 
                                        ulong &lastTicket);
   void              CloseAllPositions();
   
   // Вспомогательные функции
   double            CalculateLotSize(double baseLotSize, double multiplier, int sequence);
};

//+------------------------------------------------------------------+
//| Конструктор класса                                               |
//+------------------------------------------------------------------+
CTradingOperations::CTradingOperations(string symbol, int magicNumber, CTrade* tradeObject, bool debugMode = false)
{
   m_symbol = symbol;
   m_magicNumber = magicNumber;
   m_trade = tradeObject;
   m_debugMode = debugMode;
}

//+------------------------------------------------------------------+
//| Функция начала последовательности покупок                        |
//+------------------------------------------------------------------+
bool CTradingOperations::StartBuySequence(double lotSize, double pointValue, int stopLossPoints, int takeProfitPoints, ulong &lastTicket)
{
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   double stopLoss = ask - (stopLossPoints * pointValue);
   double takeProfit = ask + (takeProfitPoints * pointValue);
   
   if(m_debugMode)
   {
      Print("DEBUG: Начинаем последовательность покупок. Лот: ", lotSize, ", SL: ", stopLoss, ", TP: ", takeProfit);
   }
   
   if(m_trade.Buy(lotSize, m_symbol, 0, stopLoss, takeProfit))
   {
      lastTicket = m_trade.ResultOrder();
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Функция начала последовательности продаж                         |
//+------------------------------------------------------------------+
bool CTradingOperations::StartSellSequence(double lotSize, double pointValue, int stopLossPoints, int takeProfitPoints, ulong &lastTicket)
{
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double stopLoss = bid + (stopLossPoints * pointValue);
   double takeProfit = bid - (takeProfitPoints * pointValue);
   
   if(m_debugMode)
   {
      Print("DEBUG: Начинаем последовательность продаж. Лот: ", lotSize, ", SL: ", stopLoss, ", TP: ", takeProfit);
   }
   
   if(m_trade.Sell(lotSize, m_symbol, 0, stopLoss, takeProfit))
   {
      lastTicket = m_trade.ResultOrder();
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Функция открытия следующей сделки в последовательности           |
//+------------------------------------------------------------------+
bool CTradingOperations::OpenNextTradeInSequence(bool isInBuySequence, double lotSize, double pointValue, 
                                                int recoveryStopLossPoints, int recoveryTakeProfitPoints, 
                                                ulong &lastTicket, bool &waitingForHourlyBreakout)
{
   if(isInBuySequence)
   {
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double stopLoss = ask - (recoveryStopLossPoints * pointValue);
      double takeProfit = ask + (recoveryTakeProfitPoints * pointValue);
      
      if(m_debugMode)
      {
         Print("DEBUG: Открываем следующую покупку в последовательности. Лот: ", lotSize);
      }
      
      if(m_trade.Buy(lotSize, m_symbol, 0, stopLoss, takeProfit))
      {
         lastTicket = m_trade.ResultOrder();
         return true;
      }
      else
      {
         // Если не удалось открыть сделку, сбрасываем ожидание
         waitingForHourlyBreakout = false;
         return false;
      }
   }
   else // isInSellSequence
   {
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double stopLoss = bid + (recoveryStopLossPoints * pointValue);
      double takeProfit = bid - (recoveryTakeProfitPoints * pointValue);
      
      if(m_debugMode)
      {
         Print("DEBUG: Открываем следующую продажу в последовательности. Лот: ", lotSize);
      }
      
      if(m_trade.Sell(lotSize, m_symbol, 0, stopLoss, takeProfit))
      {
         lastTicket = m_trade.ResultOrder();
         return true;
      }
      else
      {
         // Если не удалось открыть сделку, сбрасываем ожидание
         waitingForHourlyBreakout = false;
         return false;
      }
   }
}

//+------------------------------------------------------------------+
//| Функция открытия противоположной позиции после убытка            |
//+------------------------------------------------------------------+
bool CTradingOperations::OpenOppositePosition(bool &isInBuySequence, bool &isInSellSequence, double lotSize, 
                                             double pointValue, int recoveryStopLossPoints, int recoveryTakeProfitPoints, 
                                             ulong &lastTicket)
{
   if(isInBuySequence)
   {
      // Переключаемся на продажи
      isInBuySequence = false;
      isInSellSequence = true;
      
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double stopLoss = bid + (recoveryStopLossPoints * pointValue);
      double takeProfit = bid - (recoveryTakeProfitPoints * pointValue);
      
      if(m_debugMode)
      {
         Print("DEBUG: Открываем противоположную позицию (продажа). Лот: ", lotSize);
      }
      
      if(m_trade.Sell(lotSize, m_symbol, 0, stopLoss, takeProfit))
      {
         lastTicket = m_trade.ResultOrder();
         return true;
      }
   }
   else if(isInSellSequence)
   {
      // Переключаемся на покупки
      isInSellSequence = false;
      isInBuySequence = true;
      
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double stopLoss = ask - (recoveryStopLossPoints * pointValue);
      double takeProfit = ask + (recoveryTakeProfitPoints * pointValue);
      
      if(m_debugMode)
      {
         Print("DEBUG: Открываем противоположную позицию (покупка). Лот: ", lotSize);
      }
      
      if(m_trade.Buy(lotSize, m_symbol, 0, stopLoss, takeProfit))
      {
         lastTicket = m_trade.ResultOrder();
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Функция закрытия всех позиций                                    |
//+------------------------------------------------------------------+
void CTradingOperations::CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
         PositionGetInteger(POSITION_MAGIC) == m_magicNumber)
      {
         m_trade.PositionClose(ticket);
         
         if(m_debugMode)
         {
            Print("DEBUG: Закрыта позиция #", ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Функция расчета размера лота с учетом множителя                  |
//+------------------------------------------------------------------+
double CTradingOperations::CalculateLotSize(double baseLotSize, double multiplier, int sequence)
{
   double lotSize = baseLotSize * MathPow(multiplier, sequence - 1);
   
   // Ограничиваем максимальный размер лота
   double maxLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
   if(lotSize > maxLot) lotSize = maxLot;
   
   // Округляем до шага изменения размера лота
   double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   return lotSize;
}