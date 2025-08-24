//+------------------------------------------------------------------+
//|                                               HydroGoldCopycat |
//|                        Copyright 2025, Pablo Nachos |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Pablo Nachos"
#property link      ""
#property version   "1.3"
#property description "A flexible breakout strategy robot."

#include "Config.mqh"
#include "Signals.mqh"
#include "Trading.mqh"

//--- Global variable for lot size management
double g_current_lot_size;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("HydroGoldCopycat EA Initialized.");
   Print("Magic Number: ", MAGIC_NUMBER);
   Print("Initial Lot Size: ", InpLotSize);
   Print("Lot Multiplier: ", InpLotMultiplier);
   Print("Extremum Hours: ", InpExtremumHours);
   Print("Exit on Reverse: ", InpExitOnReverse);
   Print("Allow Multiple Trades: ", InpAllowMultipleTrades);

   //--- Initialize the lot size
   g_current_lot_size = InpLotSize;
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("HydroGoldCopycat EA Deinitialized. Reason: ", reason);
  }



//+------------------------------------------------------------------+
//| A helper function to get the profit of the last closed trade.    |
//+------------------------------------------------------------------+
double GetLastProfit()
  {
   HistorySelect(0, TimeCurrent());
   int deals = HistoryDealsTotal();
   for(int i = deals - 1; i >= 0; i--)
     {
      long ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == MAGIC_NUMBER)
        {
         // Found the last deal, return its profit.
         return HistoryDealGetDouble(ticket, DEAL_PROFIT);
        }
     }
   return 0.0; // No trades in history
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   static datetime last_check_time = 0;
   datetime current_bar_time = (datetime)SeriesInfoInteger(_Symbol, PERIOD_M1, SERIES_LASTBAR_DATE);

   if(current_bar_time <= last_check_time)
      return; // Not a new bar yet

   last_check_time = current_bar_time;
   int signal = CheckSignal();
   int open_trades = CountOpenTrades();

   //--- 1. Handle Exit Logic
   if(open_trades > 0 && InpExitOnReverse)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER)
           {
            long type = PositionGetInteger(POSITION_TYPE);
            if((type == POSITION_TYPE_BUY && signal == -1) || (type == POSITION_TYPE_SELL && signal == 1))
              {
               Print("Reverse signal found. Closing position #", PositionGetTicket(i));
               trade.PositionClose(PositionGetTicket(i), InpSlippage);
               return; // Exit after closing to re-evaluate on next tick
              }
           }
        }
     }

   //--- 2. Handle Entry Logic
   if(signal != 0)
     {
      //--- Time Filter
      MqlDateTime current_time;
      TimeCurrent(current_time);
      if(current_time.hour < 1)
         return; // Trading is forbidden at this hour

      bool can_open_new_trade = false;
      if(open_trades == 0)
        {
         can_open_new_trade = true;
         //--- Lot multiplier logic
         double last_profit = GetLastProfit();
         if(last_profit < 0)
           {
            g_current_lot_size = NormalizeDouble(g_current_lot_size * InpLotMultiplier, 2);
           }
         else
           {
            g_current_lot_size = InpLotSize;
           }
        }
      else if(InpAllowMultipleTrades)
        {
         can_open_new_trade = true;
        }

      if(can_open_new_trade)
        {
         Print("Signal found: ", signal, ". Opening trade with lot ", g_current_lot_size);
         OpenTrade(signal, g_current_lot_size);
        }
     }
  }
//+------------------------------------------------------------------+