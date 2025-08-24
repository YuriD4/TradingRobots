//+------------------------------------------------------------------+
//|                                               HydroGoldCopycat |
//|                        Copyright 2025, Pablo Nachos |
//|                                                                  |
//+------------------------------------------------------------------+
#include "Config.mqh"

//+------------------------------------------------------------------+
//| Get the profit of the last closed trade for this EA.             |
//| Returns 0.0 if no trade history or on error.                     |
//+------------------------------------------------------------------+
double GetLastTradeProfit()
  {
   if(HistorySelect(0, TimeCurrent()))
     {
      uint total_deals = HistoryDealsTotal();
      for(uint i = total_deals - 1; i >= 0; i--)
        {
         long deal_ticket = HistoryDealGetTicket(i);
         if(deal_ticket > 0)
           {
            if(HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) == MAGIC_NUMBER)
              {
               //--- We found the last deal for our EA
               return HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
              }
           }
        }
     }
   else
     {
      Print("Error selecting history!");
     }

   return 0.0; // No history found for this magic number
  }
