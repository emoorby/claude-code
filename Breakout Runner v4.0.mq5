//+------------------------------------------------------------------+
//|                                       Breakout Runner v4.0.mq5   |
//|                                                                  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Breakout Runner v4.0"
#property version   "4.00"
#property strict

//--- Input parameters
input string    OrderTime = "09:00";           // Time to place orders (HH:MM)
input int       ATR_Period = 10;               // ATR Period
input double    ATR_Multiplier = 3.0;          // ATR Multiplier
input double    LotSize = 0.1;                 // Lot Size
input double    BreakevenTrigger_R = 1.0;      // Breakeven trigger (in R)
input double    WaitPeriod_R = 0.5;            // Wait period after breakeven (in R)
input double    StopLoss_R = 1.0;              // Stop Loss (in R from entry)
input double    TakeProfit_R = 2.0;            // Take Profit (in R from entry)
input int       MagicNumber = 240100;          // Magic Number

//--- Global variables
int atr_handle;
bool orders_placed_today = false;
datetime last_order_date = 0;
double current_R = 0;
bool buy_at_breakeven = false;
bool sell_at_breakeven = false;
double buy_breakeven_reached_price = 0;
double sell_breakeven_reached_price = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("=================================================");
    Print("Breakout Runner v4.0 - Initialization Started");
    Print("=================================================");

    //--- Create ATR indicator handle
    atr_handle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
    if(atr_handle == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create ATR indicator handle");
        return(INIT_FAILED);
    }

    Print("ATR Indicator created successfully");
    Print("Settings:");
    Print("  - Order Time: ", OrderTime);
    Print("  - ATR Period: ", ATR_Period);
    Print("  - ATR Multiplier: ", ATR_Multiplier);
    Print("  - Lot Size: ", LotSize);
    Print("  - Breakeven Trigger: ", BreakevenTrigger_R, " R");
    Print("  - Wait Period After Breakeven: ", WaitPeriod_R, " R");
    Print("  - Stop Loss: ", StopLoss_R, " R");
    Print("  - Take Profit: ", TakeProfit_R, " R");
    Print("  - Magic Number: ", MagicNumber);
    Print("=================================================");
    Print("Initialization completed successfully");
    Print("=================================================");

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("=================================================");
    Print("Breakout Runner v4.0 - Shutting down");
    Print("Reason: ", reason);
    Print("=================================================");

    //--- Release ATR indicator handle
    if(atr_handle != INVALID_HANDLE)
        IndicatorRelease(atr_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Check if it's time to place orders
    CheckAndPlaceOrders();

    //--- Manage existing positions
    ManagePositions();
}

//+------------------------------------------------------------------+
//| Check if it's time to place orders                              |
//+------------------------------------------------------------------+
void CheckAndPlaceOrders()
{
    //--- Get current time
    datetime current_time = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(current_time, dt);

    //--- Check if we're on a new day
    datetime current_date = StringToTime(TimeToString(current_time, TIME_DATE));
    if(current_date > last_order_date)
    {
        orders_placed_today = false;
        last_order_date = current_date;
        Print("--- New Day Detected: ", TimeToString(current_date, TIME_DATE), " ---");
        Print("Orders can be placed today when time reaches: ", OrderTime);
    }

    //--- Check if orders already placed today
    if(orders_placed_today)
        return;

    //--- Parse order time
    string time_parts[];
    int splits = StringSplit(OrderTime, ':', time_parts);
    if(splits != 2)
    {
        Print("ERROR: Invalid OrderTime format. Use HH:MM");
        return;
    }

    int order_hour = (int)StringToInteger(time_parts[0]);
    int order_minute = (int)StringToInteger(time_parts[1]);

    //--- Check if current time matches order time
    if(dt.hour == order_hour && dt.min == order_minute)
    {
        Print("=================================================");
        Print("ORDER PLACEMENT TIME REACHED: ", TimeToString(current_time, TIME_DATE|TIME_MINUTES));
        Print("=================================================");
        PlacePendingOrders();
        orders_placed_today = true;
    }
}

