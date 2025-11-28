//+------------------------------------------------------------------+
//|                                        OpeningRangeBreakout.mq5 |
//|                                                                  |
//|                    Opening Range Breakout Expert Adviser         |
//+------------------------------------------------------------------+
#property copyright "Opening Range Breakout EA"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
enum ENUM_TRADE_DIRECTION
{
   TRADE_BOTH,      // Both Directions
   TRADE_BUY_ONLY,  // Buy Only
   TRADE_SELL_ONLY  // Sell Only
};

enum ENUM_LOT_MODE
{
   LOT_FIXED,       // Fixed Lot Size
   LOT_RISK_BASED   // Risk Based on Balance
};

// Range Time Settings
input group "=== Range Time Settings ==="
input int      InpRangeStartHour    = 9;      // Range Start Hour (0-23)
input int      InpRangeStartMinute  = 0;      // Range Start Minute (0-59)
input int      InpRangeEndHour      = 9;      // Range End Hour (0-23)
input int      InpRangeEndMinute    = 30;     // Range End Minute (0-59)

// Range Conditions
input group "=== Range Conditions ==="
input int      InpMaxRangePoints    = 500;    // Maximum Range Size (Points)
input ENUM_TRADE_DIRECTION InpTradeDirection = TRADE_BOTH; // Trade Direction

// Stop Loss and Take Profit
input group "=== Stop Loss & Take Profit ==="
input double   InpStopLossPercent   = 100.0;  // Stop Loss (% of Range)
input double   InpTakeProfitPercent = 200.0;  // Take Profit (% of Range)

// Lot Size Settings
input group "=== Lot Size Settings ==="
input ENUM_LOT_MODE InpLotMode      = LOT_RISK_BASED; // Lot Size Mode
input double   InpFixedLotSize      = 0.1;    // Fixed Lot Size
input double   InpRiskPercent       = 1.0;    // Risk Percent of Balance

// Trade Management
input group "=== Trade Management ==="
input int      InpMaxTradesPerDay   = 3;      // Maximum Trades Per Day
input int      InpMagicNumber       = 123456; // Magic Number
input string   InpTradeComment      = "ORB";  // Trade Comment

// Advanced Trade Management
input group "=== Advanced Trade Management ==="
input double   InpBreakevenPercent     = 50.0;    // Move to Breakeven (% of Range)
input double   InpPausePercent         = 25.0;    // Pause Before Management (% of Range)
input double   InpBaselineBalance      = 10000.0; // Baseline Balance
input double   InpTrailingStopPoints   = 20.0;    // Trailing Stop Distance (Points) - Below Baseline
input int      InpATRPeriod            = 10;      // ATR Period - At/Above Baseline
input double   InpATRModifier          = 1.0;     // ATR Modifier - At/Above Baseline

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
double   g_rangeHigh = 0.0;           // High of the range
double   g_rangeLow = 0.0;            // Low of the range
bool     g_rangeIdentified = false;   // Flag: range has been identified
bool     g_rangeProcessed = false;    // Flag: range finalization has been attempted
bool     g_ordersPlaced = false;      // Flag: initial orders placed
int      g_tradesCount = 0;           // Number of trades executed today
int      g_currentDay = 0;            // Current day for daily reset
ulong    g_buyStopTicket = 0;         // Buy stop order ticket
ulong    g_sellStopTicket = 0;        // Sell stop order ticket
double   g_rangeSize = 0.0;           // Size of the range in price

// Position tracking arrays for trade management
ulong    g_positionTickets[100];         // Store up to 100 position tickets
bool     g_breakevenReached[100];        // Breakeven reached flag
bool     g_nextMoveReached[100];         // Next move (pause) reached flag
int      g_timeframeLevel[100];          // Current timeframe level for ATR trailing
double   g_breakevenPrice[100];          // Breakeven price
double   g_initialSL[100];               // Initial stop loss
int      g_positionType[100];            // 1 = BUY, 2 = SELL
int      g_positionCount = 0;            // Number of tracked positions

