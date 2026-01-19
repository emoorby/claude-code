//+------------------------------------------------------------------+
//|                                       Breakout Runner v4.0.mq5   |
//|                                                                  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Breakout Runner v4.0"
#property version   "4.00"
#property strict

//--- Enumerations
enum ENUM_LOT_MODE
{
    LOT_MODE_FIXED,           // Fixed Lot Size
    LOT_MODE_RISK_PERCENT     // Risk Percentage
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

//--- Input parameters
input string    OrderTime = "09:00";                    // Time to place orders (HH:MM)
input string    OrderDeleteTime = "22:00";              // Time to delete pending orders (HH:MM)
input int       ATR_Period = 10;                        // ATR Period
input double    ATR_Multiplier = 3.0;                   // ATR Multiplier
input ENUM_LOT_MODE LotSizingMode = LOT_MODE_RISK_PERCENT;  // Lot Sizing Mode
input double    FixedLotSize = 0.1;                     // Fixed Lot Size
input double    RiskPercent = 1.0;                      // Risk Percentage (for Risk mode)
input double    BreakevenTrigger_R = 1.0;               // Breakeven trigger (in R)
input double    BreakevenBuffer_Points = 5;             // Breakeven buffer (in points)
input double    WaitPeriod_R = 0.5;                     // Wait period after breakeven (in R)
input double    StopLoss_R = 1.0;                       // Stop Loss (in R from entry)
input int       MinStopLoss_Points = 100;               // Minimum Stop Loss (in points)
input double    TakeProfit_R = 2.0;                     // Take Profit (in R from entry)
input string    OrderComment = "Breakout Runner v4.0";  // Order Comment
input int       MagicNumber = 240100;                   // Magic Number

// Advanced Trade Management
input group "=== Advanced Trade Management ==="
input double   BaselineBalance = 10000.0;               // Baseline Balance
input double   ATRModifier = 1.0;                       // ATR Modifier for trailing
input ENUM_MAX_TIMEFRAME MaxTimeframe = MAX_TF_D1;      // Maximum Timeframe for Progression

// ADX Volatility Filter
input group "=== ADX Volatility Filter ==="
input bool     EnableADXFilter = false;                 // Enable ADX Volatility Filter
input bool     Filter_CheckATRIncreasing = true;        // Check 1: ATR Must Be Increasing
input bool     Filter_CheckSignificantIncrease = true;  // Check 2: ATR Increase Must Be Significant
input bool     Filter_CheckDirectionalMomentum = true;  // Check 3: Directional Momentum Required
input int      ATRFilter_RecentCandles = 2;             // Recent Candles (x)
input int      ATRFilter_EarlierCandles = 3;            // Earlier Candles (y)
input double   ATRFilter_MinIncreasePercent = 20.0;     // Minimum ATR Increase (% of Earlier ATR)
input int      DirectionalFilter_Candles = 5;           // Directional Candles to Check
input int      DirectionalFilter_MinRequired = 4;       // Minimum Directional Candles Required

//--- Global variables
int atr_handle;
bool orders_placed_today = false;
bool orders_deleted_today = false;
datetime last_order_date = 0;
datetime last_delete_date = 0;
double current_R = 0;

// ATR_Trend_Ind indicator handles for all timeframes
int atr_trend_handle_M1 = INVALID_HANDLE;
int atr_trend_handle_M5 = INVALID_HANDLE;
int atr_trend_handle_M15 = INVALID_HANDLE;
int atr_trend_handle_M30 = INVALID_HANDLE;
int atr_trend_handle_H1 = INVALID_HANDLE;
int atr_trend_handle_H4 = INVALID_HANDLE;
int atr_trend_handle_D1 = INVALID_HANDLE;

//--- Position tracking structures
struct PositionTracking
{
    ulong ticket;
    double entry_R;                    // R value when position was opened
    bool at_breakeven;                 // Whether position has moved to breakeven
    double breakeven_reached_price;    // Price when breakeven was reached
    bool wait_period_logged;           // Whether wait period completion has been logged
    bool atr_management_active;        // Whether ATR trailing is active
    int timeframe_level;               // Current timeframe level (0=M1, 1=M5, etc.)
    bool use_below_baseline_method;    // Management method locked at position open
    datetime last_bar_time;            // Last bar time for timeframe progression
    double cached_atr_values[7];       // Cached ATR_Trend_Ind values for each timeframe
};

PositionTracking tracked_positions[];
int tracked_positions_count = 0;

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

    //--- Create ATR_Trend_Ind indicator handles for all timeframes
    atr_trend_handle_M1 = iCustom(_Symbol, PERIOD_M1, "ATR_Trend_Ind", ATR_Period, ATRModifier);
    atr_trend_handle_M5 = iCustom(_Symbol, PERIOD_M5, "ATR_Trend_Ind", ATR_Period, ATRModifier);
    atr_trend_handle_M15 = iCustom(_Symbol, PERIOD_M15, "ATR_Trend_Ind", ATR_Period, ATRModifier);
    atr_trend_handle_M30 = iCustom(_Symbol, PERIOD_M30, "ATR_Trend_Ind", ATR_Period, ATRModifier);
    atr_trend_handle_H1 = iCustom(_Symbol, PERIOD_H1, "ATR_Trend_Ind", ATR_Period, ATRModifier);
    atr_trend_handle_H4 = iCustom(_Symbol, PERIOD_H4, "ATR_Trend_Ind", ATR_Period, ATRModifier);
    atr_trend_handle_D1 = iCustom(_Symbol, PERIOD_D1, "ATR_Trend_Ind", ATR_Period, ATRModifier);

