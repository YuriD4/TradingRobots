# Trend Change Simple Trading Robot

## Overview

Trend Change Simple is a simplified version of the Trend Change trading robot for MetaTrader 5. This robot uses a false breakout strategy based on the previous day's price range (16:00 to 00:00) to identify trading opportunities.

## How It Works

### Basic Trading Logic

1. **Range Detection**: The robot identifies the price range from the previous day between 16:00 and 00:00 (server time)
2. **False Breakout Detection**: The robot waits for price to break out of this range by a configurable number of points
3. **Return Signal**: When price returns back into the range (1 point above the lower boundary for buy signals, or 1 point below the upper boundary for sell signals), the robot opens a position
4. **Stop Loss & Take Profit**: Fixed stop loss and take profit levels based on configuration
5. **Trailing Stop**: When profit reaches the stop loss distance, the stop loss is moved to breakeven
6. **Reversal System**: If a trade closes at a loss, the robot can reverse and open the opposite trade (configurable)
7. **Range Blocking**: If a trade closes at take profit, the range is blocked for the rest of the day (no more trades until next day's range)

### Trading Conditions

**For Buy Signals:**
- Price breaks below the range low by the specified breakout points
- Price then returns above the range low by 1 point
- Robot opens a BUY position

**For Sell Signals:**
- Price breaks above the range high by the specified breakout points  
- Price then returns below the range high by 1 point
- Robot opens a SELL position

### Risk Management

- **Fixed Stop Loss**: Configurable fixed stop loss in points
- **Take Profit**: Multiple of stop loss distance (configurable multiplier)
- **Trailing Stop**: Moves stop to breakeven when profit equals stop loss distance
- **Reversal System**: After a losing trade, can reverse direction with optional lot scaling
- **Maximum Reversals**: Configurable limit on number of reversals per sequence
- **Daily Range Blocking**: After a profitable trade (take profit), the range is blocked until the next day

## File Structure

- [`TrendChangeSimple.mq5`](TrendChangeSimple.mq5) - Main robot file
- [`TrendChangeSimpleConfig.mqh`](TrendChangeSimpleConfig.mqh) - Configuration parameters
- [`TrendChangeSimpleUtils.mqh`](TrendChangeSimpleUtils.mqh) - Utility functions
- [`TradingOperationsSimple.mqh`](TradingOperationsSimple.mqh) - Trading operations
- [`RangeManager.mqh`](RangeManager.mqh) - Range detection and management

## Configuration Parameters

The robot can be configured through the following input parameters:

### Basic Settings
- **`InpMagicNumber`** - Unique identifier for the robot's trades (default: 234567)
- **`InpLotSize`** - Base lot size for trades (default: 0.01)
- **`InpDebugMode`** - Enable debug logging (default: true)

### Strategy Settings
- **`InpBreakoutPoints`** - Points required to detect breakout (default: 10)
- **`InpStopLossPoints`** - Fixed stop loss in points (default: 20)
- **`InpTakeProfitMultiplier`** - Take profit multiplier relative to stop loss (default: 2.0)

### Reversal System
- **`InpMaxReversals`** - Maximum number of reversals (0 = no reversals, default: 3)
- **`InpLotScalingFactor`** - Lot scaling factor for reversals (1.0 = no scaling, 2.0 = doubling, default: 1.0)
- **`InpReverseOnBreakeven`** - Whether to reverse when position is closed at breakeven (default: true)

### Time Settings
- **`InpTradingStartHour`** - Start of trading hours (default: 0)
- **`InpTradingEndHour`** - End of trading hours (default: 23)

## Installation

1. Copy all files to the `MQL5/Experts/Trend Change Simple/` folder in your MetaTrader 5 terminal
2. Restart MetaTrader 5 or refresh the expert list
3. Drag the robot onto the chart of your choice
4. Configure parameters as needed
5. Enable "Allow Algo Trading" in the terminal

## Usage Example

### Typical Configuration for EURUSD M15:
- **Breakout Points**: 10 (represents about 1 pip for most pairs)
- **Stop Loss Points**: 20 (represents about 2 pips)
- **Take Profit Multiplier**: 2.0 (4 pip take profit)
- **Max Reversals**: 2 (allows 2 reversal attempts)
- **Lot Scaling Factor**: 1.5 (increase lot by 50% on each reversal)

### Expected Behavior:
1. Robot detects previous day range (16:00-00:00)
2. Waits for price to break range by 10 points
3. When price returns 1 point into range, opens counter-trend position
4. If trade closes at take profit, range is blocked for the rest of the day
5. If trade closes at stop loss, reverses with 1.5x lot size (if reversals remaining)
6. Next day: new range is detected and system resets

## Point Calculation

The robot automatically handles point calculation for different pair types:
- **Regular pairs**: 1 point = 0.0001 (4th decimal place)
- **JPY pairs**: 1 point = 0.01 (3rd decimal place)

## Risk Management Features

### Reversal System Logic
1. **First Trade**: Base lot size
2. **After Loss**: Open opposite direction with scaled lot
3. **After Profit (Take Profit or Breakeven)**: Block range for day, reset to base lot and clear reversal count
4. **Max Reversals Reached**: Stop trading until next day's range

### Example Reversal Sequence (with 2.0 scaling factor):
1. Trade 1: 0.01 lot → Loss → Reverse
2. Trade 2: 0.02 lot → Loss → Reverse
3. Trade 3: 0.04 lot → Take Profit or Breakeven → Block range for day
4. Next day: New range detected, reset to 0.01 lot

**Alternative scenario:**
1. Trade 1: 0.01 lot → Loss → Reverse
2. Trade 2: 0.02 lot → Loss → Reverse
3. Trade 3: 0.04 lot → Loss → Stop (max reversals reached)
4. Wait for next day's range

## Visual Elements

The robot draws the following on the chart:
- **Blue line**: Previous day range high
- **Red line**: Previous day range low
- **Gray rectangle**: Previous day range area

## Risk Warning

This is an automated trading system that involves substantial risk:
- **False breakouts** may not always reverse as expected
- **Reversal system** can amplify losses if market continues trending
- **Always test on demo** before using real money
- **Monitor performance** regularly and adjust parameters as needed

## Recommended Testing

1. **Backtest** on historical data with different parameter combinations
2. **Demo test** for at least 1 month before live trading
3. **Start small** with minimum lot sizes in live trading
4. **Monitor closely** during first weeks of operation

## Troubleshooting

### Common Issues:
- **No trades**: Check if range is being detected (debug mode shows range values)
- **Unexpected entries**: Verify breakout points configuration
- **Large losses**: Consider reducing lot scaling factor or max reversals

### Debug Information:
Enable `InpDebugMode = true` to see detailed logging of:
- Range detection and values
- Breakout detection
- Trade signals and executions
- Reversal system operations

## Support

For questions about the robot logic or issues, check the debug logs first. The robot provides extensive logging when debug mode is enabled.

## Disclaimer

This trading robot is provided for educational purposes. Trading in financial markets involves substantial risk of loss. Past performance does not guarantee future results. Use at your own risk.