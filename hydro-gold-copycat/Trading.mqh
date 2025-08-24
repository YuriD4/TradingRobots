//+------------------------------------------------------------------+
//|                                               HydroGoldCopycat |
//|                        Copyright 2025, Pablo Nachos |
//|                                                                  |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#include "Config.mqh"

CTrade trade;

//+------------------------------------------------------------------+
//| Count current open trades                                        |
//+------------------------------------------------------------------+
int CountOpenTrades()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER)
        {
         count++;
        }
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Open a new trade                                                 |
//+------------------------------------------------------------------+
void OpenTrade(int signal, double lot_size)
  {
   trade.SetExpertMagicNumber(MAGIC_NUMBER);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   double sl_price, tp_price;
   double point = _Point;

   if(signal == 1) // Buy Signal
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl_price = ask - InpStopLossPoints * point;
      tp_price = ask + InpTakeProfitPoints * point;
      trade.Buy(lot_size, _Symbol, ask, sl_price, tp_price, "Buy Signal");
     }
   else if(signal == -1) // Sell Signal
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl_price = bid + InpStopLossPoints * point;
      tp_price = bid - InpTakeProfitPoints * point;
      trade.Sell(lot_size, _Symbol, bid, sl_price, tp_price, "Sell Signal");
     }
  }

