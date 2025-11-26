# Opening Range Breakout Expert Adviser (MQL5)

## Overview

This Expert Adviser implements an **Opening Range Breakout** trading strategy for MetaTrader 5. The EA identifies a price range during a specified time period and places pending stop orders to trade breakouts from that range.

## Strategy Description

1. **Range Identification**: During a user-defined time period (e.g., 9:00-9:30), the EA tracks the highest and lowest prices
2. **Order Placement**: After the range period ends, the EA places:
   - A **Buy Stop** order at the high of the range
   - A **Sell Stop** order at the low of the range
3. **Order Replacement**: When an order is triggered, it is automatically replaced with a new order at the same price
4. **Trade Limits**: Trading stops when the maximum number of trades per day is reached
5. **Daily Reset**: All counters and range values reset at the start of each new trading day

## Installation

1. Copy `OpeningRangeBreakout.mq5` to your MetaTrader 5 `MQL5/Experts/` folder
2. Compile the EA in MetaEditor (F7) or it will auto-compile when you drag it to a chart
3. Drag the EA onto your desired chart
4. Configure the input parameters (see below)
5. Enable AutoTrading in MT5

## Input Parameters

### Range Time Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| **Range Start Hour** | Hour when range tracking begins (0-23) | 9 |
| **Range Start Minute** | Minute when range tracking begins (0-59) | 0 |
| **Range End Hour** | Hour when range tracking ends (0-23) | 9 |
| **Range End Minute** | Minute when range tracking ends (0-59) | 30 |

**Example**: Default settings track the range from 9:00 to 9:30

### Range Conditions

| Parameter | Description | Default |
|-----------|-------------|---------|
| **Maximum Range Size (Points)** | Maximum allowed range size. Orders will NOT be placed if range exceeds this value | 500 |
| **Trade Direction** | Which direction to trade:<br>- **Both Directions**: Place both buy and sell stop orders<br>- **Buy Only**: Only place buy stop orders<br>- **Sell Only**: Only place sell stop orders | Both |

### Stop Loss & Take Profit

| Parameter | Description | Default |
|-----------|-------------|---------|
| **Stop Loss (% of Range)** | Stop loss distance as a percentage of the range size | 100% |
| **Take Profit (% of Range)** | Take profit distance as a percentage of the range size | 200% |

**Examples**:
- Range = 50 pips, SL = 100%, TP = 200% → SL = 50 pips, TP = 100 pips
- Range = 30 pips, SL = 50%, TP = 150% → SL = 15 pips, TP = 45 pips

### Lot Size Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| **Lot Size Mode** | How to calculate lot size:<br>- **Fixed Lot Size**: Use a fixed lot size<br>- **Risk Based on Balance**: Calculate lot size based on account balance and risk percentage | Risk Based |
| **Fixed Lot Size** | Lot size when using Fixed mode | 0.1 |
| **Risk Percent of Balance** | Percentage of account balance to risk per trade (used in Risk Based mode) | 1.0% |

**Risk-Based Calculation**:
The EA calculates the lot size to risk the specified percentage of your account balance based on the stop loss distance.

### Trade Management

| Parameter | Description | Default |
|-----------|-------------|---------|
| **Maximum Trades Per Day** | Maximum number of trades allowed per day. No new orders after this limit is reached | 3 |
| **Magic Number** | Unique identifier for this EA's orders | 123456 |

## How It Works

### 1. Range Tracking Phase

During the specified range time (e.g., 9:00-9:30):
- The EA continuously monitors price action
- Tracks the highest high and lowest low
- Logs any updates to range boundaries

**Example Log Output:**
```
Range tracking started - Initial High: 1.09500 Low: 1.09450
Range High updated: 1.09500 -> 1.09520
Range Low updated: 1.09450 -> 1.09430
```

### 2. Range Finalization

When the range period ends:
- The EA finalizes the range values
- Calculates the range size in points
- Checks if the range meets the maximum size condition

**Example Log Output:**
```
========================================
Range Period Ended - Range Finalized
Range High: 1.09520
Range Low: 1.09430
Range Size: 0.00090 (90 points)
Range size acceptable - Orders will be placed
========================================
```

**If range is too large:**
```
Range too large (600 points > 500 max) - Orders will NOT be placed
```

### 3. Order Placement

If the range passes all conditions:
- Calculates stop loss and take profit levels
- Calculates appropriate lot size
- Places buy stop order at range high (if allowed)
- Places sell stop order at range low (if allowed)