// ATR Indicator handle
int      g_atrHandle = INVALID_HANDLE;   // ATR_Trend_Ind indicator handle

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("========================================");
   Print("Opening Range Breakout EA Initialized");
   Print("========================================");
   Print("Range Time: ", IntegerToString(InpRangeStartHour), ":",
         StringFormat("%02d", InpRangeStartMinute), " to ",
         IntegerToString(InpRangeEndHour), ":",
         StringFormat("%02d", InpRangeEndMinute));
   Print("Max Range: ", InpMaxRangePoints, " points");
   Print("Trade Direction: ", EnumToString(InpTradeDirection));
   Print("Stop Loss: ", InpStopLossPercent, "% of range");
   Print("Take Profit: ", InpTakeProfitPercent, "% of range");
   Print("Lot Mode: ", EnumToString(InpLotMode));
   if(InpLotMode == LOT_FIXED)
      Print("Fixed Lot Size: ", InpFixedLotSize);
   else
      Print("Risk Percent: ", InpRiskPercent, "%");
   Print("Max Trades Per Day: ", InpMaxTradesPerDay);
   Print("Magic Number: ", InpMagicNumber);
   Print("Trade Comment: ", InpTradeComment);
   Print("========================================");
   Print("Trade Management Settings:");
   Print("Breakeven Trigger: ", InpBreakevenPercent, "% of range");
   Print("Pause Before Management: ", InpPausePercent, "% of range");
   Print("Baseline Balance: ", InpBaselineBalance);
   Print("Trailing Stop (below baseline): ", InpTrailingStopPoints, " points");
   Print("ATR Period (at/above baseline): ", InpATRPeriod);
   Print("ATR Modifier: ", InpATRModifier);
   Print("========================================");

   // Initialize current day
   MqlDateTime time_struct;
   TimeCurrent(time_struct);
   g_currentDay = time_struct.day;

   // Initialize position tracking arrays
   g_positionCount = 0;
   ArrayInitialize(g_positionTickets, 0);
   ArrayInitialize(g_breakevenReached, false);
   ArrayInitialize(g_nextMoveReached, false);
   ArrayInitialize(g_timeframeLevel, 0);
   ArrayInitialize(g_breakevenPrice, 0.0);
   ArrayInitialize(g_initialSL, 0.0);
   ArrayInitialize(g_positionType, 0);

   // Create ATR_Trend_Ind indicator handle
   g_atrHandle = iCustom(_Symbol, PERIOD_CURRENT, "ATR_Trend_Ind", InpATRPeriod, InpATRModifier);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("WARNING: Failed to create ATR_Trend_Ind indicator handle");
      Print("ATR trade management will use fallback method");
   }
   else
   {
      Print("ATR_Trend_Ind indicator loaded successfully");
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release ATR indicator handle
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);

   Print("========================================");
   Print("Opening Range Breakout EA Deinitialized");
   Print("Reason: ", reason);
   Print("========================================");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if new day has started
   CheckNewDay();

   // Get current time
   MqlDateTime time_struct;
   TimeCurrent(time_struct);

   // Check if we are within the range period
   if(IsWithinRangeTime(time_struct))
   {
      UpdateRange();
   }
   else if(IsAfterRangeTime(time_struct) && !g_rangeProcessed)
   {
      // Range period has ended, finalize the range (only once per day)
      FinalizeRange();
      g_rangeProcessed = true;  // Mark as processed to prevent repeated messages
   }

   // If range is identified but orders not placed, place them
   if(g_rangeIdentified && !g_ordersPlaced && g_tradesCount < InpMaxTradesPerDay)
   {
      PlaceStopOrders();
   }

   // Check if any orders were triggered and need replacement
   if(g_ordersPlaced && g_tradesCount < InpMaxTradesPerDay)
   {
      CheckAndReplaceOrders();
   }

   // Manage open positions if any exist
   if(PositionsTotal() > 0)
   {
      ManageOpenPositions();
   }
}

//+------------------------------------------------------------------+
//| Check if current time is within range period                     |
//+------------------------------------------------------------------+
bool IsWithinRangeTime(MqlDateTime &time_struct)
{
   int currentMinutes = time_struct.hour * 60 + time_struct.min;
   int rangeStartMinutes = InpRangeStartHour * 60 + InpRangeStartMinute;
   int rangeEndMinutes = InpRangeEndHour * 60 + InpRangeEndMinute;

   return (currentMinutes >= rangeStartMinutes && currentMinutes < rangeEndMinutes);
}

//+------------------------------------------------------------------+
//| Check if current time is after range period                      |
//+------------------------------------------------------------------+
bool IsAfterRangeTime(MqlDateTime &time_struct)
{
   int currentMinutes = time_struct.hour * 60 + time_struct.min;
   int rangeEndMinutes = InpRangeEndHour * 60 + InpRangeEndMinute;

   return (currentMinutes >= rangeEndMinutes);
}

//+------------------------------------------------------------------+
//| Update range high and low during range period                    |
//+------------------------------------------------------------------+
void UpdateRange()
{
   double high = iHigh(_Symbol, PERIOD_CURRENT, 0);
   double low = iLow(_Symbol, PERIOD_CURRENT, 0);

   // Initialize range on first tick within range period
   if(g_rangeHigh == 0.0 || g_rangeLow == 0.0)
   {
      g_rangeHigh = high;
      g_rangeLow = low;
      Print("Range tracking started - Initial High: ", g_rangeHigh,
            " Low: ", g_rangeLow);
      return;
   }

   // Update high if current high is higher
   if(high > g_rangeHigh)
   {
      Print("Range High updated: ", g_rangeHigh, " -> ", high);
      g_rangeHigh = high;
   }

   // Update low if current low is lower
   if(low < g_rangeLow)
   {
      Print("Range Low updated: ", g_rangeLow, " -> ", low);
      g_rangeLow = low;
   }
}

//+------------------------------------------------------------------+
//| Finalize range after range period ends                           |
//+------------------------------------------------------------------+
void FinalizeRange()
{
   if(g_rangeHigh == 0.0 || g_rangeLow == 0.0)
   {
      Print("ERROR: Range not properly tracked. High: ", g_rangeHigh,
            " Low: ", g_rangeLow);
      return;
   }

   g_rangeSize = g_rangeHigh - g_rangeLow;
   double rangeSizePoints = g_rangeSize / _Point;

   Print("========================================");
   Print("Range Period Ended - Range Finalized");
   Print("Range High: ", g_rangeHigh);
   Print("Range Low: ", g_rangeLow);
   Print("Range Size: ", g_rangeSize, " (", rangeSizePoints, " points)");

   // Check if range meets maximum size condition
   if(rangeSizePoints > InpMaxRangePoints)
   {
      Print("Range too large (", rangeSizePoints, " points > ",
            InpMaxRangePoints, " max) - Orders will NOT be placed");
      g_rangeIdentified = false;
      Print("========================================");
      return;
   }

   Print("Range size acceptable - Orders will be placed");
   Print("========================================");
   g_rangeIdentified = true;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on settings                             |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopLossDistance)
{
   double lotSize = 0.0;

   if(InpLotMode == LOT_FIXED)
   {
      lotSize = InpFixedLotSize;
      Print("Lot size calculation: FIXED mode = ", lotSize, " lots");
   }
   else // LOT_RISK_BASED
   {
      double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmount = accountBalance * InpRiskPercent / 100.0;
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

      double stopLossTicks = stopLossDistance / tickSize;
      lotSize = riskAmount / (stopLossTicks * tickValue);

      Print("Lot size calculation: RISK-BASED mode");
      Print("  Account Balance: ", accountBalance);
      Print("  Risk Amount: ", riskAmount, " (", InpRiskPercent, "%)");
      Print("  Stop Loss Distance: ", stopLossDistance);
      Print("  Calculated Lot Size: ", lotSize);
   }

   // Normalize lot size
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   lotSize = MathFloor(lotSize / lotStep) * lotStep;

   Print("  Normalized Lot Size: ", lotSize, " (Min: ", minLot,
         " Max: ", maxLot, " Step: ", lotStep, ")");

   return lotSize;
}

