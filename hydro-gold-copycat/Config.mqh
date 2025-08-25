//+------------------------------------------------------------------+
//|                                               HydroGoldCopycat |
//|                        Copyright 2025, Pablo Nachos |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Pablo Nachos"
#property link      ""
#property version   "1.00"

//--- EA settings
#define MAGIC_NUMBER 1234567

//--- Strategy Parameters
input int InpSmaFilterPeriod = 20;      // Period for the trend-filtering SMA
input int InpExtremumHours = 1;         // Hours to look back/forward for a significant extremum
input int InpMaxDistancePoints = 100;  // Max distance from breakout level to open a trade
input int InpTradingStartTime = 0;     // Trading session start hour (0-23)
input int InpTradingEndTime = 23;      // Trading session end hour (0-23)

//--- Trading settings
input double InpLotSize = 0.11;           // Initial Lot Size
input int InpSlippage = 3;              // Slippage in points
input int InpStopLossPoints = 2000;     // Stop Loss in points
input int InpTakeProfitPoints = 500;    // Take Profit in points

//--- Strategy Modifiers
input double InpLotMultiplier = 1.0;      // Multiplier for next lot after a loss
input bool InpExitOnReverse = true;       // Close trade on reverse signal
input bool InpAllowMultipleTrades = false; // Allow multiple trades to be open