//+------------------------------------------------------------------+
//| Place pending orders                                             |
//+------------------------------------------------------------------+
void PlacePendingOrders()
{
    Print("--- Starting Order Placement Process ---");

    //--- Delete any existing pending orders first
    DeletePendingOrders();

    //--- Get ATR value
    double atr_buffer[];
    ArraySetAsSeries(atr_buffer, true);

    if(CopyBuffer(atr_handle, 0, 0, 2, atr_buffer) < 2)
    {
        Print("ERROR: Failed to copy ATR buffer");
        return;
    }

    double atr_value = atr_buffer[0];
    Print("ATR Value: ", DoubleToString(atr_value, _Digits));

    //--- Calculate R (distance between buy stop and sell stop)
    current_R = atr_value * ATR_Multiplier;
    Print("R Calculation: ATR(", DoubleToString(atr_value, _Digits), ") * Multiplier(", ATR_Multiplier, ") = ", DoubleToString(current_R, _Digits));

    //--- Get current price
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    Print("Current Price: ", DoubleToString(current_price, _Digits));

    //--- Calculate order prices (R/2 from current price)
    double half_R = current_R / 2.0;
    double buy_stop_price = current_price + half_R;
    double sell_stop_price = current_price - half_R;

    Print("Half R: ", DoubleToString(half_R, _Digits));
    Print("Buy Stop Price: ", DoubleToString(buy_stop_price, _Digits), " (Current + R/2)");
    Print("Sell Stop Price: ", DoubleToString(sell_stop_price, _Digits), " (Current - R/2)");

    //--- Calculate stop loss and take profit levels
    double buy_sl = buy_stop_price - (current_R * StopLoss_R);
    double buy_tp = buy_stop_price + (current_R * TakeProfit_R);
    double sell_sl = sell_stop_price + (current_R * StopLoss_R);
    double sell_tp = sell_stop_price - (current_R * TakeProfit_R);

    Print("Buy Stop - SL: ", DoubleToString(buy_sl, _Digits), ", TP: ", DoubleToString(buy_tp, _Digits));
    Print("Sell Stop - SL: ", DoubleToString(sell_sl, _Digits), ", TP: ", DoubleToString(sell_tp, _Digits));

    //--- Normalize prices
    buy_stop_price = NormalizeDouble(buy_stop_price, _Digits);
    sell_stop_price = NormalizeDouble(sell_stop_price, _Digits);
    buy_sl = NormalizeDouble(buy_sl, _Digits);
    buy_tp = NormalizeDouble(buy_tp, _Digits);
    sell_sl = NormalizeDouble(sell_sl, _Digits);
    sell_tp = NormalizeDouble(sell_tp, _Digits);

    //--- Place Buy Stop order
    Print("--- Placing Buy Stop Order ---");
    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_PENDING;
    request.symbol = _Symbol;
    request.volume = LotSize;
    request.type = ORDER_TYPE_BUY_STOP;
    request.price = buy_stop_price;
    request.sl = buy_sl;
    request.tp = buy_tp;
    request.deviation = 10;
    request.magic = MagicNumber;
    request.comment = "Breakout Runner v4.0 - Buy";

    if(OrderSend(request, result))
    {
        Print("SUCCESS: Buy Stop order placed");
        Print("  Order Ticket: ", result.order);
        Print("  Price: ", DoubleToString(buy_stop_price, _Digits));
        Print("  SL: ", DoubleToString(buy_sl, _Digits));
        Print("  TP: ", DoubleToString(buy_tp, _Digits));
    }
    else
    {
        Print("ERROR: Failed to place Buy Stop order");
        Print("  Error Code: ", result.retcode);
        Print("  Error Description: ", GetErrorDescription(result.retcode));
    }

    //--- Place Sell Stop order
    Print("--- Placing Sell Stop Order ---");
    request.type = ORDER_TYPE_SELL_STOP;
    request.price = sell_stop_price;
    request.sl = sell_sl;
    request.tp = sell_tp;
    request.comment = "Breakout Runner v4.0 - Sell";

    if(OrderSend(request, result))
    {
        Print("SUCCESS: Sell Stop order placed");
        Print("  Order Ticket: ", result.order);
        Print("  Price: ", DoubleToString(sell_stop_price, _Digits));
        Print("  SL: ", DoubleToString(sell_sl, _Digits));
        Print("  TP: ", DoubleToString(sell_tp, _Digits));
    }
    else
    {
        Print("ERROR: Failed to place Sell Stop order");
        Print("  Error Code: ", result.retcode);
        Print("  Error Description: ", GetErrorDescription(result.retcode));
    }

    Print("=================================================");
    Print("Order Placement Process Completed");
    Print("=================================================");
}

