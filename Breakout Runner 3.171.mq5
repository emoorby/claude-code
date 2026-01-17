//+------------------------------------------------------------------+
//|                                        OpeningRangeBreakout.mq5 |
//|                                                                  |
//|                    Opening Range Breakout Expert Adviser         |
//+------------------------------------------------------------------+
#property copyright "Opening Range Breakout EA"
#property version   "3.2"
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

enum ENUM_MAX_TIMEFRAME
{
   MAX_TF_M1,   // M1
   MAX_TF_M5,   // M5
   MAX_TF_M15,  // M15
   MAX_TF_M30,  // M30
   MAX_TF_H1,   // H1
   MAX_TF_H4,   // H4
   MAX_TF_D1    // D1
};

// Entry Time Settings
input group "=== Entry Time Settings ==="
input int      InpEntryHour    = 16;     // Entry Hour (0-23)
input int      InpEntryMinute  = 30;     // Entry Minute (0-59)

// ATR Range Calculation
input group "=== ATR Range Calculation ==="
input int      InpATRPeriod         = 10;    // ATR Period for Range Calculation
input double   InpATRMultiplier     = 3.0;   // ATR Multiplier for R (default: 3.0)

// Pending Order Deletion Time
input group "=== Pending Order Deletion ==="
input int      InpDeleteOrdersHour   = 23;    // Delete Pending Orders Hour (0-23)
input int      InpDeleteOrdersMinute = 59;    // Delete Pending Orders Minute (0-59)

// Trade Direction
input group "=== Trade Direction ==="
input ENUM_TRADE_DIRECTION InpTradeDirection = TRADE_BOTH; // Trade Direction

// Take Profit
input group "=== Take Profit ==="
input double   InpTakeProfitR = 10.0;  // Take Profit (R multiples)

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
input double   InpBreakevenR           = 2.0;     // Move to Breakeven (R multiples)
input int      InpBreakevenBufferPoints = 5;      // Breakeven Buffer (Points above/below entry)
input double   InpPauseR               = 1.0;     // Pause Before Management (R multiples)
input double   InpBaselineBalance      = 10000.0; // Baseline Balance
input ENUM_MAX_TIMEFRAME InpMaxTimeframe = MAX_TF_D1; // Maximum Timeframe for Progression

// ATR_Trend_Ind Settings - Above Baseline
input group "=== ATR_Trend_Ind Settings (Above Baseline) ==="
input int      InpATRPeriod_AboveBaseline    = 10;   // ATR Period (Above Baseline)
input double   InpATRModifier_AboveBaseline  = 1.0;  // ATR Modifier (Above Baseline)

// Points-Based Trailing - Below Baseline
input group "=== Points-Based Trailing (Below Baseline) ==="
input int      InpBelowBaseline_BreakevenPoints = 50;   // Breakeven Trigger (Points)
input int      InpBelowBaseline_TrailingPoints  = 25;   // Trailing Stop Distance (Points)

// ADX Filter
input group "=== ADX Filter ==="
input bool     InpEnableADXFilter  = true;   // Enable ADX Filter
input int      InpADXPeriod        = 15;     // ADX Period
input double   InpADXLevel         = 20.0;   // Minimum ADX Level

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
bool     g_ordersPlaced = false;      // Flag: orders placed at entry time
int      g_tradesCount = 0;           // Number of trades executed today
int      g_currentDay = 0;            // Current day for daily reset
bool     g_ordersDeletedToday = false; // Flag: pending orders deleted at specified time today
ulong    g_buyStopTicket = 0;         // Buy stop order ticket
ulong    g_sellStopTicket = 0;        // Sell stop order ticket
double   g_R = 0.0;                   // Calculated R value (3 × ATR) in price
int      g_atrHandle = INVALID_HANDLE; // ATR indicator handle for R calculation
int      g_adxHandle = INVALID_HANDLE; // ADX indicator handle

// Position tracking arrays for trade management
ulong    g_positionTickets[100];         // Store up to 100 position tickets
bool     g_breakevenReached[100];        // Breakeven reached flag
bool     g_nextMoveReached[100];         // Next move (pause) reached flag
int      g_timeframeLevel[100];          // Current timeframe level for ATR trailing
double   g_breakevenPrice[100];          // Breakeven price
double   g_initialSL[100];               // Initial stop loss
int      g_positionType[100];            // 1 = BUY, 2 = SELL
datetime g_lastBarTime[100];             // Last bar time for each position's timeframe
bool     g_useBelowBaselineMethod[100];  // Management method locked at position open (true = M1 only, false = timeframe progression)
double   g_lastATRValue[100][7];         // Cached last valid ATR_Trend_Ind value [position][timeframe_level]
int      g_positionCount = 0;            // Number of tracked positions

// ATR Indicator handles for different timeframes - Above Baseline
int      g_atrHandleM1_Above = INVALID_HANDLE;
int      g_atrHandleM5_Above = INVALID_HANDLE;
int      g_atrHandleM15_Above = INVALID_HANDLE;
int      g_atrHandleM30_Above = INVALID_HANDLE;
int      g_atrHandleH1_Above = INVALID_HANDLE;
int      g_atrHandleH4_Above = INVALID_HANDLE;
int      g_atrHandleD1_Above = INVALID_HANDLE;

// ATR Indicator handles for different timeframes - Below Baseline
int      g_atrHandleM1_Below = INVALID_HANDLE;
int      g_atrHandleM5_Below = INVALID_HANDLE;
int      g_atrHandleM15_Below = INVALID_HANDLE;
int      g_atrHandleM30_Below = INVALID_HANDLE;
int      g_atrHandleH1_Below = INVALID_HANDLE;
int      g_atrHandleH4_Below = INVALID_HANDLE;
int      g_atrHandleD1_Below = INVALID_HANDLE;

