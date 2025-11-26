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

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
double   g_rangeHigh = 0.0;           // High of the range
double   g_rangeLow = 0.0;            // Low of the range
bool     g_rangeIdentified = false;   // Flag: range has been identified
bool     g_ordersPlaced = false;      // Flag: initial orders placed
int      g_tradesCount = 0;           // Number of trades executed today
int      g_currentDay = 0;            // Current day for daily reset
ulong    g_buyStopTicket = 0;         // Buy stop order ticket
ulong    g_sellStopTicket = 0;        // Sell stop order ticket
double   g_rangeSize = 0.0;           // Size of the range in price

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
   Print("========================================");

   // Initialize current day
   MqlDateTime time_struct;
   TimeCurrent(time_struct);
   g_currentDay = time_struct.day;

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
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
   else if(IsAfterRangeTime(time_struct) && !g_rangeIdentified)
   {
      // Range period has ended, finalize the range
      FinalizeRange();
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

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.symbol = _Symbol;
   request.volume = lotSize;
   request.magic = InpMagicNumber;
   request.deviation = 10;
   request.type_filling = ORDER_FILLING_IOC;

   // Place Buy Stop Order
   if(InpTradeDirection == TRADE_BOTH || InpTradeDirection == TRADE_BUY_ONLY)
   {
      request.action = TRADE_ACTION_PENDING;
      request.type = ORDER_TYPE_BUY_STOP;
      request.price = NormalizeDouble(g_rangeHigh, _Digits);
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
         }
      }
      else
      {
         Print("ERROR: OrderSend failed for Buy Stop");
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
      request.type = ORDER_TYPE_SELL_STOP;
      request.price = NormalizeDouble(g_rangeLow, _Digits);
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
         }
      }
      else
      {
         Print("ERROR: OrderSend failed for Sell Stop");
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
      double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

      Print("Current Ask: ", ask, " Bid: ", bid, " Stop Level: ", stopLevel);

      // Calculate stop loss and take profit distances
      double slDistance = g_rangeSize * InpStopLossPercent / 100.0;
      double tpDistance = g_rangeSize * InpTakeProfitPercent / 100.0;
      double lotSize = CalculateLotSize(slDistance);

      MqlTradeRequest request;
      MqlTradeResult result;

      // Replace Buy Stop if it was triggered
      if(buyOrderTriggered && (InpTradeDirection == TRADE_BOTH || InpTradeDirection == TRADE_BUY_ONLY))
      {
         // Check if original range high price is still valid for a buy stop
         double buyStopPrice = g_rangeHigh;
         double minBuyStopPrice = ask + stopLevel;

         if(buyStopPrice < minBuyStopPrice)
         {
            Print("WARNING: Original buy stop price (", buyStopPrice,
                  ") is below minimum allowed (", minBuyStopPrice, ")");
            buyStopPrice = minBuyStopPrice;
            Print("Adjusting buy stop price to: ", buyStopPrice);
         }

         ZeroMemory(request);
         ZeroMemory(result);

         request.action = TRADE_ACTION_PENDING;
         request.symbol = _Symbol;
         request.volume = lotSize;
         request.magic = InpMagicNumber;
         request.type = ORDER_TYPE_BUY_STOP;
         request.price = NormalizeDouble(buyStopPrice, _Digits);
         request.sl = NormalizeDouble(buyStopPrice - slDistance, _Digits);
         request.tp = NormalizeDouble(buyStopPrice + tpDistance, _Digits);
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

      // Replace Sell Stop if it was triggered
      if(sellOrderTriggered && (InpTradeDirection == TRADE_BOTH || InpTradeDirection == TRADE_SELL_ONLY))
      {
         // Check if original range low price is still valid for a sell stop
         double sellStopPrice = g_rangeLow;
         double maxSellStopPrice = bid - stopLevel;

         if(sellStopPrice > maxSellStopPrice)
         {
            Print("WARNING: Original sell stop price (", sellStopPrice,
                  ") is above maximum allowed (", maxSellStopPrice, ")");
            sellStopPrice = maxSellStopPrice;
            Print("Adjusting sell stop price to: ", sellStopPrice);
         }

         ZeroMemory(request);
         ZeroMemory(result);

         request.action = TRADE_ACTION_PENDING;
         request.symbol = _Symbol;
         request.volume = lotSize;
         request.magic = InpMagicNumber;
         request.type = ORDER_TYPE_SELL_STOP;
         request.price = NormalizeDouble(sellStopPrice, _Digits);
         request.sl = NormalizeDouble(sellStopPrice + slDistance, _Digits);
         request.tp = NormalizeDouble(sellStopPrice - tpDistance, _Digits);
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
      g_ordersPlaced = false;
      g_tradesCount = 0;
      g_buyStopTicket = 0;
      g_sellStopTicket = 0;
      g_currentDay = time_struct.day;

      Print("Daily reset complete");
      Print("Trade count reset to: 0");
      Print("Range values cleared");
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
