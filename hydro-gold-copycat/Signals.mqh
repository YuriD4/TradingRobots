//+------------------------------------------------------------------+
//|                                               HydroGoldCopycat |
//|                        Copyright 2025, Pablo Nachos |
//|                                                                  |
//+------------------------------------------------------------------+
#include "Config.mqh"

//+------------------------------------------------------------------+
//| Checks if a bar is a significant high.                           |
//+------------------------------------------------------------------+
bool IsSignificantHigh(int bar_index, int period, const double &highs[])
  {
   // Ensure we have enough data around the bar
   if(bar_index < period || bar_index >= ArraySize(highs) - period)
      return false;

   double pivot_high = highs[bar_index];

   for(int i = 1; i <= period; i++)
     {
      if(highs[bar_index - i] > pivot_high || highs[bar_index + i] > pivot_high)
         return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Checks if a bar is a significant low.                            |
//+------------------------------------------------------------------+
bool IsSignificantLow(int bar_index, int period, const double &lows[])
  {
   // Ensure we have enough data around the bar
   if(bar_index < period || bar_index >= ArraySize(lows) - period)
      return false;

   double pivot_low = lows[bar_index];

   for(int i = 1; i <= period; i++)
     {
      if(lows[bar_index - i] < pivot_low || lows[bar_index + i] < pivot_low)
         return false;
     }

   return true;
  }


//+------------------------------------------------------------------+
//| Checks for a trading signal based on the breakout strategy.      |
//| Returns 1 for buy, -1 for sell, 0 for no signal.               |
//+------------------------------------------------------------------+
int CheckSignal()
  {
   ENUM_TIMEFRAMES timeframe = PERIOD_M5;
   string symbol = _Symbol;
   int extremum_period_bars = InpExtremumHours * 12; // 12 bars on M5 = 1 hour

//--- Get enough history for our checks (e.g., 3x the period)
   int history_to_load = extremum_period_bars * 3;
   if(history_to_load < 50) history_to_load = 50; // Minimum history
   
   double high[], low[], close[];
   if(CopyHigh(symbol, timeframe, 0, history_to_load, high) < history_to_load ||
      CopyLow(symbol, timeframe, 0, history_to_load, low) < history_to_load ||
      CopyClose(symbol, timeframe, 0, 2, close) < 2)
     {
      Print("Error copying history data");
      return 0;
     }
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

//--- Get the SMA filter value
   double sma_buffer[];
   if(CopyBuffer(iMA(symbol, timeframe, InpSmaFilterPeriod, 0, MODE_SMA, PRICE_CLOSE), 0, 0, 1, sma_buffer) < 1)
     {
      Print("Error copying SMA data");
      return 0;
     }
   double sma_value = sma_buffer[0];

   double current_price = close[0];

//--- Buy Signal Logic
   if(current_price > sma_value)
     {
      // Find the most recent significant high to break
      for(int i = extremum_period_bars; i < history_to_load - extremum_period_bars; i++)
        {
         if(IsSignificantHigh(i, extremum_period_bars, high))
           {
            double breakout_level = high[i];
            bool is_first_break = true;
            // Check if the level has been broken since it was formed
            for(int j = i - 1; j > 0; j--)
              {
               if(high[j] > breakout_level)
                 {
                  is_first_break = false;
                  break;
                 }
              }

            if(is_first_break)
              {
               // Check for breakout and proximity
               if(current_price > breakout_level && (current_price - breakout_level) <= InpMaxDistancePoints * _Point)
                 {
                  return 1; // Buy signal
                 }
              }
            break; // We only care about the most recent significant level
           }
        }
     }

//--- Sell Signal Logic
   if(current_price < sma_value)
     {
      // Find the most recent significant low to break
      for(int i = extremum_period_bars; i < history_to_load - extremum_period_bars; i++)
        {
         if(IsSignificantLow(i, extremum_period_bars, low))
           {
            double breakout_level = low[i];
            bool is_first_break = true;
            // Check if the level has been broken since it was formed
            for(int j = i - 1; j > 0; j--)
              {
               if(low[j] < breakout_level)
                 {
                  is_first_break = false;
                  break;
                 }
              }

            if(is_first_break)
              {
               // Check for breakout and proximity
               if(current_price < breakout_level && (breakout_level - current_price) <= InpMaxDistancePoints * _Point)
                 {
                  return -1; // Sell signal
                 }
              }
            break; // We only care about the most recent significant level
           }
        }
     }

   return 0; // No signal
  }