// Management logging flag
bool     g_lastLoggedMethod = false;      // Last logged method (false = trailing, true = ATR)

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("========================================");
   Print("ATR Breakout EA v3.2 Initialized");
   Print("========================================");
   Print("Entry Time: ", IntegerToString(InpEntryHour), ":",
         StringFormat("%02d", InpEntryMinute));
   Print("R Calculation: ", InpATRMultiplier, " × ATR(", InpATRPeriod, ")");
   Print("Entry: Price ± R/2");
   Print("Stop Loss: Opposite order price");
   Print("Take Profit: ", InpTakeProfitR, "R");
   Print("Trade Direction: ", EnumToString(InpTradeDirection));
   Print("Lot Mode: ", EnumToString(InpLotMode));
   if(InpLotMode == LOT_FIXED)
      Print("Fixed Lot Size: ", InpFixedLotSize);
   else
      Print("Risk Percent: ", InpRiskPercent, "%");
   Print("Max Trades Per Day: ", InpMaxTradesPerDay);
   Print("Magic Number: ", InpMagicNumber);
   Print("========================================");
   Print("Trade Management Settings:");
   Print("Baseline Balance: ", InpBaselineBalance);
   Print("Below Baseline: Points-Based Trailing");
   Print("  Breakeven: ", InpBelowBaseline_BreakevenPoints, " points");
   Print("  Trailing: ", InpBelowBaseline_TrailingPoints, " points");
   Print("At/Above Baseline: ATR Multi-Timeframe");
   Print("  Breakeven: ", InpBreakevenR, "R");
   Print("  Pause: ", InpPauseR, "R");
   Print("  Breakeven Buffer: ", InpBreakevenBufferPoints, " points");
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
   ArrayInitialize(g_lastBarTime, 0);
   ArrayInitialize(g_useBelowBaselineMethod, false);
   ArrayInitialize(g_lastATRValue, 0.0);

   // Create ATR indicator handle for R calculation
   g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create ATR indicator handle");
      return(INIT_FAILED);
   }
   Print("ATR indicator loaded successfully");

   // Create ADX indicator handle if filter is enabled
   if(InpEnableADXFilter)
   {
      g_adxHandle = iADX(_Symbol, PERIOD_CURRENT, InpADXPeriod);
      if(g_adxHandle == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create ADX indicator handle");
         return(INIT_FAILED);
      }
      Print("ADX Filter enabled (Period: ", InpADXPeriod, ", Level: ", InpADXLevel, ")");
   }
   else
   {
      Print("ADX Filter disabled");
   }

   // Create ATR_Trend_Ind indicator handles for all timeframes - Above Baseline only
   // Below Baseline uses points-based trailing, so no indicators needed
   g_atrHandleM1_Above = iCustom(_Symbol, PERIOD_M1, "ATR_Trend_Ind", InpATRPeriod_AboveBaseline, InpATRModifier_AboveBaseline);
   g_atrHandleM5_Above = iCustom(_Symbol, PERIOD_M5, "ATR_Trend_Ind", InpATRPeriod_AboveBaseline, InpATRModifier_AboveBaseline);
   g_atrHandleM15_Above = iCustom(_Symbol, PERIOD_M15, "ATR_Trend_Ind", InpATRPeriod_AboveBaseline, InpATRModifier_AboveBaseline);
   g_atrHandleM30_Above = iCustom(_Symbol, PERIOD_M30, "ATR_Trend_Ind", InpATRPeriod_AboveBaseline, InpATRModifier_AboveBaseline);
   g_atrHandleH1_Above = iCustom(_Symbol, PERIOD_H1, "ATR_Trend_Ind", InpATRPeriod_AboveBaseline, InpATRModifier_AboveBaseline);
   g_atrHandleH4_Above = iCustom(_Symbol, PERIOD_H4, "ATR_Trend_Ind", InpATRPeriod_AboveBaseline, InpATRModifier_AboveBaseline);
   g_atrHandleD1_Above = iCustom(_Symbol, PERIOD_D1, "ATR_Trend_Ind", InpATRPeriod_AboveBaseline, InpATRModifier_AboveBaseline);

   int failedHandles = 0;
   if(g_atrHandleM1_Above == INVALID_HANDLE) failedHandles++;
   if(g_atrHandleM5_Above == INVALID_HANDLE) failedHandles++;
   if(g_atrHandleM15_Above == INVALID_HANDLE) failedHandles++;
   if(g_atrHandleM30_Above == INVALID_HANDLE) failedHandles++;
   if(g_atrHandleH1_Above == INVALID_HANDLE) failedHandles++;
   if(g_atrHandleH4_Above == INVALID_HANDLE) failedHandles++;
   if(g_atrHandleD1_Above == INVALID_HANDLE) failedHandles++;

   if(failedHandles > 0)
   {
      Print("WARNING: Failed to create ", failedHandles, " ATR_Trend_Ind indicator handle(s)");
      Print("ATR trade management will use fallback method for failed timeframes");
   }
   else
   {
      Print("ATR_Trend_Ind indicators loaded successfully for Above Baseline management");
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release ATR indicator handles - Above Baseline only
   if(g_atrHandleM1_Above != INVALID_HANDLE) IndicatorRelease(g_atrHandleM1_Above);
   if(g_atrHandleM5_Above != INVALID_HANDLE) IndicatorRelease(g_atrHandleM5_Above);
   if(g_atrHandleM15_Above != INVALID_HANDLE) IndicatorRelease(g_atrHandleM15_Above);
   if(g_atrHandleM30_Above != INVALID_HANDLE) IndicatorRelease(g_atrHandleM30_Above);
   if(g_atrHandleH1_Above != INVALID_HANDLE) IndicatorRelease(g_atrHandleH1_Above);
   if(g_atrHandleH4_Above != INVALID_HANDLE) IndicatorRelease(g_atrHandleH4_Above);
   if(g_atrHandleD1_Above != INVALID_HANDLE) IndicatorRelease(g_atrHandleD1_Above);

   // Release ATR indicator handle
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);

   // Release ADX indicator handle
   if(g_adxHandle != INVALID_HANDLE) IndicatorRelease(g_adxHandle);

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

   // Check if it's time to delete pending orders
   CheckPendingOrderDeletionTime();

   // Check if it's entry time and place orders
   if(!g_ordersPlaced && g_tradesCount < InpMaxTradesPerDay)
   {
      CheckEntryTime();
   }

   // Check pending orders and run ADX filter before they trigger
   if(g_ordersPlaced && InpEnableADXFilter)
   {
      CheckPendingOrdersBeforeTrigger();
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
//| Check if it's entry time and calculate R                         |
//+------------------------------------------------------------------+
void CheckEntryTime()
{
   MqlDateTime time_struct;
   TimeCurrent(time_struct);

   // Check if current bar opened at entry time
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   MqlDateTime barTime_struct;
   TimeToStruct(currentBarTime, barTime_struct);

   // Only execute at the open of the bar at entry time
   if(barTime_struct.hour != InpEntryHour || barTime_struct.min != InpEntryMinute)
      return;

   // Calculate R using ATR
   double atrBuffer[1];
   if(CopyBuffer(g_atrHandle, 0, 0, 1, atrBuffer) != 1)
   {
      Print("ERROR: Failed to get ATR value for R calculation");
      return;
   }

   g_R = InpATRMultiplier * atrBuffer[0];
   double R_points = g_R / _Point;

   Print("========================================");
   Print("ENTRY TIME REACHED: ", InpEntryHour, ":", StringFormat("%02d", InpEntryMinute));
   Print("ATR Value: ", atrBuffer[0]);
   Print("R Calculated: ", g_R, " (", R_points, " points)");
   Print("R = ", InpATRMultiplier, " × ATR(", InpATRPeriod, ")");
   Print("========================================");

   // Place orders
   PlaceStopOrders();
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
      double risk = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;

      double ticksize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickvalue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double lotstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double minvolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxvolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double volumelimit = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);

      // Ensure stopLossDistance is positive
      if(stopLossDistance < 0) stopLossDistance = stopLossDistance * -1;

      double moneyPerLotstep = stopLossDistance / ticksize * tickvalue * lotstep;
      lotSize = MathFloor(risk / moneyPerLotstep) * lotstep;

      // Apply volume limits
      if(volumelimit != 0) lotSize = MathMin(lotSize, volumelimit);
      if(maxvolume != 0) lotSize = MathMin(lotSize, maxvolume);
      if(minvolume != 0) lotSize = MathMax(lotSize, minvolume);
      lotSize = NormalizeDouble(lotSize, 2);

      Print("Lot size calculation: RISK-BASED mode");
      Print("  Account Balance: ", AccountInfoDouble(ACCOUNT_BALANCE));
      Print("  Risk Amount: ", risk, " (", InpRiskPercent, "%)");
      Print("  Tick Size: ", ticksize);
      Print("  Tick Value: ", tickvalue);
      Print("  Lot Step: ", lotstep);
      Print("  Stop Loss Distance: ", stopLossDistance, " (", stopLossDistance/ticksize, " ticks)");
      Print("  Money Per Lot Step: ", moneyPerLotstep);
      Print("  Calculated Lot Size: ", lotSize, " (Min: ", minvolume, " Max: ", maxvolume, " Step: ", lotstep, ")");
   }

   return lotSize;
}

