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

   //--- 1. Handle Forced Exit (if outside trading hours)
   MqlDateTime current_time;
   TimeCurrent(current_time);
   if(current_time.hour < InpTradingStartTime || current_time.hour > InpTradingEndTime)
     {
      if(open_trades > 0)
        {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
           {
            if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER)
              {
               Print("Outside trading hours. Closing position #", PositionGetTicket(i));
               trade.PositionClose(PositionGetTicket(i), InpSlippage);
              }
           }
        }
      return; // Do not proceed with other logic outside trading hours
     }

   //--- 2. Handle Exit Logic (SMA Crossover)
   if(open_trades > 0)
     {
      // Get M5 close price and SMA value for the last completed bar
      double m5_close_array[1];
      double m5_sma_array[1];
      if(CopyClose(_Symbol, PERIOD_M5, 1, 1, m5_close_array) < 1 ||
         CopyBuffer(iMA(_Symbol, PERIOD_M5, InpSmaFilterPeriod, 0, MODE_SMA, PRICE_CLOSE), 0, 1, 1, m5_sma_array) < 1)
        {
         Print("Error copying M5 data for SMA exit.");
         return;
        }
      double m5_close = m5_close_array[0];
      double m5_sma = m5_sma_array[0];

      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER)
           {
            long type = PositionGetInteger(POSITION_TYPE);
            bool close_condition_met = false;

            // For Buy positions, close if M5 candle closes below SMA
            if(type == POSITION_TYPE_BUY && m5_close < m5_sma)
              {
               close_condition_met = true;
              }
            // For Sell positions, close if M5 candle closes above SMA
            else if(type == POSITION_TYPE_SELL && m5_close > m5_sma)
              {
               close_condition_met = true;
              }

            if(close_condition_met)
              {
               Print("M5 candle closed against SMA. Closing position #", PositionGetTicket(i));
               trade.PositionClose(PositionGetTicket(i), InpSlippage);
               return; // Exit after closing to re-evaluate on next tick
              }
           }
        }
     }

   //--- 3. Handle Exit Logic (Reverse Signal - if enabled)
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

   //--- 4. Handle Entry Logic
   if(signal != 0)
     {
      //--- Time Filter for Entry
      if(current_time.hour < InpTradingStartTime || current_time.hour > InpTradingEndTime)
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