//+------------------------------------------------------------------+
//| Delete pending orders                                            |
//+------------------------------------------------------------------+
void DeletePendingOrders()
{
    Print("--- Checking for existing pending orders to delete ---");

    int total_orders = OrdersTotal();
    if(total_orders == 0)
    {
        Print("No pending orders found");
        return;
    }

    Print("Found ", total_orders, " pending order(s)");

    for(int i = total_orders - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket > 0)
        {
            if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
               OrderGetInteger(ORDER_MAGIC) == MagicNumber)
            {
                MqlTradeRequest request = {};
                MqlTradeResult result = {};

                request.action = TRADE_ACTION_REMOVE;
                request.order = ticket;

                if(OrderSend(request, result))
                {
                    Print("Deleted pending order: ", ticket);
                }
                else
                {
                    Print("ERROR: Failed to delete order ", ticket, ", Error: ", result.retcode);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Manage existing positions                                        |
//+------------------------------------------------------------------+
void ManagePositions()
{
    int total_positions = PositionsTotal();
    if(total_positions == 0)
        return;

    for(int i = 0; i < total_positions; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0)
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
                ManagePosition(ticket);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Manage individual position                                       |
//+------------------------------------------------------------------+
void ManagePosition(ulong ticket)
{
    if(!PositionSelectByTicket(ticket))
        return;

    double position_open_price = PositionGetDouble(POSITION_PRICE_OPEN);
    double current_sl = PositionGetDouble(POSITION_SL);
    double current_tp = PositionGetDouble(POSITION_TP);
    long position_type = PositionGetInteger(POSITION_TYPE);
    double current_price;

    if(position_type == POSITION_TYPE_BUY)
    {
        current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

        //--- Calculate profit in terms of R
        double profit_points = current_price - position_open_price;
        double profit_in_R = profit_points / current_R;

        //--- Check if we need to move to breakeven
        if(!buy_at_breakeven && profit_in_R >= BreakevenTrigger_R)
        {
            Print("=================================================");
            Print("BUY POSITION BREAKEVEN TRIGGER REACHED");
            Print("  Ticket: ", ticket);
            Print("  Open Price: ", DoubleToString(position_open_price, _Digits));
            Print("  Current Price: ", DoubleToString(current_price, _Digits));
            Print("  Profit: ", DoubleToString(profit_in_R, 2), " R");
            Print("  Moving Stop Loss to Breakeven");
            Print("=================================================");

            MqlTradeRequest request = {};
            MqlTradeResult result = {};

            request.action = TRADE_ACTION_SLTP;
            request.symbol = _Symbol;
            request.position = ticket;
            request.sl = NormalizeDouble(position_open_price, _Digits);
            request.tp = current_tp;

            if(OrderSend(request, result))
            {
                buy_at_breakeven = true;
                buy_breakeven_reached_price = current_price;
                Print("SUCCESS: Stop Loss moved to breakeven at ", DoubleToString(position_open_price, _Digits));
                Print("Waiting for price to move ", WaitPeriod_R, " R before further action");
                Print("Wait trigger price: ", DoubleToString(buy_breakeven_reached_price + (current_R * WaitPeriod_R), _Digits));
            }
            else
            {
                Print("ERROR: Failed to modify position");
                Print("  Error Code: ", result.retcode);
                Print("  Error Description: ", GetErrorDescription(result.retcode));
            }
        }

        //--- Check wait period after breakeven
        if(buy_at_breakeven)
        {
            double distance_from_breakeven = current_price - buy_breakeven_reached_price;
            double distance_in_R = distance_from_breakeven / current_R;

            if(distance_in_R >= WaitPeriod_R)
            {
                Print("--- BUY POSITION: Wait period completed ---");
                Print("  Current Price: ", DoubleToString(current_price, _Digits));
                Print("  Distance from breakeven trigger: ", DoubleToString(distance_in_R, 2), " R");
                Print("  Ready for additional actions (to be implemented)");
                //--- Future functionality will be added here
            }
        }
    }
    else if(position_type == POSITION_TYPE_SELL)
    {
        current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

        //--- Calculate profit in terms of R
        double profit_points = position_open_price - current_price;
        double profit_in_R = profit_points / current_R;

        //--- Check if we need to move to breakeven
        if(!sell_at_breakeven && profit_in_R >= BreakevenTrigger_R)
        {
            Print("=================================================");
            Print("SELL POSITION BREAKEVEN TRIGGER REACHED");
            Print("  Ticket: ", ticket);
            Print("  Open Price: ", DoubleToString(position_open_price, _Digits));
            Print("  Current Price: ", DoubleToString(current_price, _Digits));
            Print("  Profit: ", DoubleToString(profit_in_R, 2), " R");
            Print("  Moving Stop Loss to Breakeven");
            Print("=================================================");

            MqlTradeRequest request = {};
            MqlTradeResult result = {};

            request.action = TRADE_ACTION_SLTP;
            request.symbol = _Symbol;
            request.position = ticket;
            request.sl = NormalizeDouble(position_open_price, _Digits);
            request.tp = current_tp;

            if(OrderSend(request, result))
            {
                sell_at_breakeven = true;
                sell_breakeven_reached_price = current_price;
                Print("SUCCESS: Stop Loss moved to breakeven at ", DoubleToString(position_open_price, _Digits));
                Print("Waiting for price to move ", WaitPeriod_R, " R before further action");
                Print("Wait trigger price: ", DoubleToString(sell_breakeven_reached_price - (current_R * WaitPeriod_R), _Digits));
            }
            else
            {
                Print("ERROR: Failed to modify position");
                Print("  Error Code: ", result.retcode);
                Print("  Error Description: ", GetErrorDescription(result.retcode));
            }
        }

        //--- Check wait period after breakeven
        if(sell_at_breakeven)
        {
            double distance_from_breakeven = sell_breakeven_reached_price - current_price;
            double distance_in_R = distance_from_breakeven / current_R;

            if(distance_in_R >= WaitPeriod_R)
            {
                Print("--- SELL POSITION: Wait period completed ---");
                Print("  Current Price: ", DoubleToString(current_price, _Digits));
                Print("  Distance from breakeven trigger: ", DoubleToString(distance_in_R, 2), " R");
                Print("  Ready for additional actions (to be implemented)");
                //--- Future functionality will be added here
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Get error description                                            |
//+------------------------------------------------------------------+
string GetErrorDescription(uint error_code)
{
    switch(error_code)
    {
        case 10004: return "Requote";
        case 10006: return "Request rejected";
        case 10007: return "Request canceled by trader";
        case 10008: return "Order placed";
        case 10009: return "Request completed";
        case 10010: return "Only part of the request was completed";
        case 10011: return "Request processing error";
        case 10012: return "Request canceled by timeout";
        case 10013: return "Invalid request";
        case 10014: return "Invalid volume in the request";
        case 10015: return "Invalid price in the request";
        case 10016: return "Invalid stops in the request";
        case 10017: return "Trade is disabled";
        case 10018: return "Market is closed";
        case 10019: return "There is not enough money to complete the request";
        case 10020: return "Prices changed";
        case 10021: return "There are no quotes to process the request";
        case 10022: return "Invalid order expiration date in the request";
        case 10023: return "Order state changed";
        case 10024: return "Too frequent requests";
        case 10025: return "No changes in request";
        case 10026: return "Autotrading disabled by server";
        case 10027: return "Autotrading disabled by client terminal";
        case 10028: return "Request locked for processing";
        case 10029: return "Order or position frozen";
        case 10030: return "Invalid order filling type";
        case 10031: return "No connection with the trade server";
        case 10032: return "Operation is allowed only for live accounts";
        case 10033: return "The number of pending orders has reached the limit";
        case 10034: return "The volume of orders and positions for the symbol has reached the limit";
        case 10035: return "Incorrect or prohibited order type";
        case 10036: return "Position with the specified POSITION_IDENTIFIER has already been closed";
        default: return "Unknown error";
    }
}
//+------------------------------------------------------------------+