//+------------------------------------------------------------------+
//| Place buy and sell stop orders                                   |
//+------------------------------------------------------------------+
void PlaceStopOrders()
{
   Print("========================================");
   Print("Placing stop orders using R-based calculation...");

   // Get current market prices
   double currentPrice = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) + SymbolInfoDouble(_Symbol, SYMBOL_BID)) / 2.0;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   Print("Current Price (mid): ", currentPrice);
   Print("Ask: ", ask, " | Bid: ", bid);
   Print("R value: ", g_R, " (", (g_R/_Point), " points)");

   // Calculate order prices
   double halfR = g_R / 2.0;
   double buyStopPrice = NormalizeDouble(currentPrice + halfR, _Digits);
   double sellStopPrice = NormalizeDouble(currentPrice - halfR, _Digits);

   Print("BUY STOP Entry: ", buyStopPrice, " (Price + R/2)");
   Print("SELL STOP Entry: ", sellStopPrice, " (Price - R/2)");
   Print("SL Distance: R (", g_R, ")");
   Print("TP Distance: ", InpTakeProfitR, "R (", (InpTakeProfitR * g_R), ")");

   // Calculate lot size based on R
   double lotSize = CalculateLotSize(g_R);

   if(lotSize <= 0)
   {
      Print("ERROR: Invalid lot size calculated: ", lotSize);
      Print("========================================");
      return;
   }

   MqlTradeRequest request;
   MqlTradeResult result;

   // Place Buy Stop Order
   if(InpTradeDirection == TRADE_BOTH || InpTradeDirection == TRADE_BUY_ONLY)
   {
      ZeroMemory(request);
      ZeroMemory(result);

      request.action = TRADE_ACTION_PENDING;
      request.symbol = _Symbol;
      request.volume = lotSize;
      request.magic = InpMagicNumber;
      request.comment = InpTradeComment;
      request.type = ORDER_TYPE_BUY_STOP;
      request.price = buyStopPrice;
      request.sl = sellStopPrice;  // SL = opposite order price
      request.tp = NormalizeDouble(buyStopPrice + (InpTakeProfitR * g_R), _Digits);
      request.deviation = 10;
      request.type_filling = ORDER_FILLING_IOC;

      Print("Placing BUY STOP order:");
      Print("  Entry: ", request.price);
      Print("  SL: ", request.sl, " (SELL STOP price)");
      Print("  TP: ", request.tp, " (Entry + ", InpTakeProfitR, "R)");
      Print("  Lot Size: ", request.volume);

      if(OrderSend(request, result))
      {
         if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
         {
            g_buyStopTicket = result.order;
            Print("SUCCESS: Buy Stop #", g_buyStopTicket, " placed");
         }
         else
         {
            Print("ERROR: Buy Stop failed - ", result.retcode, ": ", GetRetcodeDescription(result.retcode));
         }
      }
      else
      {
         Print("ERROR: OrderSend failed for Buy Stop - ", GetLastError());
      }
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
      request.price = sellStopPrice;
      request.sl = buyStopPrice;  // SL = opposite order price
      request.tp = NormalizeDouble(sellStopPrice - (InpTakeProfitR * g_R), _Digits);
      request.deviation = 10;
      request.type_filling = ORDER_FILLING_IOC;

      Print("Placing SELL STOP order:");
      Print("  Entry: ", request.price);
      Print("  SL: ", request.sl, " (BUY STOP price)");
      Print("  TP: ", request.tp, " (Entry - ", InpTakeProfitR, "R)");
      Print("  Lot Size: ", request.volume);

      if(OrderSend(request, result))
      {
         if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
         {
            g_sellStopTicket = result.order;
            Print("SUCCESS: Sell Stop #", g_sellStopTicket, " placed");
         }
         else
         {
            Print("ERROR: Sell Stop failed - ", result.retcode, ": ", GetRetcodeDescription(result.retcode));
         }
      }
      else
      {
         Print("ERROR: OrderSend failed for Sell Stop - ", GetLastError());
      }
   }

   g_ordersPlaced = true;
   Print("========================================");
}