//+------------------------------------------------------------------+
//| Place buy and sell stop orders                                   |
//+------------------------------------------------------------------+
void PlaceStopOrders()
{
   Print("========================================");
   Print("Attempting to place stop orders...");

   // Get current market information
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;
   long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double stopLevelPrice = stopLevel * _Point;

   Print("Current Market Info:");
   Print("  Ask: ", ask, " | Bid: ", bid);
   Print("  Spread: ", spread, " (", (spread/_Point), " points)");
   Print("  Broker Stop Level: ", stopLevel, " points (", stopLevelPrice, " price)");

   // Calculate stop loss and take profit distances
   double slDistance = g_rangeSize * InpStopLossPercent / 100.0;
   double tpDistance = g_rangeSize * InpTakeProfitPercent / 100.0;

   Print("Stop Loss Distance: ", slDistance, " (", InpStopLossPercent, "% of range)");
   Print("Take Profit Distance: ", tpDistance, " (", InpTakeProfitPercent, "% of range)");

   // Calculate lot size
   double lotSize = CalculateLotSize(slDistance);

   if(lotSize <= 0)
   {
      Print("ERROR: Invalid lot size calculated: ", lotSize);
      Print("========================================");
      return;
   }

   // Calculate adjusted order prices with automatic buffer
   // Buffer = max(stop level, spread) + 2 points for safety
   double buffer = MathMax(stopLevelPrice, spread) + (2 * _Point);

   double buyStopPrice = g_rangeHigh;
   double minBuyStopPrice = ask + buffer;

   if(buyStopPrice < minBuyStopPrice)
   {
      Print("WARNING: Original buy stop price (", buyStopPrice,
            ") too close to Ask (", ask, ")");
      Print("  Minimum required: ", minBuyStopPrice, " (Ask + ", buffer, " buffer)");
      buyStopPrice = minBuyStopPrice;
      Print("  Adjusted buy stop price to: ", buyStopPrice);
   }

   double sellStopPrice = g_rangeLow;
   double maxSellStopPrice = bid - buffer;

   if(sellStopPrice > maxSellStopPrice)
   {
      Print("WARNING: Original sell stop price (", sellStopPrice,
            ") too close to Bid (", bid, ")");
      Print("  Maximum allowed: ", maxSellStopPrice, " (Bid - ", buffer, " buffer)");
      sellStopPrice = maxSellStopPrice;
      Print("  Adjusted sell stop price to: ", sellStopPrice);
   }

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.symbol = _Symbol;
   request.volume = lotSize;
   request.magic = InpMagicNumber;
   request.comment = InpTradeComment;
   request.deviation = 10;
   request.type_filling = ORDER_FILLING_IOC;

   // Place Buy Stop Order
   if(InpTradeDirection == TRADE_BOTH || InpTradeDirection == TRADE_BUY_ONLY)
   {
      request.action = TRADE_ACTION_PENDING;
      request.type = ORDER_TYPE_BUY_STOP;
      request.price = NormalizeDouble(buyStopPrice, _Digits);
      // SL and TP calculated from ORIGINAL range high, not adjusted entry price
      request.sl = NormalizeDouble(g_rangeHigh - slDistance, _Digits);
      request.tp = NormalizeDouble(g_rangeHigh + tpDistance, _Digits);

      Print("Placing BUY STOP order:");
      Print("  Price: ", request.price);
      Print("  Stop Loss: ", request.sl);
      Print("  Take Profit: ", request.tp);
      Print("  Lot Size: ", request.volume);

      if(OrderSend(request, result))
      {
         if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
         {
            g_buyStopTicket = result.order;
            Print("SUCCESS: Buy Stop order placed. Ticket: ", g_buyStopTicket);
         }
         else
         {
            Print("ERROR: Buy Stop order failed. Return code: ", result.retcode,
                  " (", GetRetcodeDescription(result.retcode), ")");
            Print("  Error details: ", result.comment);
         }
      }
      else
      {
         int lastError = GetLastError();
         Print("ERROR: OrderSend failed for Buy Stop. Error code: ", lastError);
         Print("  Error description: ", ErrorDescription(lastError));
      }
   }
   else
   {
      Print("Buy Stop order skipped (Trade Direction: ",
            EnumToString(InpTradeDirection), ")");
   }

   // Place Sell Stop Order
   if(InpTradeDirection == TRADE_BOTH || InpTradeDirection == TRADE_SELL_ONLY)
   {
      ZeroMemory(request);
      ZeroMemory(result);

      request.action = TRADE_ACTION_PENDING;
      request.symbol = _Symbol;
      request.volume = lotSize;
      request.magic = InpMagicNumber;
      request.comment = InpTradeComment;
      request.type = ORDER_TYPE_SELL_STOP;
      request.price = NormalizeDouble(sellStopPrice, _Digits);
      // SL and TP calculated from ORIGINAL range low, not adjusted entry price
      request.sl = NormalizeDouble(g_rangeLow + slDistance, _Digits);
      request.tp = NormalizeDouble(g_rangeLow - tpDistance, _Digits);
      request.deviation = 10;
      request.type_filling = ORDER_FILLING_IOC;

      Print("Placing SELL STOP order:");
      Print("  Price: ", request.price);
      Print("  Stop Loss: ", request.sl);
      Print("  Take Profit: ", request.tp);
      Print("  Lot Size: ", request.volume);

      if(OrderSend(request, result))
      {
         if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
         {
            g_sellStopTicket = result.order;
            Print("SUCCESS: Sell Stop order placed. Ticket: ", g_sellStopTicket);
         }
         else
         {
            Print("ERROR: Sell Stop order failed. Return code: ", result.retcode,
                  " (", GetRetcodeDescription(result.retcode), ")");
            Print("  Error details: ", result.comment);
         }
      }
      else
      {
         int lastError = GetLastError();
         Print("ERROR: OrderSend failed for Sell Stop. Error code: ", lastError);
         Print("  Error description: ", ErrorDescription(lastError));
      }
   }
   else
   {
      Print("Sell Stop order skipped (Trade Direction: ",
            EnumToString(InpTradeDirection), ")");
   }

   g_ordersPlaced = true;
   Print("Stop orders placement complete");
   Print("========================================");
}

