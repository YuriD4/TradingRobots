//+------------------------------------------------------------------+
//|                                            TradingOperations.mqh |
//|                                    Copyright 2023, TradingRobots |
//|                                             https://www.example.com |
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
   bool              Buy(double lotSize, string symbol, double stopLoss = 0, double takeProfit = 0);
   bool              Sell(double lotSize, string symbol, double stopLoss = 0, double takeProfit = 0);
   bool              ClosePosition(ulong ticket);
   void              CloseAllPositions();
   bool              ModifyStopLoss(ulong ticket, double stopLoss);
   
   // Вспомогательные функции
   bool              IsPositionExists(ulong ticket);
   double            GetPositionOpenPrice(ulong ticket);
   double            GetPositionStopLoss(ulong ticket);
   double            GetPositionTakeProfit(ulong ticket);
   ENUM_POSITION_TYPE GetPositionType(ulong ticket);
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
//| Функция открытия позиции на покупку                              |
//+------------------------------------------------------------------+
bool CTradingOperations::Buy(double lotSize, string symbol, double stopLoss = 0, double takeProfit = 0)
{
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   
   
   if(m_trade.Buy(lotSize, symbol, 0, stopLoss, takeProfit))
   {
      ulong ticket = m_trade.ResultOrder();
      
      if(m_debugMode)
      {
         Print("DEBUG: BUY position opened successfully. Ticket: ", ticket);
      }
      
      return true;
   }
   else
   {
      if(m_debugMode)
      {
         Print("DEBUG: Failed to open BUY position. Error: ", GetLastError());
      }
      
      return false;
   }
}

//+------------------------------------------------------------------+
//| Функция открытия позиции на продажу                              |
//+------------------------------------------------------------------+
bool CTradingOperations::Sell(double lotSize, string symbol, double stopLoss = 0, double takeProfit = 0)
{
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   
   if(m_debugMode)
   {
      Print("DEBUG: Opening SELL position. Lot: ", lotSize, ", Symbol: ", symbol, 
            ", Bid: ", bid, ", SL: ", stopLoss, ", TP: ", takeProfit);
   }
   
   if(m_trade.Sell(lotSize, symbol, 0, stopLoss, takeProfit))
   {
      ulong ticket = m_trade.ResultOrder();
      
      if(m_debugMode)
      {
         Print("DEBUG: SELL position opened successfully. Ticket: ", ticket);
      }
      
      return true;
   }
   else
   {
      if(m_debugMode)
      {
         Print("DEBUG: Failed to open SELL position. Error: ", GetLastError());
      }
      
      return false;
   }
}

//+------------------------------------------------------------------+
//| Функция закрытия позиции по тикету                              |
//+------------------------------------------------------------------+
bool CTradingOperations::ClosePosition(ulong ticket)
{
   if(!IsPositionExists(ticket))
   {
      if(m_debugMode)
      {
         Print("DEBUG: Position #", ticket, " does not exist");
      }
      return false;
   }
   
   if(m_debugMode)
   {
      Print("DEBUG: Closing position #", ticket);
   }
   
   if(m_trade.PositionClose(ticket))
   {
      if(m_debugMode)
      {
         Print("DEBUG: Position #", ticket, " closed successfully");
      }
      return true;
   }
   else
   {
      if(m_debugMode)
      {
         Print("DEBUG: Failed to close position #", ticket, ". Error: ", GetLastError());
      }
      return false;
   }
}

//+------------------------------------------------------------------+
//| Функция закрытия всех позиций                                    |
//+------------------------------------------------------------------+
void CTradingOperations::CloseAllPositions()
{
   int count = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
         PositionGetInteger(POSITION_MAGIC) == m_magicNumber)
      {
         if(ClosePosition(ticket))
         {
            count++;
         }
      }
   }
   
   if(m_debugMode)
   {
      Print("DEBUG: Closed ", count, " positions");
   }
}

//+------------------------------------------------------------------+
//| Функция модификации стоп-лосса позиции                           |
//+------------------------------------------------------------------+
bool CTradingOperations::ModifyStopLoss(ulong ticket, double stopLoss)
{
   if(!IsPositionExists(ticket))
   {
      if(m_debugMode)
      {
         Print("DEBUG: Position #", ticket, " does not exist");
      }
      return false;
   }
   
   double currentStopLoss = GetPositionStopLoss(ticket);
   if(currentStopLoss == stopLoss)
   {
      // Стоп-лосс уже установлен на нужном уровне
      return true;
   }
   
   if(m_debugMode)
   {
      Print("DEBUG: Modifying stop loss for position #", ticket, 
            ". Current SL: ", currentStopLoss, ", New SL: ", stopLoss);
   }
   
   if(m_trade.PositionModify(ticket, stopLoss, GetPositionTakeProfit(ticket)))
   {
      if(m_debugMode)
      {
         Print("DEBUG: Stop loss modified successfully for position #", ticket);
      }
      return true;
   }
   else
   {
      return false;
   }
}

//+------------------------------------------------------------------+
//| Функция проверки существования позиции                            |
//+------------------------------------------------------------------+
bool CTradingOperations::IsPositionExists(ulong ticket)
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong posTicket = PositionGetTicket(i);
      if(posTicket == ticket)
      {
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Функция получения цены открытия позиции                           |
//+------------------------------------------------------------------+
double CTradingOperations::GetPositionOpenPrice(ulong ticket)
{
   if(!IsPositionExists(ticket))
      return 0;
   
   return PositionGetDouble(POSITION_PRICE_OPEN);
}

//+------------------------------------------------------------------+
//| Функция получения стоп-лосса позиции                             |
//+------------------------------------------------------------------+
double CTradingOperations::GetPositionStopLoss(ulong ticket)
{
   if(!IsPositionExists(ticket))
      return 0;
   
   return PositionGetDouble(POSITION_SL);
}

//+------------------------------------------------------------------+
//| Функция получения тейк-профита позиции                           |
//+------------------------------------------------------------------+
double CTradingOperations::GetPositionTakeProfit(ulong ticket)
{
   if(!IsPositionExists(ticket))
      return 0;
   
   return PositionGetDouble(POSITION_TP);
}

//+------------------------------------------------------------------+
//| Функция получения типа позиции                                   |
//+------------------------------------------------------------------+
ENUM_POSITION_TYPE CTradingOperations::GetPositionType(ulong ticket)
{
   if(!IsPositionExists(ticket))
      return WRONG_VALUE;
   
   return (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
}
//+------------------------------------------------------------------+