//+------------------------------------------------------------------+
//| Check pending orders on every M1 bar and run filter              |
//+------------------------------------------------------------------+
void CheckPendingOrdersBeforeTrigger()
{
   // Only run filter if we have pending orders
   bool hasPendingOrders = (g_buyStopTicket > 0 || g_sellStopTicket > 0);
   if(!hasPendingOrders)
      return;

   // Get current ADX value
   double adxBuffer[1];
   if(CopyBuffer(g_adxHandle, 0, 0, 1, adxBuffer) != 1)
   {
      Print("ERROR: Failed to get ADX value for filter check");
      return;
   }

   double currentADX = adxBuffer[0];
   bool filterPassed = (currentADX >= InpADXLevel);

   Print("ADX Filter Check: ADX = ", DoubleToString(currentADX, 2),
         " | Required: ", InpADXLevel, " | ", (filterPassed ? "PASSED" : "FAILED"));

   if(!filterPassed)
   {
      // ADX too low - delete pending orders
      Print("ADX below threshold - Deleting pending orders");

      // Delete Buy Stop if exists
      if(g_buyStopTicket > 0)
      {
         MqlTradeRequest request;
         MqlTradeResult result;
         ZeroMemory(request);
         ZeroMemory(result);

         request.action = TRADE_ACTION_REMOVE;
         request.order = g_buyStopTicket;

         if(OrderSend(request, result) && result.retcode == TRADE_RETCODE_DONE)
         {
            Print("BUY STOP #", g_buyStopTicket, " deleted (ADX filter)");
            g_buyStopTicket = 0;
         }
      }

      // Delete Sell Stop if exists
      if(g_sellStopTicket > 0)
      {
         MqlTradeRequest request;
         MqlTradeResult result;
         ZeroMemory(request);
         ZeroMemory(result);

         request.action = TRADE_ACTION_REMOVE;
         request.order = g_sellStopTicket;

         if(OrderSend(request, result) && result.retcode == TRADE_RETCODE_DONE)
         {
            Print("SELL STOP #", g_sellStopTicket, " deleted (ADX filter)");
            g_sellStopTicket = 0;
         }
      }
   }
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
         // Order not found in pending orders, check if it became a position
         // Only check for active position, NOT history (to avoid false triggers when position closes)
         if(PositionSelectByTicket(g_buyStopTicket))
         {
            Print("========================================");
            Print("BUY STOP order triggered! Ticket: ", g_buyStopTicket);
            buyOrderTriggered = true;
            g_buyStopTicket = 0;
         }
      }
   }

   // Check Sell Stop Order
   if(g_sellStopTicket > 0)
   {
      if(!OrderSelect(g_sellStopTicket))
      {
         // Order not found in pending orders, check if it became a position
         // Only check for active position, NOT history (to avoid false triggers when position closes)
         if(PositionSelectByTicket(g_sellStopTicket))
         {
            Print("========================================");
            Print("SELL STOP order triggered! Ticket: ", g_sellStopTicket);
            sellOrderTriggered = true;
            g_sellStopTicket = 0;
         }
      }
   }

   // Increment trade count for triggered orders
   // Note: Filter is now checked BEFORE orders trigger (see CheckPendingOrdersBeforeTrigger)
   // so any order that triggers has already passed the filter
   if(buyOrderTriggered || sellOrderTriggered)
   {
      g_tradesCount++;
      Print("Trade count increased to: ", g_tradesCount, "/", InpMaxTradesPerDay);
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

      // Reset pending order deletion flag for the new day
      g_ordersDeletedToday = false;

      // PRESERVE STATE OF OPEN POSITIONS before resetting
      // Save current position states temporarily
      ulong savedTickets[100];
      bool savedBreakevenReached[100];
      bool savedNextMoveReached[100];
      int savedTimeframeLevel[100];
      double savedBreakevenPrice[100];
      double savedInitialSL[100];
      int savedPositionType[100];
      datetime savedLastBarTime[100];
      bool savedUseBelowBaselineMethod[100];
      double savedLastATRValue[100][7];
      int savedPositionCount = 0;

      // Copy existing open position states
      for(int i = 0; i < g_positionCount; i++)
      {
         // Check if this position is still open
         if(PositionSelectByTicket(g_positionTickets[i]))
         {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            {
               // Position is still open - preserve its state
               savedTickets[savedPositionCount] = g_positionTickets[i];
               savedBreakevenReached[savedPositionCount] = g_breakevenReached[i];
               savedNextMoveReached[savedPositionCount] = g_nextMoveReached[i];
               savedTimeframeLevel[savedPositionCount] = g_timeframeLevel[i];
               savedBreakevenPrice[savedPositionCount] = g_breakevenPrice[i];
               savedInitialSL[savedPositionCount] = g_initialSL[i];
               savedPositionType[savedPositionCount] = g_positionType[i];
               savedLastBarTime[savedPositionCount] = g_lastBarTime[i];
               savedUseBelowBaselineMethod[savedPositionCount] = g_useBelowBaselineMethod[i];
               // Copy all cached ATR values for all timeframes
               for(int tf = 0; tf < 7; tf++)
                  savedLastATRValue[savedPositionCount][tf] = g_lastATRValue[i][tf];
               savedPositionCount++;

               Print("Preserving state for position #", g_positionTickets[i],
                     " (Timeframe: ", GetTimeframeName(g_timeframeLevel[i]),
                     ", Breakeven: ", (g_breakevenReached[i] ? "Yes" : "No"),
                     ", ATR Management: ", (g_nextMoveReached[i] ? "Active" : "Pending"),
                     ", Method: ", (g_useBelowBaselineMethod[i] ? "M1 Only" : "Timeframe Progression"), ")");
            }
         }
      }

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
      ArrayInitialize(g_lastBarTime, 0);
      ArrayInitialize(g_useBelowBaselineMethod, false);
      ArrayInitialize(g_lastATRValue, 0.0);

      // RESTORE PRESERVED POSITION STATES
      // Restore saved position states back to the arrays
      for(int i = 0; i < savedPositionCount; i++)
      {
         g_positionTickets[i] = savedTickets[i];
         g_breakevenReached[i] = savedBreakevenReached[i];
         g_nextMoveReached[i] = savedNextMoveReached[i];
         g_timeframeLevel[i] = savedTimeframeLevel[i];
         g_breakevenPrice[i] = savedBreakevenPrice[i];
         g_initialSL[i] = savedInitialSL[i];
         g_positionType[i] = savedPositionType[i];
         g_lastBarTime[i] = savedLastBarTime[i];
         g_useBelowBaselineMethod[i] = savedUseBelowBaselineMethod[i];
         // Restore all cached ATR values for all timeframes
         for(int tf = 0; tf < 7; tf++)
            g_lastATRValue[i][tf] = savedLastATRValue[i][tf];
      }
      g_positionCount = savedPositionCount;

      // Reset logging flag
      g_lastLoggedMethod = false;

      Print("Daily reset complete");
      Print("Trade count reset to: 0");
      Print("Range values cleared");
      if(savedPositionCount > 0)
         Print("Position states preserved: ", savedPositionCount, " open position(s) will continue management");
      else
         Print("No open positions to preserve");
      Print("========================================");
   }
}