//+------------------------------------------------------------------+
//| Check if orders were triggered and replace them                  |
//+------------------------------------------------------------------+
void CheckAndReplaceOrders()
{
   bool buyOrderTriggered = false;
   bool sellOrderTriggered = false;

   // Check Buy Stop Order
   if(g_buyStopTicket > 0)
   {
      if(!OrderSelect(g_buyStopTicket))
      {
         // Order not found in pending orders, check if it was executed
         if(PositionSelectByTicket(g_buyStopTicket) || IsOrderInHistory(g_buyStopTicket))
         {
            Print("========================================");
            Print("BUY STOP order triggered! Ticket: ", g_buyStopTicket);
            buyOrderTriggered = true;
            g_tradesCount++;
            Print("Trade count increased to: ", g_tradesCount, "/", InpMaxTradesPerDay);
            g_buyStopTicket = 0;
         }
      }
   }

   // Check Sell Stop Order
   if(g_sellStopTicket > 0)
   {
      if(!OrderSelect(g_sellStopTicket))
      {
         // Order not found in pending orders, check if it was executed
         if(PositionSelectByTicket(g_sellStopTicket) || IsOrderInHistory(g_sellStopTicket))
         {
            Print("========================================");
            Print("SELL STOP order triggered! Ticket: ", g_sellStopTicket);
            sellOrderTriggered = true;
            g_tradesCount++;
            Print("Trade count increased to: ", g_tradesCount, "/", InpMaxTradesPerDay);
            g_sellStopTicket = 0;
         }
      }
   }

   // Replace triggered orders if trade limit not reached
   if((buyOrderTriggered || sellOrderTriggered) && g_tradesCount < InpMaxTradesPerDay)
   {
      Print("Replacing triggered orders...");
      Print("Remaining trades allowed: ", InpMaxTradesPerDay - g_tradesCount);

      // Get current market prices
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double spread = ask - bid;
      long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double stopLevelPrice = stopLevel * _Point;

      // Calculate intelligent buffer (same as initial order placement)
      double buffer = MathMax(stopLevelPrice, spread) + (2 * _Point);

      Print("Current Market Info:");
      Print("  Ask: ", ask, " | Bid: ", bid);
      Print("  Spread: ", spread, " (", (spread/_Point), " points)");
      Print("  Stop Level: ", stopLevel, " points (", stopLevelPrice, " price)");
      Print("  Calculated Buffer: ", buffer, " (", (buffer/_Point), " points)");

      // Calculate stop loss and take profit distances
      double slDistance = g_rangeSize * InpStopLossPercent / 100.0;
      double tpDistance = g_rangeSize * InpTakeProfitPercent / 100.0;
      double lotSize = CalculateLotSize(slDistance);

      MqlTradeRequest request;
      MqlTradeResult result;

      // Replace SELL Stop when BUY was triggered (only if sell stop doesn't already exist)
      if(buyOrderTriggered && g_sellStopTicket == 0 && (InpTradeDirection == TRADE_BOTH || InpTradeDirection == TRADE_SELL_ONLY))
      {
         Print("Buy order was triggered - checking if sell stop needs replacement...");
         Print("Sell stop ticket: ", g_sellStopTicket, " (0 = doesn't exist)");

         // Check if original range low price is still valid for a sell stop
         double sellStopPrice = g_rangeLow;
         double maxSellStopPrice = bid - buffer;

         if(sellStopPrice > maxSellStopPrice)
         {
            Print("WARNING: Original sell stop price (", sellStopPrice,
                  ") too close to Bid (", bid, ")");
            Print("  Maximum allowed: ", maxSellStopPrice, " (Bid - ", buffer, " buffer)");
            sellStopPrice = maxSellStopPrice;
            Print("  Adjusted sell stop price to: ", sellStopPrice);
         }

         ZeroMemory(request);
         ZeroMemory(result);

         request.action = TRADE_ACTION_PENDING;
         request.symbol = _Symbol;
         request.volume = lotSize;
         request.magic = InpMagicNumber;
         request.comment = InpTradeComment;
         request.type = ORDER_TYPE_SELL_STOP;
         request.price = NormalizeDouble(sellStopPrice, _Digits);
         // SL and TP calculated from ORIGINAL range low, not adjusted entry price
         request.sl = NormalizeDouble(g_rangeLow + slDistance, _Digits);
         request.tp = NormalizeDouble(g_rangeLow - tpDistance, _Digits);
         request.deviation = 10;
         request.type_filling = ORDER_FILLING_IOC;

         Print("Replacing SELL STOP order:");
         Print("  Price: ", request.price);
         Print("  Stop Loss: ", request.sl);
         Print("  Take Profit: ", request.tp);

         if(OrderSend(request, result))
         {
            if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
            {
               g_sellStopTicket = result.order;
               Print("SUCCESS: Sell Stop order replaced. New Ticket: ", g_sellStopTicket);
            }
            else
            {
               Print("ERROR: Sell Stop replacement failed. Return code: ", result.retcode,
                     " (", GetRetcodeDescription(result.retcode), ")");
            }
         }
         else
         {
            Print("ERROR: OrderSend failed for Sell Stop replacement");
         }
      }
      else if(buyOrderTriggered && g_sellStopTicket > 0)
      {
         Print("Buy order was triggered - sell stop already exists (Ticket: ", g_sellStopTicket, "), no replacement needed");
      }

      // Replace BUY Stop when SELL was triggered (only if buy stop doesn't already exist)
      if(sellOrderTriggered && g_buyStopTicket == 0 && (InpTradeDirection == TRADE_BOTH || InpTradeDirection == TRADE_BUY_ONLY))
      {
         Print("Sell order was triggered - checking if buy stop needs replacement...");
         Print("Buy stop ticket: ", g_buyStopTicket, " (0 = doesn't exist)");

         // Check if original range high price is still valid for a buy stop
         double buyStopPrice = g_rangeHigh;
         double minBuyStopPrice = ask + buffer;

         if(buyStopPrice < minBuyStopPrice)
         {
            Print("WARNING: Original buy stop price (", buyStopPrice,
                  ") too close to Ask (", ask, ")");
            Print("  Minimum required: ", minBuyStopPrice, " (Ask + ", buffer, " buffer)");
            buyStopPrice = minBuyStopPrice;
            Print("  Adjusted buy stop price to: ", buyStopPrice);
         }

         ZeroMemory(request);
         ZeroMemory(result);

         request.action = TRADE_ACTION_PENDING;
         request.symbol = _Symbol;
         request.volume = lotSize;
         request.magic = InpMagicNumber;
         request.comment = InpTradeComment;
         request.type = ORDER_TYPE_BUY_STOP;
         request.price = NormalizeDouble(buyStopPrice, _Digits);
         // SL and TP calculated from ORIGINAL range high, not adjusted entry price
         request.sl = NormalizeDouble(g_rangeHigh - slDistance, _Digits);
         request.tp = NormalizeDouble(g_rangeHigh + tpDistance, _Digits);
         request.deviation = 10;
         request.type_filling = ORDER_FILLING_IOC;

         Print("Replacing BUY STOP order:");
         Print("  Price: ", request.price);
         Print("  Stop Loss: ", request.sl);
         Print("  Take Profit: ", request.tp);

         if(OrderSend(request, result))
         {
            if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
            {
               g_buyStopTicket = result.order;
               Print("SUCCESS: Buy Stop order replaced. New Ticket: ", g_buyStopTicket);
            }
            else
            {
               Print("ERROR: Buy Stop replacement failed. Return code: ", result.retcode,
                     " (", GetRetcodeDescription(result.retcode), ")");
            }
         }
         else
         {
            Print("ERROR: OrderSend failed for Buy Stop replacement");
         }
      }
      else if(sellOrderTriggered && g_buyStopTicket > 0)
      {
         Print("Sell order was triggered - buy stop already exists (Ticket: ", g_buyStopTicket, "), no replacement needed");
      }

      Print("========================================");
   }
   else if((buyOrderTriggered || sellOrderTriggered) && g_tradesCount >= InpMaxTradesPerDay)
   {
      Print("Maximum trades per day reached (", InpMaxTradesPerDay,
            "). No more orders will be placed today.");
      Print("========================================");
   }
}

