# HydroGoldCopycat EA Strategy

**Note: This document must be kept under 1000 characters.**

This EA trades XAUUSD on M5 using a configurable breakout strategy.

### Core Entry Logic:
1.  **Trading Session Filter:** Trades are only opened within specified hours (`InpTradingStartTime` to `InpTradingEndTime`). Any open trades are forcibly closed when outside this range.
2.  **Significant Extremum:** Identifies a pivot high/low respected by the market for a set period (e.g., 1 hour) on both sides.
3.  **First Breakout Filter:** Ensures a trade is only triggered on the first break of the identified extremum level since its formation.
4.  **Proximity Filter:** A trade is only opened if the price is within a max distance (in points) of the level being broken.
5.  **Trend Filter:** A 20-period SMA on the M5 chart is used as a final trend confirmation.

### Configurable Parameters:
*   `InpLotMultiplier`: Multiplies lot size after a loss. Default: 1.0.
*   `InpExtremumHours`: Hours to check for a significant extremum. Default: 1.
*   `InpMaxDistancePoints`: Max distance from breakout to enter. Default: 100.
*   `InpTradingStartTime`: Trading session start hour (0-23). Default: 0.
*   `InpTradingEndTime`: Trading session end hour (0-23). Default: 23.
*   `InpExitOnReverse`: Close trades on a reverse signal. Default: `true`.
*   `InpAllowMultipleTrades`: Allow hedging. Default: `false`.

*Version: 1.7*