//+------------------------------------------------------------------+
//| Check and delete pending orders at specified time                |
//+------------------------------------------------------------------+
void CheckPendingOrderDeletionTime()
{
   // Check if orders have already been deleted today
   if(g_ordersDeletedToday)
      return;

   MqlDateTime time_struct;
   TimeCurrent(time_struct);

   // Calculate current time in minutes
   int currentMinutes = time_struct.hour * 60 + time_struct.min;
   int deleteTimeMinutes = InpDeleteOrdersHour * 60 + InpDeleteOrdersMinute;

   // Check if current time has reached or passed the deletion time
   if(currentMinutes >= deleteTimeMinutes)
   {
      // Delete any remaining pending orders
      int deletedCount = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(OrderSelect(ticket))
         {
            if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
               OrderGetInteger(ORDER_MAGIC) == InpMagicNumber)
            {
               MqlTradeRequest request;
               MqlTradeResult result;
               ZeroMemory(request);
               ZeroMemory(result);

               request.action = TRADE_ACTION_REMOVE;
               request.order = ticket;

               if(OrderSend(request, result))
               {
                  if(result.retcode == TRADE_RETCODE_DONE)
                  {
                     deletedCount++;
                     Print("Deleted pending order #", ticket, " at ", time_struct.hour, ":",
                           (time_struct.min < 10 ? "0" : ""), time_struct.min);
                  }
               }
            }
         }
      }

      if(deletedCount > 0)
      {
         Print("========================================");
         Print("PENDING ORDER DELETION TIME REACHED");
         Print("Deleted ", deletedCount, " pending order(s) at ", InpDeleteOrdersHour, ":",
               (InpDeleteOrdersMinute < 10 ? "0" : ""), InpDeleteOrdersMinute);
         Print("========================================");
      }

      // Mark orders as deleted for today
      g_ordersDeletedToday = true;
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
   datetime tempLastBarTime[100];
   bool tempUseBelowBaselineMethod[100];
   double tempLastATRValue[100][7];
   int tempCount = 0;

   // Initialize temporary arrays
   ArrayInitialize(tempTickets, 0);
   ArrayInitialize(tempBreakevenReached, false);
   ArrayInitialize(tempNextMoveReached, false);
   ArrayInitialize(tempTimeframeLevel, 0);
   ArrayInitialize(tempBreakevenPrice, 0.0);
   ArrayInitialize(tempInitialSL, 0.0);
   ArrayInitialize(tempType, 0);
   ArrayInitialize(tempLastBarTime, 0);
   ArrayInitialize(tempUseBelowBaselineMethod, false);
   ArrayInitialize(tempLastATRValue, 0.0);

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
                  tempLastBarTime[tempCount] = g_lastBarTime[existingIndex];
                  tempUseBelowBaselineMethod[tempCount] = g_useBelowBaselineMethod[existingIndex];
                  // Preserve cached ATR values for all timeframes
                  for(int tf = 0; tf < 7; tf++)
                     tempLastATRValue[tempCount][tf] = g_lastATRValue[existingIndex][tf];
               }
               else
               {
                  // New position - initialize with default values
                  // LOCK IN management method based on CURRENT balance at position opening
                  double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
                  bool useBelowBaselineMethod = (currentBalance < InpBaselineBalance);

                  tempBreakevenReached[tempCount] = false;
                  tempNextMoveReached[tempCount] = false;
                  tempTimeframeLevel[tempCount] = 0;
                  tempBreakevenPrice[tempCount] = 0.0;
                  tempInitialSL[tempCount] = PositionGetDouble(POSITION_SL);
                  tempType[tempCount] = (posType == POSITION_TYPE_BUY) ? 1 : 2;
                  tempLastBarTime[tempCount] = 0;
                  tempUseBelowBaselineMethod[tempCount] = useBelowBaselineMethod;
                  // New position starts with no cached ATR values (already initialized to 0)

                  Print("New position #", ticket, " detected. Balance: ", currentBalance,
                        " | Baseline: ", InpBaselineBalance,
                        " | Locked Management Method: ", (useBelowBaselineMethod ? "M1 Only" : "Timeframe Progression"));
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
      g_lastBarTime[k] = tempLastBarTime[k];
      g_useBelowBaselineMethod[k] = tempUseBelowBaselineMethod[k];
      // Copy cached ATR values for all timeframes
      for(int tf = 0; tf < 7; tf++)
         g_lastATRValue[k][tf] = tempLastATRValue[k][tf];
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
double GetATRTrendIndValue(ENUM_TIMEFRAMES timeframe, ENUM_POSITION_TYPE posType, int posIndex)
{
   double value[];
   ArraySetAsSeries(value, true);

   int timeframeLevel = GetTimeframeLevel(timeframe);

   // Determine which handle set to use based on the position's locked-in method
   bool useBelowBaselineMethod = g_useBelowBaselineMethod[posIndex];

   // Select the correct handle based on timeframe and baseline method
   int atrHandle = INVALID_HANDLE;
   if(useBelowBaselineMethod)
   {
      // Use Below Baseline handles
      switch(timeframe)
      {
         case PERIOD_M1:  atrHandle = g_atrHandleM1_Below;  break;
         case PERIOD_M5:  atrHandle = g_atrHandleM5_Below;  break;
         case PERIOD_M15: atrHandle = g_atrHandleM15_Below; break;
         case PERIOD_M30: atrHandle = g_atrHandleM30_Below; break;
         case PERIOD_H1:  atrHandle = g_atrHandleH1_Below;  break;
         case PERIOD_H4:  atrHandle = g_atrHandleH4_Below;  break;
         case PERIOD_D1:  atrHandle = g_atrHandleD1_Below;  break;
         default:         atrHandle = INVALID_HANDLE; break;
      }
   }
   else
   {
      // Use Above Baseline handles
      switch(timeframe)
      {
         case PERIOD_M1:  atrHandle = g_atrHandleM1_Above;  break;
         case PERIOD_M5:  atrHandle = g_atrHandleM5_Above;  break;
         case PERIOD_M15: atrHandle = g_atrHandleM15_Above; break;
         case PERIOD_M30: atrHandle = g_atrHandleM30_Above; break;
         case PERIOD_H1:  atrHandle = g_atrHandleH1_Above;  break;
         case PERIOD_H4:  atrHandle = g_atrHandleH4_Above;  break;
         case PERIOD_D1:  atrHandle = g_atrHandleD1_Above;  break;
         default:         atrHandle = INVALID_HANDLE; break;
      }
   }

   // Try to get values from ATR_Trend_Ind indicator for this timeframe
   if(atrHandle != INVALID_HANDLE)
   {
      // ATR_Trend_Ind has 4 buffers:
      // Buffer 0: ATR_UP_Buffer (arrows, only on trend changes)
      // Buffer 1: ATR_DN_Buffer (arrows, only on trend changes)
      // Buffer 2: ATR_UP_Line_Buffer (continuous line - SELL stops, above price)
      // Buffer 3: ATR_DN_Line_Buffer (continuous line - BUY stops, below price)

      // Select the correct buffer based on position type
      int targetBuffer = (posType == POSITION_TYPE_BUY) ? 3 : 2;

      // Look back through bars to find the last valid value
      // The indicator only updates when the value changes, so we need to check multiple bars
      double values[];
      ArraySetAsSeries(values, true);

      int lookbackBars = 50;  // Look back up to 50 bars
      int copiedBars = CopyBuffer(atrHandle, targetBuffer, 0, lookbackBars, values);
      if(copiedBars > 0)
      {
         // Search through bars from most recent to oldest (use actual copied count, not requested count)
         for(int i = 0; i < copiedBars; i++)
         {
            // Check if value is valid (non-zero and reasonable price range)
            if(values[i] > 0 && values[i] > 100 && values[i] < 100000)
            {
               double currentPrice = (posType == POSITION_TYPE_BUY) ?
                                     SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                                     SymbolInfoDouble(_Symbol, SYMBOL_ASK);

               // Verify the value makes sense for the position type
               bool validForBuy = (posType == POSITION_TYPE_BUY && values[i] < currentPrice);
               bool validForSell = (posType == POSITION_TYPE_SELL && values[i] > currentPrice);

               if(validForBuy || validForSell)
               {
                  // Cache this valid value
                  g_lastATRValue[posIndex][timeframeLevel] = values[i];

                  if(i == 0)
                  {
                     Print("Found & cached ", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                           " stop price ", values[i], " in buffer ", targetBuffer, " bar 0 on ",
                           GetTimeframeName(timeframeLevel));
                  }
                  else
                  {
                     Print("Found & cached ", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                           " stop price ", values[i], " in buffer ", targetBuffer, " bar ", i, " (lookback) on ",
                           GetTimeframeName(timeframeLevel));
                  }

                  return values[i];
               }
            }
         }
      }

      // No valid value found in indicator - check if we have a cached value
      if(g_lastATRValue[posIndex][timeframeLevel] > 0)
      {
         Print("ATR_Trend_Ind buffer empty, using cached value: ", g_lastATRValue[posIndex][timeframeLevel],
               " on ", GetTimeframeName(timeframeLevel));
         return g_lastATRValue[posIndex][timeframeLevel];
      }

      Print("WARNING: No valid price level found in ATR_Trend_Ind buffers and no cached value on ",
            GetTimeframeName(timeframeLevel));
   }
   else
   {
      Print("ERROR: ATR_Trend_Ind handle invalid for ", GetTimeframeName(timeframeLevel));
   }

   // Fallback: use current price with ATR-based offset
   double currentPrice = (posType == POSITION_TYPE_BUY) ?
                         SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Below baseline positions use points-based trailing, so always use Above Baseline ATR parameters for fallback
   int atrPeriod = InpATRPeriod_AboveBaseline;
   double atrModifier = InpATRModifier_AboveBaseline;

   int atrFallbackHandle = iATR(_Symbol, timeframe, atrPeriod);
   if(atrFallbackHandle != INVALID_HANDLE)
   {
      double atrBuffer[1];
      if(CopyBuffer(atrFallbackHandle, 0, 0, 1, atrBuffer) == 1)
      {
         IndicatorRelease(atrFallbackHandle);
         if(atrBuffer[0] > 0)
         {
            double atrValue = atrBuffer[0] * atrModifier;
            double stopPrice;

            if(posType == POSITION_TYPE_BUY)
            {
               // For BUY: Stop loss = Current Price - ATR × Multiplier
               stopPrice = currentPrice - atrValue;
            }
            else // SELL
            {
               // For SELL: Stop loss = Current Price + ATR × Multiplier
               stopPrice = currentPrice + atrValue;
            }

            Print("Using fallback ATR-based stop: ", stopPrice,
                  " (Current: ", currentPrice, ", ATR: ", atrValue,
                  ", Method: ", (useBelowBaselineMethod ? "Below Baseline" : "Above Baseline"), ") on ",
                  GetTimeframeName(GetTimeframeLevel(timeframe)));
            return stopPrice;
         }
      }
      IndicatorRelease(atrFallbackHandle);
   }

   Print("ERROR: No ATR value available for ", GetTimeframeName(GetTimeframeLevel(timeframe)));
   return 0;
}

//+------------------------------------------------------------------+
//| Get current timeframe based on level                             |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetCurrentTimeframe(int level)
{
   switch(level)
   {
      case 0: return PERIOD_M1;
      case 1: return PERIOD_M5;
      case 2: return PERIOD_M15;
      case 3: return PERIOD_M30;
      case 4: return PERIOD_H1;
      case 5: return PERIOD_H4;
      case 6: return PERIOD_D1;
      default: return PERIOD_M1;
   }
}

//+------------------------------------------------------------------+
//| Get timeframe level                                              |
//+------------------------------------------------------------------+
int GetTimeframeLevel(ENUM_TIMEFRAMES timeframe)
{
   switch(timeframe)
   {
      case PERIOD_M1: return 0;
      case PERIOD_M5: return 1;
      case PERIOD_M15: return 2;
      case PERIOD_M30: return 3;
      case PERIOD_H1: return 4;
      case PERIOD_H4: return 5;
      case PERIOD_D1: return 6;
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
      case 0: return "M1";
      case 1: return "M5";
      case 2: return "M15";
      case 3: return "M30";
      case 4: return "H1";
      case 5: return "H4";
      case 6: return "D1";
      default: return "M1";
   }
}

//+------------------------------------------------------------------+
//| Get maximum timeframe level from user input                      |
//+------------------------------------------------------------------+
int GetMaxTimeframeLevel()
{
   switch(InpMaxTimeframe)
   {
      case MAX_TF_M1:  return 0;
      case MAX_TF_M5:  return 1;
      case MAX_TF_M15: return 2;
      case MAX_TF_M30: return 3;
      case MAX_TF_H1:  return 4;
      case MAX_TF_H4:  return 5;
      case MAX_TF_D1:  return 6;
      default:         return 6;  // Default to D1
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
   int previousPositionCount = g_positionCount;
   UpdatePositionDataArrays();

   // Only log when position count changes
   if(g_positionCount != previousPositionCount && g_positionCount > 0)
   {
      double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      Print("Managing ", g_positionCount, " positions. Current Balance: ", currentBalance,
            " (Baseline: ", InpBaselineBalance, ")");
      Print("Note: Each position uses the management method locked in when it was opened");
   }

   // Manage each position using its LOCKED-IN management method
   for(int i = 0; i < g_positionCount; i++)
   {
      ulong ticket = g_positionTickets[i];
      if(PositionSelectByTicket(ticket))
      {
         // Use the management method that was locked in when this position was opened
         bool positionUseBelowBaselineMethod = g_useBelowBaselineMethod[i];

         if(g_positionType[i] == 1) // BUY
            ManageBuyPosition(ticket, i, positionUseBelowBaselineMethod);
         else if(g_positionType[i] == 2) // SELL
            ManageSellPosition(ticket, i, positionUseBelowBaselineMethod);
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

   if(useBelowBaselineMethod)
   {
      // Below Baseline: Points-Based Trailing
      double priceMove = currentPrice - openPrice;
      double priceMovePoints = priceMove / _Point;

      // Stage 1: Move to breakeven when price moves specified points
      if(!g_breakevenReached[posIndex] && priceMovePoints >= InpBelowBaseline_BreakevenPoints)
      {
         // Apply buffer above entry for buy orders
         double bufferPrice = InpBreakevenBufferPoints * _Point;
         double newSL = NormalizeDouble(openPrice + bufferPrice, _Digits);

         // Validate new SL meets broker's minimum stop level requirement
         long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
         double minStopDistance = stopLevel * _Point;
         double actualDistance = currentPrice - newSL;

         if(actualDistance < minStopDistance)
         {
            Print("BUY #", ticket, " breakeven move skipped: SL too close to current price");
            Print("  Required distance: ", stopLevel, " points (", minStopDistance, ")");
            Print("  Actual distance: ", (actualDistance / _Point), " points (", actualDistance, ")");
            Print("  Will retry when price moves further");
            return;
         }

         if(SafeOrderModify(ticket, newSL, tp))
         {
            g_breakevenReached[posIndex] = true;
            g_breakevenPrice[posIndex] = newSL;
            Print("BUY #", ticket, " moved to breakeven+", InpBreakevenBufferPoints, " at ", newSL,
                  " (", priceMovePoints, " points move)");
         }
         return;
      }

      // Stage 2: Trailing stop (starts immediately after breakeven)
      if(g_breakevenReached[posIndex])
      {
         // Calculate trailing SL: currentPrice - trailing distance
         double trailingDistance = InpBelowBaseline_TrailingPoints * _Point;
         double newSL = NormalizeDouble(currentPrice - trailingDistance, _Digits);

         // Only update if new SL is better than current SL and above breakeven
         if(newSL > currentSL && newSL > g_breakevenPrice[posIndex])
         {
            if(SafeOrderModify(ticket, newSL, tp))
            {
               Print("BUY #", ticket, " trailing SL updated from ", currentSL, " to ", newSL,
                     " (trailing ", InpBelowBaseline_TrailingPoints, " points from ", currentPrice, ")");
            }
         }
      }
   }
   else
   {
      // Above Baseline: ATR Multi-Timeframe Method
      double requiredMoveForBreakeven = g_rangeSize * InpBreakevenPercent / 100.0;
      double priceMove = currentPrice - openPrice;

      // Stage 1: Move to breakeven
      if(!g_breakevenReached[posIndex] && priceMove >= requiredMoveForBreakeven)
      {
         // Apply buffer above entry for buy orders
         double bufferPrice = InpBreakevenBufferPoints * _Point;
         double newSL = NormalizeDouble(openPrice + bufferPrice, _Digits);

         // Validate new SL meets broker's minimum stop level requirement
         long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
         double minStopDistance = stopLevel * _Point;
         double actualDistance = currentPrice - newSL;

         if(actualDistance < minStopDistance)
         {
            Print("BUY #", ticket, " breakeven move skipped: SL too close to current price");
            Print("  Required distance: ", stopLevel, " points (", minStopDistance, ")");
            Print("  Actual distance: ", (actualDistance / _Point), " points (", actualDistance, ")");
            Print("  Will retry when price moves further");
            return;
         }

         if(SafeOrderModify(ticket, newSL, tp))
         {
            g_breakevenReached[posIndex] = true;
            g_breakevenPrice[posIndex] = newSL;
            Print("BUY #", ticket, " moved to breakeven+", InpBreakevenBufferPoints, " at ", newSL);
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
            g_timeframeLevel[posIndex] = 0;  // Start with M1
            g_lastBarTime[posIndex] = 0;

            Print("BUY #", ticket, " ready for ATR management (Multi-Timeframe progression)");
         }
         return;
      }

      // Stage 3: Active ATR management with timeframe progression
      if(g_breakevenReached[posIndex] && g_nextMoveReached[posIndex])
      {
         // ATR method with timeframe progression (at/above baseline)
         ENUM_TIMEFRAMES currentTF = GetCurrentTimeframe(g_timeframeLevel[posIndex]);

         // Check if new bar has formed on current timeframe
         datetime currentBarTime = iTime(_Symbol, currentTF, 0);

         // If lastBarTime is 0 (initial state) or different from current, we have a new bar
         if(g_lastBarTime[posIndex] != 0 && currentBarTime == g_lastBarTime[posIndex])
            return;  // No new bar yet, skip this tick

         // Update last bar time
         g_lastBarTime[posIndex] = currentBarTime;

         double atrStopPrice = GetATRTrendIndValue(currentTF, POSITION_TYPE_BUY, posIndex);

         // Log detailed debug info with ATR_Trend_Ind value
         Print("BUY #", ticket, " TF ATR_Trend_Ind Check | Level: ", g_timeframeLevel[posIndex],
               " | TF: ", GetTimeframeName(g_timeframeLevel[posIndex]),
               " | Bar: ", TimeToString(currentBarTime),
               " | ATR_Trend_Ind Stop: ", atrStopPrice, " | Current SL: ", currentSL,
               " | Breakeven: ", g_breakevenPrice[posIndex],
               " | Price: ", currentPrice, " | Open: ", openPrice);

         if(atrStopPrice > 0 && atrStopPrice > currentSL && atrStopPrice > g_breakevenPrice[posIndex])
         {
            double newSL = NormalizeDouble(atrStopPrice, _Digits);
            if(SafeOrderModify(ticket, newSL, tp))
            {
               Print("BUY #", ticket, " ATR_Trend_Ind SL updated from ", currentSL, " to ", newSL, " (",
                     GetTimeframeName(g_timeframeLevel[posIndex]), ")");

               // Check if we should progress to next timeframe
               int maxLevel = GetMaxTimeframeLevel();
               if(g_timeframeLevel[posIndex] < maxLevel)
               {
                  g_timeframeLevel[posIndex]++;
                  // Reset bar time to 0 to wait for next bar on new timeframe
                  g_lastBarTime[posIndex] = 0;
                  Print("BUY #", ticket, " progressed to ",
                        GetTimeframeName(g_timeframeLevel[posIndex]), " timeframe");
               }
               else if(g_timeframeLevel[posIndex] == maxLevel)
               {
                  Print("BUY #", ticket, " at maximum timeframe (",
                        GetTimeframeName(maxLevel), ") - no further progression");
               }
            }
            else
            {
               Print("BUY #", ticket, " Failed to update SL to ", newSL, " on ",
                     GetTimeframeName(g_timeframeLevel[posIndex]));
            }
         }
         else
         {
            if(atrStopPrice <= 0)
               Print("BUY #", ticket, " ATR_Trend_Ind stop price invalid: ", atrStopPrice, " on ",
                     GetTimeframeName(g_timeframeLevel[posIndex]));
            else if(atrStopPrice <= currentSL)
               Print("BUY #", ticket, " ATR_Trend_Ind stop (", atrStopPrice, ") not > Current SL (", currentSL, ") on ",
                     GetTimeframeName(g_timeframeLevel[posIndex]));
            else if(atrStopPrice <= g_breakevenPrice[posIndex])
               Print("BUY #", ticket, " ATR_Trend_Ind stop (", atrStopPrice, ") not > Breakeven (", g_breakevenPrice[posIndex], ") on ",
                     GetTimeframeName(g_timeframeLevel[posIndex]));
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

   if(useBelowBaselineMethod)
   {
      // Below Baseline: Points-Based Trailing
      double priceMove = openPrice - currentPrice;
      double priceMovePoints = priceMove / _Point;

      // Stage 1: Move to breakeven when price moves specified points
      if(!g_breakevenReached[posIndex] && priceMovePoints >= InpBelowBaseline_BreakevenPoints)
      {
         // Apply buffer below entry for sell orders
         double bufferPrice = InpBreakevenBufferPoints * _Point;
         double newSL = NormalizeDouble(openPrice - bufferPrice, _Digits);

         // Validate new SL meets broker's minimum stop level requirement
         long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
         double minStopDistance = stopLevel * _Point;
         double actualDistance = newSL - currentPrice;

         if(actualDistance < minStopDistance)
         {
            Print("SELL #", ticket, " breakeven move skipped: SL too close to current price");
            Print("  Required distance: ", stopLevel, " points (", minStopDistance, ")");
            Print("  Actual distance: ", (actualDistance / _Point), " points (", actualDistance, ")");
            Print("  Will retry when price moves further");
            return;
         }

         if(SafeOrderModify(ticket, newSL, tp))
         {
            g_breakevenReached[posIndex] = true;
            g_breakevenPrice[posIndex] = newSL;
            Print("SELL #", ticket, " moved to breakeven-", InpBreakevenBufferPoints, " at ", newSL,
                  " (", priceMovePoints, " points move)");
         }
         return;
      }

      // Stage 2: Trailing stop (starts immediately after breakeven)
      if(g_breakevenReached[posIndex])
      {
         // Calculate trailing SL: currentPrice + trailing distance
         double trailingDistance = InpBelowBaseline_TrailingPoints * _Point;
         double newSL = NormalizeDouble(currentPrice + trailingDistance, _Digits);

         // Only update if new SL is better than current SL and below breakeven
         if(newSL < currentSL && newSL < g_breakevenPrice[posIndex])
         {
            if(SafeOrderModify(ticket, newSL, tp))
            {
               Print("SELL #", ticket, " trailing SL updated from ", currentSL, " to ", newSL,
                     " (trailing ", InpBelowBaseline_TrailingPoints, " points from ", currentPrice, ")");
            }
         }
      }
   }
   else
   {
      // Above Baseline: ATR Multi-Timeframe Method
      double requiredMoveForBreakeven = g_rangeSize * InpBreakevenPercent / 100.0;
      double priceMove = openPrice - currentPrice;

      // Stage 1: Move to breakeven
      if(!g_breakevenReached[posIndex] && priceMove >= requiredMoveForBreakeven)
      {
         // Apply buffer below entry for sell orders
         double bufferPrice = InpBreakevenBufferPoints * _Point;
         double newSL = NormalizeDouble(openPrice - bufferPrice, _Digits);

         // Validate new SL meets broker's minimum stop level requirement
         long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
         double minStopDistance = stopLevel * _Point;
         double actualDistance = newSL - currentPrice;

         if(actualDistance < minStopDistance)
         {
            Print("SELL #", ticket, " breakeven move skipped: SL too close to current price");
            Print("  Required distance: ", stopLevel, " points (", minStopDistance, ")");
            Print("  Actual distance: ", (actualDistance / _Point), " points (", actualDistance, ")");
            Print("  Will retry when price moves further");
            return;
         }

         if(SafeOrderModify(ticket, newSL, tp))
         {
            g_breakevenReached[posIndex] = true;
            g_breakevenPrice[posIndex] = newSL;
            Print("SELL #", ticket, " moved to breakeven-", InpBreakevenBufferPoints, " at ", newSL);
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
            g_timeframeLevel[posIndex] = 0;  // Start with M1
            g_lastBarTime[posIndex] = 0;

            Print("SELL #", ticket, " ready for ATR management (Multi-Timeframe progression)");
         }
         return;
      }

      // Stage 3: Active ATR management with timeframe progression
      if(g_breakevenReached[posIndex] && g_nextMoveReached[posIndex])
      {
         // ATR method with timeframe progression (at/above baseline)
         ENUM_TIMEFRAMES currentTF = GetCurrentTimeframe(g_timeframeLevel[posIndex]);

         // Check if new bar has formed on current timeframe
         datetime currentBarTime = iTime(_Symbol, currentTF, 0);

         // If lastBarTime is 0 (initial state) or different from current, we have a new bar
         if(g_lastBarTime[posIndex] != 0 && currentBarTime == g_lastBarTime[posIndex])
            return;  // No new bar yet, skip this tick

         // Update last bar time
         g_lastBarTime[posIndex] = currentBarTime;

         double atrStopPrice = GetATRTrendIndValue(currentTF, POSITION_TYPE_SELL, posIndex);

         // Log detailed debug info with ATR_Trend_Ind value
         Print("SELL #", ticket, " TF ATR_Trend_Ind Check | Level: ", g_timeframeLevel[posIndex],
               " | TF: ", GetTimeframeName(g_timeframeLevel[posIndex]),
               " | Bar: ", TimeToString(currentBarTime),
               " | ATR_Trend_Ind Stop: ", atrStopPrice, " | Current SL: ", currentSL,
               " | Breakeven: ", g_breakevenPrice[posIndex],
               " | Price: ", currentPrice, " | Open: ", openPrice);

         if(atrStopPrice > 0 && atrStopPrice < currentSL && atrStopPrice < g_breakevenPrice[posIndex])
         {
            double newSL = NormalizeDouble(atrStopPrice, _Digits);
            if(SafeOrderModify(ticket, newSL, tp))
            {
               Print("SELL #", ticket, " ATR_Trend_Ind SL updated from ", currentSL, " to ", newSL, " (",
                     GetTimeframeName(g_timeframeLevel[posIndex]), ")");

               // Check if we should progress to next timeframe
               int maxLevel = GetMaxTimeframeLevel();
               if(g_timeframeLevel[posIndex] < maxLevel)
               {
                  g_timeframeLevel[posIndex]++;
                  // Reset bar time to 0 to wait for next bar on new timeframe
                  g_lastBarTime[posIndex] = 0;
                  Print("SELL #", ticket, " progressed to ",
                        GetTimeframeName(g_timeframeLevel[posIndex]), " timeframe");
               }
               else if(g_timeframeLevel[posIndex] == maxLevel)
               {
                  Print("SELL #", ticket, " at maximum timeframe (",
                        GetTimeframeName(maxLevel), ") - no further progression");
               }
            }
            else
            {
               Print("SELL #", ticket, " Failed to update SL to ", newSL, " on ",
                     GetTimeframeName(g_timeframeLevel[posIndex]));
            }
         }
         else
         {
            if(atrStopPrice <= 0)
               Print("SELL #", ticket, " ATR_Trend_Ind stop price invalid: ", atrStopPrice, " on ",
                     GetTimeframeName(g_timeframeLevel[posIndex]));
            else if(atrStopPrice >= currentSL)
               Print("SELL #", ticket, " ATR_Trend_Ind stop (", atrStopPrice, ") not < Current SL (", currentSL, ") on ",
                     GetTimeframeName(g_timeframeLevel[posIndex]));
            else if(atrStopPrice >= g_breakevenPrice[posIndex])
               Print("SELL #", ticket, " ATR_Trend_Ind stop (", atrStopPrice, ") not < Breakeven (", g_breakevenPrice[posIndex], ") on ",
                     GetTimeframeName(g_timeframeLevel[posIndex]));
         }
      }
   }
}
//+------------------------------------------------------------------+
