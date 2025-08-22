# Trend Change Trading Robot

## Overview

Trend Change is a trading robot for MetaTrader 5 that identifies trend change patterns based on engulfing candlestick patterns and executes trades accordingly. The robot is designed to work on any timeframe and trading pair.

## How It Works

### Trend Change Model

The robot identifies trend changes based on the following pattern:

1. **Engulfing Pattern Detection**: The robot detects various types of engulfing patterns:
   - Classic (2-candle) engulfing patterns
   - Extended (3-candle) engulfing patterns
   - Extended (4-candle) engulfing patterns

2. **Trend Change Conditions**: A trend change is confirmed when:
   - A sequence of opposite engulfing patterns is detected
   - Maximum 15 bars between the patterns
   - Price breaks through key levels
   - The pattern's extreme is the day's extreme
   - The pattern's extreme is also the 12-hour extreme (additional filter)

3. **Trading Rules**:
   - Fixed lot size of 0.01
   - Entry on trend change signals
   - Distance filter: trade only if current price is within a specified distance from the day's high/low
   - Dynamic stop-loss calculation:
     - For buy trades: stop-loss is set at day's low minus 2 points
     - For sell trades: stop-loss is set at day's high plus 2 points
   - Take-profit is calculated as a multiple of the stop-loss distance
   - Optional trailing stop

### File Structure

- `TrendChange.mq5` - Main robot file
- `TrendChangeConfig.mqh` - Configuration parameters
- `TrendChangeUtils.mqh` - Utility functions
- `EngulfingPatternDetector.mqh` - Engulfing pattern detection logic
- `TrendChangeDetector.mqh` - Trend change detection logic
- `TradingOperations.mqh` - Trading operations functions

## Configuration Parameters

The robot can be configured through the following input parameters in MetaTrader 5:

- `InpMagicNumber` - Unique identifier for the robot's trades (default: 123456)
- `InpLotSize` - Base lot size for trades (default: 0.01)
- `InpTakeProfitMultiplier` - Multiplier for take-profit relative to stop-loss (default: 2.0)
- `InpMaxDistanceToDayLow` - Maximum distance to day's low in points for buy trades (default: 20)
- `InpMaxDistanceToDayHigh` - Maximum distance to day's high in points for sell trades (default: 20)
- `InpUseTrailingStop` - Enable trailing stop (default: true)
- `InpCloseOnOppositeSignal` - Close positions on opposite signals (default: true)
- `InpTradingStartHour` - Start of trading hours (default: 0)
- `InpTradingEndHour` - End of trading hours (default: 23)
- `InpUseDailyMartingale` - Enable daily martingale system (default: true)
- `InpMartingaleMultiplier` - Lot size multiplier after losing trades (default: 2.0)
- `InpDebugMode` - Enable debug logging (default: true)

## Point Calculation

The robot correctly calculates points for different types of trading pairs:
- For regular pairs: 1 point = 0.0001 (4th decimal place)
- For JPY pairs: 1 point = 0.01 (3rd decimal place)

## Installation

1. Copy all files to the `MQL5/Experts/Trend Change/` folder in your MetaTrader 5 terminal
2. Restart MetaTrader 5 or refresh the expert list
3. Drag the robot onto the chart of your choice
4. Configure parameters if needed
5. Enable "Allow Algo Trading" in the terminal

## Usage

1. Select a trading instrument and timeframe
2. Apply the robot to the chart
3. The robot will automatically:
   - Detect engulfing patterns
   - Identify trend change signals
   - Open positions based on signals
   - Manage open positions with stop-loss, take-profit, and trailing stop
   - Close positions at the end of trading day (23:00) or on opposite signals

## Risk Management

- Always use appropriate stop-loss levels
- Test the robot on a demo account before using real money
- Monitor the robot's performance regularly
- Adjust parameters based on market conditions and your risk tolerance

## Daily Martingale System

The robot includes an optional daily martingale system with the following features:

- **Lot Size Multiplication**: After a losing or breakeven trade, the next trade uses a multiplied lot size
- **Daily Reset**: Martingale counters reset to base values at the start of each trading day
- **Breakeven Trigger**: Moving stop-loss to breakeven also triggers martingale for the next trade
- **Winning Reset**: After a profitable trade, lot size returns to the base value
- **Configurable Multiplier**: The multiplication factor can be adjusted via `InpMartingaleMultiplier`

**Important**: Use martingale carefully as it increases risk. Test thoroughly on demo accounts.

## Limitations

- The robot is designed for trend change trading only
- Performance may vary in different market conditions
- Not suitable for ranging markets
- Requires sufficient liquidity for proper execution

## Support

For questions or issues, please refer to the code comments or contact the developer.

## Disclaimer

This trading robot is provided for educational purposes. Trading in financial markets involves a substantial risk of loss. Use at your own risk.