    if(atr_trend_handle_M1 == INVALID_HANDLE || atr_trend_handle_M5 == INVALID_HANDLE ||
       atr_trend_handle_M15 == INVALID_HANDLE || atr_trend_handle_M30 == INVALID_HANDLE ||
       atr_trend_handle_H1 == INVALID_HANDLE || atr_trend_handle_H4 == INVALID_HANDLE ||
       atr_trend_handle_D1 == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create one or more ATR_Trend_Ind indicator handles");
        Print("  M1: ", (atr_trend_handle_M1 == INVALID_HANDLE ? "FAILED" : "OK"));
        Print("  M5: ", (atr_trend_handle_M5 == INVALID_HANDLE ? "FAILED" : "OK"));
        Print("  M15: ", (atr_trend_handle_M15 == INVALID_HANDLE ? "FAILED" : "OK"));
        Print("  M30: ", (atr_trend_handle_M30 == INVALID_HANDLE ? "FAILED" : "OK"));
        Print("  H1: ", (atr_trend_handle_H1 == INVALID_HANDLE ? "FAILED" : "OK"));
        Print("  H4: ", (atr_trend_handle_H4 == INVALID_HANDLE ? "FAILED" : "OK"));
        Print("  D1: ", (atr_trend_handle_D1 == INVALID_HANDLE ? "FAILED" : "OK"));
        return(INIT_FAILED);
    }

    Print("ATR_Trend_Ind indicators created successfully for all timeframes");

    Print("Settings:");
    Print("  - Order Placement Time: ", OrderTime);
    Print("  - Order Delete Time: ", OrderDeleteTime);
    Print("  - ATR Period: ", ATR_Period);
    Print("  - ATR Multiplier: ", ATR_Multiplier);
    Print("  - Lot Sizing Mode: ", (LotSizingMode == LOT_MODE_FIXED ? "Fixed Lot Size" : "Risk Percentage"));
    if(LotSizingMode == LOT_MODE_FIXED)
        Print("  - Fixed Lot Size: ", FixedLotSize);
    else
        Print("  - Risk Percentage: ", RiskPercent, "%");
    Print("  - Breakeven Trigger: ", BreakevenTrigger_R, " R");
    Print("  - Breakeven Buffer: ", BreakevenBuffer_Points, " points");
    Print("  - Wait Period After Breakeven: ", WaitPeriod_R, " R");
    Print("  - Stop Loss: ", StopLoss_R, " R");
    Print("  - Minimum Stop Loss: ", MinStopLoss_Points, " points");
    Print("  - Take Profit: ", TakeProfit_R, " R");
    Print("  - Order Comment: ", OrderComment);
    Print("  - Magic Number: ", MagicNumber);
    Print("");
    Print("Advanced Trade Management:");
    Print("  - Baseline Balance: ", BaselineBalance);
    Print("  - ATR Modifier: ", ATRModifier);
    string maxTfStr = "";
    switch(MaxTimeframe)
    {
        case MAX_TF_M1: maxTfStr = "M1"; break;
        case MAX_TF_M5: maxTfStr = "M5"; break;
        case MAX_TF_M15: maxTfStr = "M15"; break;
        case MAX_TF_M30: maxTfStr = "M30"; break;
        case MAX_TF_H1: maxTfStr = "H1"; break;
        case MAX_TF_H4: maxTfStr = "H4"; break;
        case MAX_TF_D1: maxTfStr = "D1"; break;
    }
    Print("  - Max Timeframe: ", maxTfStr);
    Print("");
    Print("ADX Volatility Filter:");
    Print("  - Enabled: ", (EnableADXFilter ? "YES" : "NO"));
    if(EnableADXFilter)
    {
        Print("  - Check ATR Increasing: ", (Filter_CheckATRIncreasing ? "YES" : "NO"));
        Print("  - Check Significant Increase: ", (Filter_CheckSignificantIncrease ? "YES" : "NO"));
        Print("  - Check Directional Momentum: ", (Filter_CheckDirectionalMomentum ? "YES" : "NO"));
        Print("  - Recent Candles: ", ATRFilter_RecentCandles);
        Print("  - Earlier Candles: ", ATRFilter_EarlierCandles);
        Print("  - Min Increase %: ", ATRFilter_MinIncreasePercent);
        Print("  - Directional Candles: ", DirectionalFilter_Candles);
        Print("  - Min Required: ", DirectionalFilter_MinRequired);
    }
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

    //--- Release ATR_Trend_Ind indicator handles
    if(atr_trend_handle_M1 != INVALID_HANDLE)
        IndicatorRelease(atr_trend_handle_M1);
    if(atr_trend_handle_M5 != INVALID_HANDLE)
        IndicatorRelease(atr_trend_handle_M5);
    if(atr_trend_handle_M15 != INVALID_HANDLE)
        IndicatorRelease(atr_trend_handle_M15);
    if(atr_trend_handle_M30 != INVALID_HANDLE)
        IndicatorRelease(atr_trend_handle_M30);
    if(atr_trend_handle_H1 != INVALID_HANDLE)
        IndicatorRelease(atr_trend_handle_H1);
    if(atr_trend_handle_H4 != INVALID_HANDLE)
        IndicatorRelease(atr_trend_handle_H4);
    if(atr_trend_handle_D1 != INVALID_HANDLE)
        IndicatorRelease(atr_trend_handle_D1);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Clean up tracking for any closed positions
    CleanupClosedPositions();

    //--- Check if it's time to place orders
    CheckAndPlaceOrders();

    //--- Check if it's time to delete pending orders
    CheckAndDeleteOrders();

    //--- Manage existing positions
    ManagePositions();
}