**Example Log Output:**
```
========================================
Attempting to place stop orders...
Stop Loss Distance: 0.00090 (100% of range)
Take Profit Distance: 0.00180 (200% of range)
Lot size calculation: RISK-BASED mode
  Account Balance: 10000.00
  Risk Amount: 100.00 (1%)
  Stop Loss Distance: 0.00090
  Calculated Lot Size: 0.11
  Normalized Lot Size: 0.11 (Min: 0.01 Max: 100.00 Step: 0.01)
Placing BUY STOP order:
  Price: 1.09520
  Stop Loss: 1.09430
  Take Profit: 1.09700
  Lot Size: 0.11
SUCCESS: Buy Stop order placed. Ticket: 123456789
Placing SELL STOP order:
  Price: 1.09430
  Stop Loss: 1.09520
  Take Profit: 1.09250
  Lot Size: 0.11
SUCCESS: Sell Stop order placed. Ticket: 123456790
========================================
```

### 4. Order Monitoring & Replacement

The EA continuously monitors pending orders:
- Detects when an order is triggered
- Increments the trade counter
- Replaces the triggered order with a new one (if trade limit not reached)

**Example Log Output:**
```
========================================
BUY STOP order triggered! Ticket: 123456789
Trade count increased to: 1/3
Replacing triggered orders...
Remaining trades allowed: 2
Replacing BUY STOP order at: 1.09520
SUCCESS: Buy Stop order replaced. New Ticket: 123456791
========================================
```

**When trade limit is reached:**
```
Maximum trades per day reached (3). No more orders will be placed today.
```

### 5. Daily Reset

At the start of each new trading day:
- All counters reset to zero
- Range values are cleared
- The EA is ready to start fresh

**Example Log Output:**
```
========================================
NEW TRADING DAY DETECTED
Previous day: 15 -> New day: 16
Resetting daily values...
Daily reset complete
Trade count reset to: 0
Range values cleared
========================================
```

## Logging

The EA provides comprehensive logging in the **Experts** tab of the Terminal window. Log messages include:

- **Initialization**: EA settings and parameters
- **Range Tracking**: Updates to range high/low during tracking period
- **Range Finalization**: Final range values and validation results
- **Order Placement**: Detailed information about each order placed
- **Lot Size Calculation**: Breakdown of lot size computation
- **Order Triggers**: Notification when orders are executed
- **Order Replacement**: Details of replacement orders
- **Trade Counting**: Current trade count vs. maximum allowed
- **Daily Reset**: Confirmation of daily reset events
- **Errors**: Any errors encountered during operation

## Usage Tips

### Recommended Settings for Different Markets

**Forex (Major Pairs)**:
- Range: 30 minutes (e.g., 9:00-9:30 for London open)
- Max Range: 300-500 points
- SL: 100% of range
- TP: 150-200% of range

**Indices**:
- Range: 15-30 minutes (e.g., 9:30-10:00 for US open)
- Max Range: 1000-2000 points (adjust for instrument)
- SL: 80-100% of range
- TP: 200% of range

**Commodities**:
- Range: 60 minutes for slower markets
- Max Range: varies by instrument
- SL: 100% of range
- TP: 150-200% of range

### Risk Management

1. **Use Risk-Based Lot Sizing**: Start with 0.5-1% risk per trade
2. **Set Realistic Trade Limits**: 2-3 trades per day is reasonable
3. **Monitor Range Size**: Adjust max range based on typical volatility
4. **Test First**: Always test on a demo account first

### Optimization

Consider optimizing these parameters on historical data:
- Range start/end times
- Maximum range size
- Stop loss percentage
- Take profit percentage
- Maximum trades per day

## Troubleshooting

### Orders Not Being Placed

**Check the Experts tab logs for these messages:**

1. **"Range too large"**: Increase the Maximum Range Size parameter
2. **"Invalid lot size"**: Check your account balance and risk settings
3. **"Trade disabled"**: Ensure AutoTrading is enabled
4. **"Not enough money"**: Reduce lot size or risk percentage
5. **"Invalid stops"**: Your broker may have minimum stop level requirements

### Orders Not Being Replaced

- Verify that trade count hasn't reached the maximum
- Check that the EA is still running (should see log activity)
- Ensure the symbol has active trading hours

### Unexpected Behavior

1. Check the **Experts** tab for detailed logs
2. Verify your input parameters are correct
3. Ensure the time zone matches your broker's server time
4. Check that there are no conflicting EAs running

## Important Notes

- **Broker Time**: The EA uses broker server time for range detection
- **Slippage**: Actual fill prices may differ from stop order prices during high volatility
- **Weekends**: The EA automatically resets on Monday
- **News Events**: Consider disabling the EA during high-impact news
- **Backtesting**: The EA can be backtested in the Strategy Tester (visual mode recommended)

## Version History

**Version 1.00**
- Initial release
- Opening range breakout strategy
- Risk-based and fixed lot sizing
- Order replacement functionality
- Daily trade limits
- Comprehensive logging

## Support

For issues, questions, or suggestions, check the Experts tab logs first as they provide detailed information about the EA's operation.

## Disclaimer

**Trading forex and CFDs involves significant risk of loss and is not suitable for all investors. Past performance is not indicative of future results. Always test on a demo account before trading live.**

---

**Happy Trading!**