//+------------------------------------------------------------------+
//| Check if order is in history                                     |
//+------------------------------------------------------------------+
bool IsOrderInHistory(ulong ticket)
{
   if(HistoryOrderSelect(ticket))
      return true;

   if(HistoryDealSelect(ticket))
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| Check for new trading day and reset                              |
//+------------------------------------------------------------------+
void CheckNewDay()
{
   MqlDateTime time_struct;
   TimeCurrent(time_struct);

   if(time_struct.day != g_currentDay)
   {
      Print("========================================");
      Print("NEW TRADING DAY DETECTED");
      Print("Previous day: ", g_currentDay, " -> New day: ", time_struct.day);
      Print("Resetting daily values...");

      // Reset all daily tracking variables
      g_rangeHigh = 0.0;
      g_rangeLow = 0.0;
      g_rangeSize = 0.0;
      g_rangeIdentified = false;
      g_rangeProcessed = false;
      g_ordersPlaced = false;
      g_tradesCount = 0;
      g_buyStopTicket = 0;
      g_sellStopTicket = 0;
      g_currentDay = time_struct.day;

      // Reset position tracking arrays
      g_positionCount = 0;
      ArrayInitialize(g_positionTickets, 0);
      ArrayInitialize(g_breakevenReached, false);
      ArrayInitialize(g_nextMoveReached, false);
      ArrayInitialize(g_timeframeLevel, 0);
      ArrayInitialize(g_breakevenPrice, 0.0);
      ArrayInitialize(g_initialSL, 0.0);
      ArrayInitialize(g_positionType, 0);

      Print("Daily reset complete");
      Print("Trade count reset to: 0");
      Print("Range values cleared");
      Print("Position tracking arrays reset");
      Print("========================================");
   }
}

//+------------------------------------------------------------------+
//| Get return code description                                      |
//+------------------------------------------------------------------+
string GetRetcodeDescription(uint retcode)
{
   switch(retcode)
   {
      case TRADE_RETCODE_DONE: return "Request completed";
      case TRADE_RETCODE_PLACED: return "Order placed";
      case TRADE_RETCODE_REJECT: return "Request rejected";
      case TRADE_RETCODE_CANCEL: return "Request canceled";
      case TRADE_RETCODE_ERROR: return "Request processing error";
      case TRADE_RETCODE_INVALID: return "Invalid request";
      case TRADE_RETCODE_INVALID_VOLUME: return "Invalid volume";
      case TRADE_RETCODE_INVALID_PRICE: return "Invalid price";
      case TRADE_RETCODE_INVALID_STOPS: return "Invalid stops";
      case TRADE_RETCODE_TRADE_DISABLED: return "Trade disabled";
      case TRADE_RETCODE_MARKET_CLOSED: return "Market closed";
      case TRADE_RETCODE_NO_MONEY: return "Not enough money";
      case TRADE_RETCODE_PRICE_CHANGED: return "Price changed";
      case TRADE_RETCODE_PRICE_OFF: return "No quotes";
      case TRADE_RETCODE_CONNECTION: return "No connection";
      default: return "Unknown return code";
   }
}

//+------------------------------------------------------------------+
//| Get error description                                            |
//+------------------------------------------------------------------+
string ErrorDescription(int error_code)
{
   switch(error_code)
   {
      case 0:    return "Success";
      case 4: return "Invalid parameters";
      case 5:    return "Old client terminal version";
      case 64:   return "Account blocked";
      case 65:   return "Invalid account";
      case 128:  return "Trade timeout";
      case 129:  return "Invalid price";
      case 130:  return "Invalid stops";
      case 131:  return "Invalid trade volume";
      case 132:  return "Market is closed";
      case 133:  return "Trade is disabled";
      case 134:  return "Not enough money";
      case 135:  return "Price changed";
      case 136:  return "Off quotes";
      case 137:  return "Broker is busy";
      case 138:  return "Requote";
      case 139:  return "Order is locked";
      case 140:  return "Buy orders only allowed";
      case 141:  return "Too many requests";
      case 145:  return "Modification denied because order too close to market";
      case 146:  return "Trade context is busy";
      case 147:  return "Expiration denied by broker";
      case 148:  return "Too many orders";
      case 149:  return "Hedging prohibited";
      case 150:  return "Prohibited by FIFO rules";
      default:   return "Unknown error";
   }
}

//+------------------------------------------------------------------+
//| Update position tracking arrays                                  |
//+------------------------------------------------------------------+
void UpdatePositionDataArrays()
{
   // Temporary arrays to preserve existing position data
   ulong tempTickets[100];
   bool tempBreakevenReached[100];
   bool tempNextMoveReached[100];
   int tempTimeframeLevel[100];
   double tempBreakevenPrice[100];
   double tempInitialSL[100];
   int tempType[100];
   int tempCount = 0;

   // Initialize temporary arrays
   ArrayInitialize(tempTickets, 0);
   ArrayInitialize(tempBreakevenReached, false);
   ArrayInitialize(tempNextMoveReached, false);
   ArrayInitialize(tempTimeframeLevel, 0);
   ArrayInitialize(tempBreakevenPrice, 0.0);
   ArrayInitialize(tempInitialSL, 0.0);
   ArrayInitialize(tempType, 0);

   // Loop through all open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            int posType = (int)PositionGetInteger(POSITION_TYPE);

            // Check if this position already exists in our array
            int existingIndex = -1;
            for(int j = 0; j < g_positionCount; j++)
            {
               if(g_positionTickets[j] == ticket)
               {
                  existingIndex = j;
                  break;
               }
            }

            // Add to temp array
            if(tempCount < 100)
            {
               tempTickets[tempCount] = ticket;

               // If position already existed, preserve its state
               if(existingIndex >= 0)
               {
                  tempBreakevenReached[tempCount] = g_breakevenReached[existingIndex];
                  tempNextMoveReached[tempCount] = g_nextMoveReached[existingIndex];
                  tempTimeframeLevel[tempCount] = g_timeframeLevel[existingIndex];
                  tempBreakevenPrice[tempCount] = g_breakevenPrice[existingIndex];
                  tempInitialSL[tempCount] = g_initialSL[existingIndex];
                  tempType[tempCount] = g_positionType[existingIndex];
               }
               else
               {
                  // New position - initialize with default values
                  tempBreakevenReached[tempCount] = false;
                  tempNextMoveReached[tempCount] = false;
                  tempTimeframeLevel[tempCount] = 0;
                  tempBreakevenPrice[tempCount] = 0.0;
                  tempInitialSL[tempCount] = PositionGetDouble(POSITION_SL);
                  tempType[tempCount] = (posType == POSITION_TYPE_BUY) ? 1 : 2;
               }

               tempCount++;
            }
         }
      }
   }

   // Copy temp arrays back to main arrays
   g_positionCount = tempCount;
   for(int k = 0; k < g_positionCount; k++)
   {
      g_positionTickets[k] = tempTickets[k];
      g_breakevenReached[k] = tempBreakevenReached[k];
      g_nextMoveReached[k] = tempNextMoveReached[k];
      g_timeframeLevel[k] = tempTimeframeLevel[k];
      g_breakevenPrice[k] = tempBreakevenPrice[k];
      g_initialSL[k] = tempInitialSL[k];
      g_positionType[k] = tempType[k];
   }
}