//+------------------------------------------------------------------+
//| Add position to tracking                                         |
//+------------------------------------------------------------------+
void AddPositionTracking(ulong ticket, double entry_R_value)
{
    ArrayResize(tracked_positions, tracked_positions_count + 1);
    tracked_positions[tracked_positions_count].ticket = ticket;
    tracked_positions[tracked_positions_count].entry_R = entry_R_value;
    tracked_positions[tracked_positions_count].at_breakeven = false;
    tracked_positions[tracked_positions_count].breakeven_reached_price = 0;
    tracked_positions[tracked_positions_count].wait_period_logged = false;

    // Initialize ATR trailing management fields
    tracked_positions[tracked_positions_count].atr_management_active = false;
    tracked_positions[tracked_positions_count].timeframe_level = 0;  // Start at M1

    // Lock management method based on current balance vs baseline
    double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    tracked_positions[tracked_positions_count].use_below_baseline_method = (current_balance < BaselineBalance);

    tracked_positions[tracked_positions_count].last_bar_time = 0;

    // Initialize cached ATR values
    for(int i = 0; i < 7; i++)
        tracked_positions[tracked_positions_count].cached_atr_values[i] = 0;

    tracked_positions_count++;

    Print("Position tracking added: Ticket ", ticket, ", Entry R: ", DoubleToString(entry_R_value, _Digits),
          ", Below baseline method: ", (tracked_positions[tracked_positions_count - 1].use_below_baseline_method ? "YES" : "NO"));
}

//+------------------------------------------------------------------+
//| Get position tracking index                                      |
//+------------------------------------------------------------------+
int GetPositionTrackingIndex(ulong ticket)
{
    for(int i = 0; i < tracked_positions_count; i++)
    {
        if(tracked_positions[i].ticket == ticket)
            return i;
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Clean up closed positions from tracking                          |
//+------------------------------------------------------------------+
void CleanupClosedPositions()
{
    for(int i = tracked_positions_count - 1; i >= 0; i--)
    {
        if(!PositionSelectByTicket(tracked_positions[i].ticket))
        {
            Print("Removing closed position from tracking: Ticket ", tracked_positions[i].ticket);

            // Shift array elements
            for(int j = i; j < tracked_positions_count - 1; j++)
            {
                tracked_positions[j] = tracked_positions[j + 1];
            }
            tracked_positions_count--;
            ArrayResize(tracked_positions, tracked_positions_count);
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                |
//+------------------------------------------------------------------+
double CalculateLotSize(double stop_loss_distance)
{
    double lot_size = 0;

    if(LotSizingMode == LOT_MODE_FIXED)
    {
        lot_size = FixedLotSize;
        Print("--- Lot Size Calculation (Fixed Mode) ---");
        Print("  Using Fixed Lot Size: ", lot_size);
    }
    else // LOT_MODE_RISK_PERCENT
    {
        Print("--- Lot Size Calculation (Risk Percentage Mode) ---");

        //--- Get account balance and currency
        double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        string account_currency = AccountInfoString(ACCOUNT_CURRENCY);
        Print("  Account Balance: ", DoubleToString(account_balance, 2), " ", account_currency);

        //--- Calculate risk amount in account currency
        double risk_amount = account_balance * RiskPercent / 100.0;
        Print("  Risk Amount: ", DoubleToString(risk_amount, 2), " (", RiskPercent, "% of balance)");

        //--- Get symbol properties
        double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
        double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
        double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        double contract_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        string profit_currency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
        string base_currency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);

        Print("  Symbol Tick Size: ", tick_size);
        Print("  Symbol Tick Value: ", tick_value, " (in account currency)");
        Print("  Symbol Point: ", point);
        Print("  Symbol Contract Size: ", contract_size);
        Print("  Symbol Base Currency: ", base_currency);
        Print("  Symbol Profit Currency: ", profit_currency);

        //--- Calculate stop loss in points
        double sl_points = stop_loss_distance / point;
        Print("  Stop Loss Distance: ", DoubleToString(stop_loss_distance, _Digits));
        Print("  Stop Loss Points: ", DoubleToString(sl_points, 0));

        //--- Calculate point value in account currency
        //--- For CFDs/Indices: tick_value is already in account currency
        //--- For Forex: tick_value is also in account currency
        double point_value = (tick_value / tick_size) * point;
        Print("  Point Value (per 1 lot): ", DoubleToString(point_value, 5), " ", account_currency);

        //--- Calculate money at risk per lot
        double money_at_risk_per_lot = sl_points * point_value;
        Print("  Money at Risk per 1 lot: ", DoubleToString(money_at_risk_per_lot, 2), " ", account_currency);

        //--- Calculate lot size
        if(money_at_risk_per_lot > 0)
        {
            lot_size = risk_amount / money_at_risk_per_lot;
            Print("  Calculated Lot Size: ", DoubleToString(lot_size, 2), " (Risk/MoneyPerLot)");
        }
        else
        {
            Print("ERROR: Invalid calculation - money at risk per lot is zero or negative");
            lot_size = FixedLotSize; // Fallback to fixed lot size
            Print("  Using fallback Fixed Lot Size: ", lot_size);
        }
    }

    //--- Normalize lot size to symbol requirements
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    Print("  Symbol Min Lot: ", min_lot);
    Print("  Symbol Max Lot: ", max_lot);
    Print("  Symbol Lot Step: ", lot_step);

    //--- Normalize to lot step
    lot_size = MathFloor(lot_size / lot_step) * lot_step;

    //--- Apply min/max constraints
    if(lot_size < min_lot)
    {
        lot_size = min_lot;
        Print("  Lot size adjusted to minimum: ", lot_size);
    }
    if(lot_size > max_lot)
    {
        lot_size = max_lot;
        Print("  Lot size adjusted to maximum: ", lot_size);
    }

    Print("  Final Lot Size: ", lot_size);

    return lot_size;
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
//| Check if it's time to delete pending orders                      |
//+------------------------------------------------------------------+
void CheckAndDeleteOrders()
{
    //--- Get current time
    datetime current_time = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(current_time, dt);

    //--- Check if we're on a new day
    datetime current_date = StringToTime(TimeToString(current_time, TIME_DATE));
    if(current_date > last_delete_date)
    {
        orders_deleted_today = false;
        last_delete_date = current_date;
    }

    //--- Check if orders already deleted today
    if(orders_deleted_today)
        return;

    //--- Parse order delete time
    string time_parts[];
    int splits = StringSplit(OrderDeleteTime, ':', time_parts);
    if(splits != 2)
    {
        Print("ERROR: Invalid OrderDeleteTime format. Use HH:MM");
        return;
    }

    int delete_hour = (int)StringToInteger(time_parts[0]);
    int delete_minute = (int)StringToInteger(time_parts[1]);

    //--- Check if current time matches delete time
    if(dt.hour == delete_hour && dt.min == delete_minute)
    {
        Print("=================================================");
        Print("ORDER DELETE TIME REACHED: ", TimeToString(current_time, TIME_DATE|TIME_MINUTES));
        Print("Deleting all pending orders for the day");
        Print("=================================================");
        DeletePendingOrders();
        orders_deleted_today = true;
    }
}

//+------------------------------------------------------------------+
//| Get timeframe level (0=M1, 1=M5, 2=M15, 3=M30, 4=H1, 5=H4, 6=D1)|
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
        default: return -1;
    }
}

//+------------------------------------------------------------------+
//| Get ENUM_TIMEFRAMES from level                                   |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetTimeframeFromLevel(int level)
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
//| Get timeframe name string                                        |
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
        default: return "Unknown";
    }
}

//+------------------------------------------------------------------+
//| Get max timeframe level based on input                          |
//+------------------------------------------------------------------+
int GetMaxTimeframeLevel()
{
    switch(MaxTimeframe)
    {
        case MAX_TF_M1: return 0;
        case MAX_TF_M5: return 1;
        case MAX_TF_M15: return 2;
        case MAX_TF_M30: return 3;
        case MAX_TF_H1: return 4;
        case MAX_TF_H4: return 5;
        case MAX_TF_D1: return 6;
        default: return 6;
    }
}

//+------------------------------------------------------------------+
//| Get indicator handle for specific timeframe level               |
//+------------------------------------------------------------------+
int GetATRTrendHandle(int timeframe_level)
{
    switch(timeframe_level)
    {
        case 0: return atr_trend_handle_M1;
        case 1: return atr_trend_handle_M5;
        case 2: return atr_trend_handle_M15;
        case 3: return atr_trend_handle_M30;
        case 4: return atr_trend_handle_H1;
        case 5: return atr_trend_handle_H4;
        case 6: return atr_trend_handle_D1;
        default: return INVALID_HANDLE;
    }
}

//+------------------------------------------------------------------+
//| Get ATR_Trend_Ind value with caching and 50-bar lookback        |
//+------------------------------------------------------------------+
double GetATRTrendIndValue(int pos_index, int timeframe_level, ENUM_POSITION_TYPE pos_type)
{
    // Check if we have a cached value for this timeframe
    if(pos_index >= 0 && pos_index < tracked_positions_count)
    {
        if(tracked_positions[pos_index].cached_atr_values[timeframe_level] > 0)
        {
            return tracked_positions[pos_index].cached_atr_values[timeframe_level];
        }
    }

    // Get the indicator handle for this timeframe
    int handle = GetATRTrendHandle(timeframe_level);
    if(handle == INVALID_HANDLE)
    {
        Print("ERROR: Invalid handle for timeframe level ", timeframe_level);
        return 0;
    }

    // Determine which buffer to use based on position type
    // Buffer 2 = SELL stops (line above price)
    // Buffer 3 = BUY stops (line below price)
    int target_buffer = (pos_type == POSITION_TYPE_BUY) ? 3 : 2;

    // Look back up to 50 bars to find a valid ATR value
    double values[];
    ArraySetAsSeries(values, true);

    if(CopyBuffer(handle, target_buffer, 0, 50, values) <= 0)
    {
        Print("ERROR: Failed to copy buffer for timeframe level ", timeframe_level);
        return 0;
    }

    // Find the first valid (non-zero) value
    for(int i = 0; i < 50; i++)
    {
        if(values[i] > 0 && values[i] != EMPTY_VALUE)
        {
            // Cache the value
            if(pos_index >= 0 && pos_index < tracked_positions_count)
            {
                tracked_positions[pos_index].cached_atr_values[timeframe_level] = values[i];
            }
            return values[i];
        }
    }

    Print("WARNING: No valid ATR_Trend_Ind value found in 50 bars for timeframe level ", timeframe_level);
    return 0;
}

//+------------------------------------------------------------------+
//| Check ADX Volatility Filter                                      |
//| Returns true if conditions are met (allow order placement)      |
//+------------------------------------------------------------------+
bool CheckADXFilter()
{
    if(!EnableADXFilter)
        return true;  // Filter disabled, allow placement

    Print("--- Checking ADX Volatility Filter ---");

    double atr_values[];
    ArraySetAsSeries(atr_values, true);

    // Get enough ATR values for the checks
    int needed_bars = MathMax(ATRFilter_RecentCandles, ATRFilter_EarlierCandles) + DirectionalFilter_Candles + 5;
    if(CopyBuffer(atr_handle, 0, 0, needed_bars, atr_values) <= 0)
    {
        Print("ERROR: Failed to copy ATR buffer for filter check");
        return false;
    }

    // Check 1: ATR Must Be Increasing (Recent > Earlier)
    if(Filter_CheckATRIncreasing)
    {
        double recent_atr = 0;
        for(int i = 0; i < ATRFilter_RecentCandles; i++)
            recent_atr += atr_values[i];
        recent_atr /= ATRFilter_RecentCandles;

        double earlier_atr = 0;
        int earlier_start = ATRFilter_RecentCandles;
        for(int i = earlier_start; i < earlier_start + ATRFilter_EarlierCandles; i++)
            earlier_atr += atr_values[i];
        earlier_atr /= ATRFilter_EarlierCandles;

        Print("Check 1 - ATR Increasing:");
        Print("  Recent ATR (avg of ", ATRFilter_RecentCandles, " candles): ", recent_atr);
        Print("  Earlier ATR (avg of ", ATRFilter_EarlierCandles, " candles): ", earlier_atr);

        if(recent_atr <= earlier_atr)
        {
            Print("  FAILED: Recent ATR is NOT greater than earlier ATR");
            return false;
        }
        Print("  PASSED: Recent ATR is greater than earlier ATR");

        // Check 2: Significant Increase
        if(Filter_CheckSignificantIncrease)
        {
            double increase = recent_atr - earlier_atr;
            double min_increase_required = earlier_atr * (ATRFilter_MinIncreasePercent / 100.0);

            Print("Check 2 - Significant Increase:");
            Print("  ATR Increase: ", increase);
            Print("  Min Required (", ATRFilter_MinIncreasePercent, "% of earlier): ", min_increase_required);

            if(increase < min_increase_required)
            {
                Print("  FAILED: Increase is not significant enough");
                return false;
            }
            Print("  PASSED: Increase is significant");
        }
    }

    // Check 3: Directional Momentum
    if(Filter_CheckDirectionalMomentum)
    {
        Print("Check 3 - Directional Momentum:");

        // Count bullish candles (close > open)
        int bullish_count = 0;
        for(int i = 0; i < DirectionalFilter_Candles; i++)
        {
            double open = iOpen(_Symbol, PERIOD_CURRENT, i);
            double close = iClose(_Symbol, PERIOD_CURRENT, i);
            if(close > open)
                bullish_count++;
        }

        int bearish_count = DirectionalFilter_Candles - bullish_count;

        Print("  Bullish candles: ", bullish_count, " / ", DirectionalFilter_Candles);
        Print("  Bearish candles: ", bearish_count, " / ", DirectionalFilter_Candles);
        Print("  Min required: ", DirectionalFilter_MinRequired);

        bool has_directional_momentum = (bullish_count >= DirectionalFilter_MinRequired) ||
                                       (bearish_count >= DirectionalFilter_MinRequired);

        if(!has_directional_momentum)
        {
            Print("  FAILED: Not enough directional momentum");
            return false;
        }
        Print("  PASSED: Sufficient directional momentum detected");
    }

    Print("All ADX filter checks PASSED - Order placement allowed");
    return true;
}

//+------------------------------------------------------------------+
//| Place pending orders                                             |
//+------------------------------------------------------------------+
void PlacePendingOrders()
{
    Print("--- Starting Order Placement Process ---");

    //--- Check for existing open positions
    int existing_positions = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) > 0 &&
           PositionGetString(POSITION_SYMBOL) == _Symbol &&
           PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            existing_positions++;
        }
    }

    if(existing_positions > 0)
    {
        Print("NOTE: ", existing_positions, " position(s) from previous day(s) still open");
        Print("Position tracking will be preserved for existing positions");
    }

    //--- Check ADX Volatility Filter before placing orders
    if(!CheckADXFilter())
    {
        Print("ADX Volatility Filter conditions NOT met - Skipping order placement for today");
        Print("=================================================");
        return;
    }

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
    Print("*** This R value will be used for the entire trading day ***");

    //--- Get current price and broker requirements
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    long stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    long freeze_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

    Print("Current Bid: ", DoubleToString(current_price, _Digits));
    Print("Current Ask: ", DoubleToString(ask_price, _Digits));
    Print("Broker Stops Level: ", stops_level, " points");
    Print("Broker Freeze Level: ", freeze_level, " points");

    //--- Calculate order prices (R/2 from current price)
    double half_R = current_R / 2.0;
    double buy_stop_price = ask_price + half_R;
    double sell_stop_price = current_price - half_R;

    Print("Half R: ", DoubleToString(half_R, _Digits));
    Print("Buy Stop Price: ", DoubleToString(buy_stop_price, _Digits), " (Ask + R/2)");
    Print("Sell Stop Price: ", DoubleToString(sell_stop_price, _Digits), " (Bid - R/2)");

    //--- Validate pending order distance from current price
    double buy_distance_points = (buy_stop_price - ask_price) / point;
    double sell_distance_points = (current_price - sell_stop_price) / point;

    Print("Buy Stop Distance: ", DoubleToString(buy_distance_points, 0), " points from Ask");
    Print("Sell Stop Distance: ", DoubleToString(sell_distance_points, 0), " points from Bid");

    if(stops_level > 0)
    {
        if(buy_distance_points < stops_level)
        {
            Print("WARNING: Buy Stop distance (", DoubleToString(buy_distance_points, 0), ") < Broker minimum (", stops_level, ")");
            Print("Adjusting Buy Stop price to meet broker requirements");
            buy_stop_price = ask_price + (stops_level * point);
        }

        if(sell_distance_points < stops_level)
        {
            Print("WARNING: Sell Stop distance (", DoubleToString(sell_distance_points, 0), ") < Broker minimum (", stops_level, ")");
            Print("Adjusting Sell Stop price to meet broker requirements");
            sell_stop_price = current_price - (stops_level * point);
        }
    }

    //--- Calculate stop loss distance
    double stop_loss_distance = current_R * StopLoss_R;
    Print("Stop Loss Distance: ", DoubleToString(stop_loss_distance, _Digits), " (", StopLoss_R, " R)");

    //--- Validate minimum stop loss
    double sl_points = stop_loss_distance / point;
    Print("Stop Loss in Points: ", DoubleToString(sl_points, 0));

    if(sl_points < MinStopLoss_Points)
    {
        Print("WARNING: Calculated SL (", DoubleToString(sl_points, 0), " points) is less than minimum (", MinStopLoss_Points, " points)");
        Print("Adjusting stop loss to minimum: ", MinStopLoss_Points, " points");
        stop_loss_distance = MinStopLoss_Points * point;
        sl_points = MinStopLoss_Points;
    }
    else
    {
        Print("Stop loss validation passed: ", DoubleToString(sl_points, 0), " points >= ", MinStopLoss_Points, " points (minimum)");
    }

    //--- Calculate stop loss and take profit levels
    double buy_sl = buy_stop_price - stop_loss_distance;
    double buy_tp = buy_stop_price + (current_R * TakeProfit_R);
    double sell_sl = sell_stop_price + stop_loss_distance;
    double sell_tp = sell_stop_price - (current_R * TakeProfit_R);

    Print("Buy Stop - SL: ", DoubleToString(buy_sl, _Digits), ", TP: ", DoubleToString(buy_tp, _Digits));
    Print("Sell Stop - SL: ", DoubleToString(sell_sl, _Digits), ", TP: ", DoubleToString(sell_tp, _Digits));

    //--- Validate SL/TP distances for pending orders
    if(stops_level > 0)
    {
        double buy_sl_distance = (buy_stop_price - buy_sl) / point;
        double buy_tp_distance = (buy_tp - buy_stop_price) / point;
        double sell_sl_distance = (sell_sl - sell_stop_price) / point;
        double sell_tp_distance = (sell_stop_price - sell_tp) / point;

        Print("Validating SL/TP distances against broker minimum (", stops_level, " points)");
        Print("  Buy SL distance: ", DoubleToString(buy_sl_distance, 0), " points");
        Print("  Buy TP distance: ", DoubleToString(buy_tp_distance, 0), " points");
        Print("  Sell SL distance: ", DoubleToString(sell_sl_distance, 0), " points");
        Print("  Sell TP distance: ", DoubleToString(sell_tp_distance, 0), " points");

        if(buy_sl_distance < stops_level || buy_tp_distance < stops_level ||
           sell_sl_distance < stops_level || sell_tp_distance < stops_level)
        {
            Print("WARNING: SL/TP distances may not meet broker requirements");
            Print("Consider increasing ATR_Multiplier or StopLoss_R/TakeProfit_R values");
        }
    }

    //--- Calculate lot size
    double calculated_lot_size = CalculateLotSize(stop_loss_distance);

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
    request.volume = calculated_lot_size;
    request.type = ORDER_TYPE_BUY_STOP;
    request.price = buy_stop_price;
    request.sl = buy_sl;
    request.tp = buy_tp;
    request.deviation = 10;
    request.magic = MagicNumber;
    request.comment = OrderComment + " - Buy";

    if(OrderSend(request, result))
    {
        Print("SUCCESS: Buy Stop order placed");
        Print("  Order Ticket: ", result.order);
        Print("  Volume: ", calculated_lot_size);
        Print("  Price: ", DoubleToString(buy_stop_price, _Digits));
        Print("  SL: ", DoubleToString(buy_sl, _Digits));
        Print("  TP: ", DoubleToString(buy_tp, _Digits));
        Print("  Comment: ", OrderComment + " - Buy");
    }
    else
    {
        Print("ERROR: Failed to place Buy Stop order");
        Print("  Error Code: ", result.retcode);
        Print("  Error Description: ", GetErrorDescription(result.retcode));
    }

    //--- Place Sell Stop order
    Print("--- Placing Sell Stop Order ---");

    //--- CRITICAL: Refresh price at LAST possible moment to handle market movement
    double current_bid_for_sell = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double safety_buffer = point * 2; // 2 point buffer to ensure order validity

    Print("Current Bid (refreshed just before order): ", DoubleToString(current_bid_for_sell, _Digits));

    //--- Always recalculate Sell Stop based on fresh price to handle backtesting delays
    sell_stop_price = current_bid_for_sell - half_R - safety_buffer;
    sell_sl = sell_stop_price + stop_loss_distance;
    sell_tp = sell_stop_price - (current_R * TakeProfit_R);

    // Re-normalize all prices
    sell_stop_price = NormalizeDouble(sell_stop_price, _Digits);
    sell_sl = NormalizeDouble(sell_sl, _Digits);
    sell_tp = NormalizeDouble(sell_tp, _Digits);

    Print("Recalculated Sell Stop Price: ", DoubleToString(sell_stop_price, _Digits), " (Bid - R/2 - buffer)");
    Print("Sell Stop SL: ", DoubleToString(sell_sl, _Digits), ", TP: ", DoubleToString(sell_tp, _Digits));
    Print("Safety buffer applied: ", DoubleToString(safety_buffer, _Digits));

    request.type = ORDER_TYPE_SELL_STOP;
    request.price = sell_stop_price;
    request.sl = sell_sl;
    request.tp = sell_tp;
    request.comment = OrderComment + " - Sell";

    if(OrderSend(request, result))
    {
        Print("SUCCESS: Sell Stop order placed");
        Print("  Order Ticket: ", result.order);
        Print("  Volume: ", calculated_lot_size);
        Print("  Price: ", DoubleToString(sell_stop_price, _Digits));
        Print("  SL: ", DoubleToString(sell_sl, _Digits));
        Print("  TP: ", DoubleToString(sell_tp, _Digits));
        Print("  Comment: ", OrderComment + " - Sell");
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

    //--- Get or create tracking for this position
    int tracking_index = GetPositionTrackingIndex(ticket);
    if(tracking_index < 0)
    {
        // Position not tracked yet (opened before EA started or from previous session)
        if(current_R <= 0)
        {
            Print("WARNING: Position ", ticket, " not tracked and no valid R value. Cannot manage position.");
            return;
        }
        Print("Position ", ticket, " not tracked. Adding to tracking with current R: ", DoubleToString(current_R, _Digits));
        AddPositionTracking(ticket, current_R);
        tracking_index = GetPositionTrackingIndex(ticket);
    }

    //--- Get position-specific tracking data
    double position_R = tracked_positions[tracking_index].entry_R;
    bool position_at_breakeven = tracked_positions[tracking_index].at_breakeven;
    double position_breakeven_price = tracked_positions[tracking_index].breakeven_reached_price;

    if(position_type == POSITION_TYPE_BUY)
    {
        current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

        //--- Calculate profit in terms of R (using R from when position was opened)
        double profit_points = current_price - position_open_price;
        double profit_in_R = profit_points / position_R;

        //--- Check if we need to move to breakeven
        if(!position_at_breakeven && profit_in_R >= BreakevenTrigger_R)
        {
            Print("=================================================");
            Print("BUY POSITION BREAKEVEN TRIGGER REACHED");
            Print("  Ticket: ", ticket);
            Print("  Open Price: ", DoubleToString(position_open_price, _Digits));
            Print("  Current Price: ", DoubleToString(current_price, _Digits));
            Print("  Profit: ", DoubleToString(profit_in_R, 2), " R");
            Print("  Position's R value: ", DoubleToString(position_R, _Digits));
            Print("  Moving Stop Loss to Breakeven with buffer");

            //--- Calculate breakeven price with buffer
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double breakeven_price = position_open_price + (BreakevenBuffer_Points * point);

            Print("  Breakeven Buffer: ", BreakevenBuffer_Points, " points");
            Print("  New Stop Loss: ", DoubleToString(breakeven_price, _Digits));
            Print("=================================================");

            MqlTradeRequest request = {};
            MqlTradeResult result = {};

            request.action = TRADE_ACTION_SLTP;
            request.symbol = _Symbol;
            request.position = ticket;
            request.sl = NormalizeDouble(breakeven_price, _Digits);
            request.tp = current_tp;

            if(OrderSend(request, result))
            {
                // Update tracking for this position
                tracked_positions[tracking_index].at_breakeven = true;
                tracked_positions[tracking_index].breakeven_reached_price = current_price;

                Print("SUCCESS: Stop Loss moved to breakeven + ", BreakevenBuffer_Points, " points at ", DoubleToString(breakeven_price, _Digits));
                Print("Waiting for price to move ", WaitPeriod_R, " R before further action");
                Print("Wait trigger price: ", DoubleToString(current_price + (position_R * WaitPeriod_R), _Digits));
            }
            else
            {
                Print("ERROR: Failed to modify position");
                Print("  Error Code: ", result.retcode);
                Print("  Error Description: ", GetErrorDescription(result.retcode));
            }
        }

        //--- Check wait period after breakeven
        if(position_at_breakeven)
        {
            double distance_from_breakeven = current_price - position_breakeven_price;
            double distance_in_R = distance_from_breakeven / position_R;

            // Activate ATR management when wait period is complete
            if(distance_in_R >= WaitPeriod_R)
            {
                if(!tracked_positions[tracking_index].wait_period_logged)
                {
                    Print("--- BUY POSITION: Wait period completed ---");
                    Print("  Ticket: ", ticket);
                    Print("  Current Price: ", DoubleToString(current_price, _Digits));
                    Print("  Distance since breakeven was reached: ", DoubleToString(distance_in_R, 2), " R");
                    Print("  Position's R value: ", DoubleToString(position_R, _Digits));
                    Print("  Activating ATR-based trailing stop management");

                    tracked_positions[tracking_index].wait_period_logged = true;
                }

                // Activate ATR management
                if(!tracked_positions[tracking_index].atr_management_active)
                {
                    tracked_positions[tracking_index].atr_management_active = true;
                    Print("  ATR trailing stop management is now ACTIVE");
                }

                //--- ATR-based trailing stop logic
                int current_timeframe_level = tracked_positions[tracking_index].timeframe_level;
                int max_timeframe_level = GetMaxTimeframeLevel();

                // If using below baseline method, lock to M1
                if(tracked_positions[tracking_index].use_below_baseline_method)
                {
                    current_timeframe_level = 0;
                    max_timeframe_level = 0;
                }

                // Check if we're on a new bar for this timeframe
                ENUM_TIMEFRAMES current_tf = GetTimeframeFromLevel(current_timeframe_level);
                datetime current_bar_time = iTime(_Symbol, current_tf, 0);

                if(current_bar_time != tracked_positions[tracking_index].last_bar_time)
                {
                    tracked_positions[tracking_index].last_bar_time = current_bar_time;

                    // Get ATR_Trend_Ind value for current timeframe
                    double atr_stop_value = GetATRTrendIndValue(tracking_index, current_timeframe_level, POSITION_TYPE_BUY);

                    if(atr_stop_value > 0)
                    {
                        // For BUY positions, ATR stop is below price (buffer 3)
                        // Check if new stop is better than current stop
                        if(atr_stop_value > current_sl || current_sl == 0)
                        {
                            // Attempt to update stop loss
                            MqlTradeRequest request = {};
                            MqlTradeResult result = {};

                            request.action = TRADE_ACTION_SLTP;
                            request.symbol = _Symbol;
                            request.position = ticket;
                            request.sl = NormalizeDouble(atr_stop_value, _Digits);
                            request.tp = current_tp;

                            if(OrderSend(request, result))
                            {
                                Print("--- ATR Trailing Stop Updated (BUY) ---");
                                Print("  Ticket: ", ticket);
                                Print("  Timeframe: ", GetTimeframeName(current_timeframe_level));
                                Print("  New SL: ", DoubleToString(atr_stop_value, _Digits));
                                Print("  Old SL: ", DoubleToString(current_sl, _Digits));

                                // Progress to next timeframe if not at max
                                if(current_timeframe_level < max_timeframe_level)
                                {
                                    tracked_positions[tracking_index].timeframe_level++;
                                    tracked_positions[tracking_index].last_bar_time = 0;  // Force check on next timeframe
                                    Print("  Progressed to timeframe: ", GetTimeframeName(tracked_positions[tracking_index].timeframe_level));

                                    // Clear cached value for new timeframe
                                    tracked_positions[tracking_index].cached_atr_values[tracked_positions[tracking_index].timeframe_level] = 0;
                                }
                                else
                                {
                                    Print("  At maximum timeframe level");
                                }
                            }
                            else
                            {
                                Print("WARNING: Failed to update ATR trailing stop");
                                Print("  Error: ", result.retcode, " - ", GetErrorDescription(result.retcode));
                            }
                        }
                    }
                }
            }
        }
    }
    else if(position_type == POSITION_TYPE_SELL)
    {
        current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

        //--- Calculate profit in terms of R (using R from when position was opened)
        double profit_points = position_open_price - current_price;
        double profit_in_R = profit_points / position_R;

        //--- Check if we need to move to breakeven
        if(!position_at_breakeven && profit_in_R >= BreakevenTrigger_R)
        {
            Print("=================================================");
            Print("SELL POSITION BREAKEVEN TRIGGER REACHED");
            Print("  Ticket: ", ticket);
            Print("  Open Price: ", DoubleToString(position_open_price, _Digits));
            Print("  Current Price: ", DoubleToString(current_price, _Digits));
            Print("  Profit: ", DoubleToString(profit_in_R, 2), " R");
            Print("  Position's R value: ", DoubleToString(position_R, _Digits));
            Print("  Moving Stop Loss to Breakeven with buffer");

            //--- Calculate breakeven price with buffer
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double breakeven_price = position_open_price - (BreakevenBuffer_Points * point);

            Print("  Breakeven Buffer: ", BreakevenBuffer_Points, " points");
            Print("  New Stop Loss: ", DoubleToString(breakeven_price, _Digits));
            Print("=================================================");

            MqlTradeRequest request = {};
            MqlTradeResult result = {};

            request.action = TRADE_ACTION_SLTP;
            request.symbol = _Symbol;
            request.position = ticket;
            request.sl = NormalizeDouble(breakeven_price, _Digits);
            request.tp = current_tp;

            if(OrderSend(request, result))
            {
                // Update tracking for this position
                tracked_positions[tracking_index].at_breakeven = true;
                tracked_positions[tracking_index].breakeven_reached_price = current_price;

                Print("SUCCESS: Stop Loss moved to breakeven - ", BreakevenBuffer_Points, " points at ", DoubleToString(breakeven_price, _Digits));
                Print("Waiting for price to move ", WaitPeriod_R, " R before further action");
                Print("Wait trigger price: ", DoubleToString(current_price - (position_R * WaitPeriod_R), _Digits));
            }
            else
            {
                Print("ERROR: Failed to modify position");
                Print("  Error Code: ", result.retcode);
                Print("  Error Description: ", GetErrorDescription(result.retcode));
            }
        }

        //--- Check wait period after breakeven
        if(position_at_breakeven)
        {
            double distance_from_breakeven = position_breakeven_price - current_price;
            double distance_in_R = distance_from_breakeven / position_R;

            // Activate ATR management when wait period is complete
            if(distance_in_R >= WaitPeriod_R)
            {
                if(!tracked_positions[tracking_index].wait_period_logged)
                {
                    Print("--- SELL POSITION: Wait period completed ---");
                    Print("  Ticket: ", ticket);
                    Print("  Current Price: ", DoubleToString(current_price, _Digits));
                    Print("  Distance since breakeven was reached: ", DoubleToString(distance_in_R, 2), " R");
                    Print("  Position's R value: ", DoubleToString(position_R, _Digits));
                    Print("  Activating ATR-based trailing stop management");

                    tracked_positions[tracking_index].wait_period_logged = true;
                }

                // Activate ATR management
                if(!tracked_positions[tracking_index].atr_management_active)
                {
                    tracked_positions[tracking_index].atr_management_active = true;
                    Print("  ATR trailing stop management is now ACTIVE");
                }

                //--- ATR-based trailing stop logic
                int current_timeframe_level = tracked_positions[tracking_index].timeframe_level;
                int max_timeframe_level = GetMaxTimeframeLevel();

                // If using below baseline method, lock to M1
                if(tracked_positions[tracking_index].use_below_baseline_method)
                {
                    current_timeframe_level = 0;
                    max_timeframe_level = 0;
                }

                // Check if we're on a new bar for this timeframe
                ENUM_TIMEFRAMES current_tf = GetTimeframeFromLevel(current_timeframe_level);
                datetime current_bar_time = iTime(_Symbol, current_tf, 0);

                if(current_bar_time != tracked_positions[tracking_index].last_bar_time)
                {
                    tracked_positions[tracking_index].last_bar_time = current_bar_time;

                    // Get ATR_Trend_Ind value for current timeframe
                    double atr_stop_value = GetATRTrendIndValue(tracking_index, current_timeframe_level, POSITION_TYPE_SELL);

                    if(atr_stop_value > 0)
                    {
                        // For SELL positions, ATR stop is above price (buffer 2)
                        // Check if new stop is better than current stop
                        if(atr_stop_value < current_sl || current_sl == 0)
                        {
                            // Attempt to update stop loss
                            MqlTradeRequest request = {};
                            MqlTradeResult result = {};

                            request.action = TRADE_ACTION_SLTP;
                            request.symbol = _Symbol;
                            request.position = ticket;
                            request.sl = NormalizeDouble(atr_stop_value, _Digits);
                            request.tp = current_tp;

                            if(OrderSend(request, result))
                            {
                                Print("--- ATR Trailing Stop Updated (SELL) ---");
                                Print("  Ticket: ", ticket);
                                Print("  Timeframe: ", GetTimeframeName(current_timeframe_level));
                                Print("  New SL: ", DoubleToString(atr_stop_value, _Digits));
                                Print("  Old SL: ", DoubleToString(current_sl, _Digits));

                                // Progress to next timeframe if not at max
                                if(current_timeframe_level < max_timeframe_level)
                                {
                                    tracked_positions[tracking_index].timeframe_level++;
                                    tracked_positions[tracking_index].last_bar_time = 0;  // Force check on next timeframe
                                    Print("  Progressed to timeframe: ", GetTimeframeName(tracked_positions[tracking_index].timeframe_level));

                                    // Clear cached value for new timeframe
                                    tracked_positions[tracking_index].cached_atr_values[tracked_positions[tracking_index].timeframe_level] = 0;
                                }
                                else
                                {
                                    Print("  At maximum timeframe level");
                                }
                            }
                            else
                            {
                                Print("WARNING: Failed to update ATR trailing stop");
                                Print("  Error: ", result.retcode, " - ", GetErrorDescription(result.retcode));
                            }
                        }
                    }
                }
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