//+------------------------------------------------------------------+
//| Find position index in tracking arrays                           |
//+------------------------------------------------------------------+
int FindPositionIndex(ulong ticket)
{
   for(int i = 0; i < g_positionCount; i++)
   {
      if(g_positionTickets[i] == ticket)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Get ATR Trend Indicator value                                    |
//+------------------------------------------------------------------+
double GetATRTrendIndValue(ENUM_TIMEFRAMES timeframe, int buffer = 1)
{
   double atr[];
   ArraySetAsSeries(atr, true);

   // Try to get values from ATR_Trend_Ind indicator
   if(g_atrHandle != INVALID_HANDLE)
   {
      if(CopyBuffer(g_atrHandle, buffer, 0, 3, atr) > 0)
      {
         for(int i = 0; i < 3; i++)
         {
            if(atr[i] != 0 && atr[i] != EMPTY_VALUE)
               return atr[i];
         }
      }
   }

   // Fallback: use standard ATR
   double atrValue = iATR(_Symbol, timeframe, InpATRPeriod, 0);
   if(atrValue > 0)
      return atrValue;

   return 0;
}

//+------------------------------------------------------------------+
//| Get current timeframe based on level                             |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetCurrentTimeframe(int level)
{
   switch(level)
   {
      case 0: return PERIOD_M5;
      case 1: return PERIOD_M15;
      case 2: return PERIOD_M30;
      case 3: return PERIOD_H1;
      case 4: return PERIOD_H4;
      case 5: return PERIOD_D1;
      default: return PERIOD_M5;
   }
}

//+------------------------------------------------------------------+
//| Get timeframe level                                              |
//+------------------------------------------------------------------+
int GetTimeframeLevel(ENUM_TIMEFRAMES timeframe)
{
   switch(timeframe)
   {
      case PERIOD_M5: return 0;
      case PERIOD_M15: return 1;
      case PERIOD_M30: return 2;
      case PERIOD_H1: return 3;
      case PERIOD_H4: return 4;
      case PERIOD_D1: return 5;
      default: return 0;
   }
}

//+------------------------------------------------------------------+
//| Get timeframe name                                               |
//+------------------------------------------------------------------+
string GetTimeframeName(int level)
{
   switch(level)
   {
      case 0: return "M5";
      case 1: return "M15";
      case 2: return "M30";
      case 3: return "H1";
      case 4: return "H4";
      case 5: return "D1";
      default: return "Unknown";
   }
}

//+------------------------------------------------------------------+
//| Validate SL modification                                         |
//+------------------------------------------------------------------+
bool IsValidSLModification(ENUM_POSITION_TYPE posType, double newSL, double currentSL, double currentPrice)
{
   newSL = NormalizeDouble(newSL, _Digits);
   currentSL = NormalizeDouble(currentSL, _Digits);
   currentPrice = NormalizeDouble(currentPrice, _Digits);

   double minDiff = NormalizeDouble(2 * _Point, _Digits);

   // Check if new SL is different from current SL
   if(MathAbs(newSL - currentSL) < minDiff)
      return false;

   // Get minimum stop level
   long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStopLevel = stopLevel * _Point;
   double tolerance = MathMin(10 * _Point, minStopLevel * 0.5);
   if(tolerance == 0) tolerance = 10 * _Point;

   // For BUY positions, SL must be below current price
   if(posType == POSITION_TYPE_BUY)
   {
      if(newSL > currentPrice + tolerance)
         return false;

      double distance = currentPrice - newSL;
      if(distance < 0) distance = 0;

      if(minStopLevel > 0 && distance < (minStopLevel - tolerance))
         return false;
   }
   // For SELL positions, SL must be above current price
   else if(posType == POSITION_TYPE_SELL)
   {
      if(newSL < currentPrice - tolerance)
         return false;

      double distance = newSL - currentPrice;
      if(distance < 0) distance = 0;

      if(minStopLevel > 0 && distance < (minStopLevel - tolerance))
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Safe order modify with validation                                |
//+------------------------------------------------------------------+
bool SafeOrderModify(ulong ticket, double sl, double tp)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentPrice = (posType == POSITION_TYPE_BUY) ?
                         SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   // Validate the modification
   if(!IsValidSLModification(posType, sl, currentSL, currentPrice))
      return false;

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol = _Symbol;
   request.sl = sl;
   request.tp = tp;

   if(!OrderSend(request, result))
   {
      Print("OrderModify failed for #", ticket, ": Error ", GetLastError());
      return false;
   }

   if(result.retcode != TRADE_RETCODE_DONE)
   {
      Print("OrderModify failed for #", ticket, ": Retcode ", result.retcode);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Manage open positions                                            |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   // Update position tracking arrays first
   UpdatePositionDataArrays();

   // Get current balance
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   bool useBelowBaselineMethod = (currentBalance < InpBaselineBalance);

   Print("Managing ", g_positionCount, " positions. Balance: ", currentBalance,
         " (Baseline: ", InpBaselineBalance, ") - Using ",
         (useBelowBaselineMethod ? "Trailing Stop" : "ATR Method"));

   // Manage each position
   for(int i = 0; i < g_positionCount; i++)
   {
      ulong ticket = g_positionTickets[i];
      if(PositionSelectByTicket(ticket))
      {
         if(g_positionType[i] == 1) // BUY
            ManageBuyPosition(ticket, i, useBelowBaselineMethod);
         else if(g_positionType[i] == 2) // SELL
            ManageSellPosition(ticket, i, useBelowBaselineMethod);
      }
   }
}

//+------------------------------------------------------------------+
//| Manage buy position                                              |
//+------------------------------------------------------------------+
void ManageBuyPosition(ulong ticket, int posIndex, bool useBelowBaselineMethod)
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);

   double requiredMoveForBreakeven = g_rangeSize * InpBreakevenPercent / 100.0;
   double priceMove = currentPrice - openPrice;

   // Stage 1: Move to breakeven
   if(!g_breakevenReached[posIndex] && priceMove >= requiredMoveForBreakeven)
   {
      double newSL = NormalizeDouble(openPrice, _Digits);
      if(SafeOrderModify(ticket, newSL, tp))
      {
         g_breakevenReached[posIndex] = true;
         g_breakevenPrice[posIndex] = newSL;
         Print("BUY #", ticket, " moved to breakeven at ", newSL);
      }
      return;
   }

   // Stage 2: Wait for pause trigger
   if(g_breakevenReached[posIndex] && !g_nextMoveReached[posIndex])
   {
      double requiredAdditionalMove = g_rangeSize * InpPausePercent / 100.0;
      double additionalMove = priceMove - requiredMoveForBreakeven;

      if(additionalMove >= requiredAdditionalMove)
      {
         g_nextMoveReached[posIndex] = true;
         g_timeframeLevel[posIndex] = 0;
         Print("BUY #", ticket, " ready for management. Method: ",
               (useBelowBaselineMethod ? "Trailing Stop" : "ATR"));
      }
      return;
   }

   // Stage 3: Active management
   if(g_breakevenReached[posIndex] && g_nextMoveReached[posIndex])
   {
      if(useBelowBaselineMethod)
      {
         // Simple trailing stop
         double trailingDistance = InpTrailingStopPoints * _Point;
         double newSL = NormalizeDouble(currentPrice - trailingDistance, _Digits);

         if(newSL > currentSL && newSL > g_breakevenPrice[posIndex])
         {
            if(SafeOrderModify(ticket, newSL, tp))
               Print("BUY #", ticket, " trailing SL updated to ", newSL);
         }
      }
      else
      {
         // ATR method
         ENUM_TIMEFRAMES currentTF = GetCurrentTimeframe(g_timeframeLevel[posIndex]);
         double atrValue = GetATRTrendIndValue(currentTF, 1);

         if(atrValue > 0 && atrValue > currentSL && atrValue > g_breakevenPrice[posIndex])
         {
            double newSL = NormalizeDouble(atrValue, _Digits);
            if(SafeOrderModify(ticket, newSL, tp))
            {
               Print("BUY #", ticket, " ATR SL updated to ", newSL, " (",
                     GetTimeframeName(g_timeframeLevel[posIndex]), ")");

               if(g_timeframeLevel[posIndex] < 5)
                  g_timeframeLevel[posIndex]++;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage sell position                                             |
//+------------------------------------------------------------------+
void ManageSellPosition(ulong ticket, int posIndex, bool useBelowBaselineMethod)
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);

   double requiredMoveForBreakeven = g_rangeSize * InpBreakevenPercent / 100.0;
   double priceMove = openPrice - currentPrice;

   // Stage 1: Move to breakeven
   if(!g_breakevenReached[posIndex] && priceMove >= requiredMoveForBreakeven)
   {
      double newSL = NormalizeDouble(openPrice, _Digits);
      if(SafeOrderModify(ticket, newSL, tp))
      {
         g_breakevenReached[posIndex] = true;
         g_breakevenPrice[posIndex] = newSL;
         Print("SELL #", ticket, " moved to breakeven at ", newSL);
      }
      return;
   }

   // Stage 2: Wait for pause trigger
   if(g_breakevenReached[posIndex] && !g_nextMoveReached[posIndex])
   {
      double requiredAdditionalMove = g_rangeSize * InpPausePercent / 100.0;
      double additionalMove = priceMove - requiredMoveForBreakeven;

      if(additionalMove >= requiredAdditionalMove)
      {
         g_nextMoveReached[posIndex] = true;
         g_timeframeLevel[posIndex] = 0;
         Print("SELL #", ticket, " ready for management. Method: ",
               (useBelowBaselineMethod ? "Trailing Stop" : "ATR"));
      }
      return;
   }

   // Stage 3: Active management
   if(g_breakevenReached[posIndex] && g_nextMoveReached[posIndex])
   {
      if(useBelowBaselineMethod)
      {
         // Simple trailing stop
         double trailingDistance = InpTrailingStopPoints * _Point;
         double newSL = NormalizeDouble(currentPrice + trailingDistance, _Digits);

         if(newSL < currentSL && newSL < g_breakevenPrice[posIndex])
         {
            if(SafeOrderModify(ticket, newSL, tp))
               Print("SELL #", ticket, " trailing SL updated to ", newSL);
         }
      }
      else
      {
         // ATR method
         ENUM_TIMEFRAMES currentTF = GetCurrentTimeframe(g_timeframeLevel[posIndex]);
         double atrValue = GetATRTrendIndValue(currentTF, 1);

         if(atrValue > 0 && atrValue < currentSL && atrValue < g_breakevenPrice[posIndex])
         {
            double newSL = NormalizeDouble(atrValue, _Digits);
            if(SafeOrderModify(ticket, newSL, tp))
            {
               Print("SELL #", ticket, " ATR SL updated to ", newSL, " (",
                     GetTimeframeName(g_timeframeLevel[posIndex]), ")");

               if(g_timeframeLevel[posIndex] < 5)
                  g_timeframeLevel[posIndex]++;
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
