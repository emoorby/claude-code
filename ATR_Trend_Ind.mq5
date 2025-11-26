//+------------------------------------------------------------------+
//|                                                ATR_Trend_Ind.mq5 |
//|                                                 Roman Sokolowski |
//|                                                oromeks@gmail.com |
//+------------------------------------------------------------------+
#property copyright "Roman Sokolowski"
#property link      "oromeks@gmail.com"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_label1  "UP BUFFER"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrTeal
#property indicator_width1  0

#property indicator_label2  "DOWN BUFFER"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrTeal
#property indicator_width2  0

#property indicator_label3  "UP LINE"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrTeal
#property indicator_width3  1

#property indicator_label4  "DOWN LINE"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrTeal
#property indicator_width4  1

input int     ATR_Period = 10;
input double  ATR_Mod = 1.0;

double ATR_UP_Buffer[];
double ATR_DN_Buffer[];
double ATR_UP_Line_Buffer[];
double ATR_DN_Line_Buffer[];

int atr_handle;
int currBars;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- indicator buffers mapping
   SetIndexBuffer(0, ATR_UP_Buffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_ARROW, 159);

   SetIndexBuffer(1, ATR_DN_Buffer, INDICATOR_DATA);
   PlotIndexSetInteger(1, PLOT_ARROW, 159);

   SetIndexBuffer(2, ATR_UP_Line_Buffer, INDICATOR_DATA);

   SetIndexBuffer(3, ATR_DN_Line_Buffer, INDICATOR_DATA);

//--- Create ATR indicator handle
   atr_handle = iATR(_Symbol, _Period, ATR_Period);
   if(atr_handle == INVALID_HANDLE)
     {
      Print("Failed to create ATR indicator handle");
      return(INIT_FAILED);
     }

//--- Set empty value for plotting where nothing is drawn
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, 0.0);

//--- Set arrays as series (indexing from last to first)
   ArraySetAsSeries(ATR_UP_Buffer, true);
   ArraySetAsSeries(ATR_DN_Buffer, true);
   ArraySetAsSeries(ATR_UP_Line_Buffer, true);
   ArraySetAsSeries(ATR_DN_Line_Buffer, true);

   currBars = 0;

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- Release ATR indicator handle
   if(atr_handle != INVALID_HANDLE)
      IndicatorRelease(atr_handle);
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
//--- Check if enough bars
   if(rates_total < ATR_Period)
      return(0);

//--- Set arrays as series for input arrays
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(time, true);

//--- Get ATR values
   double atr[];
   ArraySetAsSeries(atr, true);

//--- Determine recalculation logic
   int limit;
   if(currBars != rates_total)
     {
      limit = rates_total - ATR_Period;
      currBars = rates_total;
     }
   else
     {
      limit = rates_total - prev_calculated;
      if(prev_calculated > 0)
         limit++;
     }

//--- Copy ATR values
   if(CopyBuffer(atr_handle, 0, 0, limit + 1, atr) <= 0)
     {
      Print("Failed to copy ATR buffer");
      return(0);
     }

//--- Main calculation loop
   double high_dot = 0, low_dot = 0;
   double high_dot_0 = 0, low_dot_0 = 0;
   bool sell_mode = false, buy_mode = false;
   bool sell_mode_0 = false, buy_mode_0 = false;

   if(limit > 10)
      limit--;

   for(int i = limit; i > 0; i--)
     {
      //--- Initialize buffers with empty values
      ATR_UP_Buffer[i] = 0.0;
      ATR_DN_Buffer[i] = 0.0;
      ATR_UP_Line_Buffer[i] = 0.0;
      ATR_DN_Line_Buffer[i] = 0.0;

      double atr_value = atr[i];

      double up_atr = high[i] + (atr_value * ATR_Mod);
      double low_atr = low[i] - (atr_value * ATR_Mod);

      bool is_high = false, is_low = false;
      if(high_dot == 0 || low_atr > high_dot)
        {
         high_dot = low_atr;
         is_high = true;
        }
      if(low_dot == 0 || up_atr < low_dot)
        {
         low_dot = up_atr;
         is_low = true;
        }

      if(low[i] < high_dot && high_dot > 0)
        {
         sell_mode = true;
         buy_mode = false;

         high_dot = 0;
        }

      if(high[i] > low_dot && low_dot > 0)
        {
         sell_mode = false;
         buy_mode = true;

         low_dot = 0;
        }

      if(buy_mode)
        {
         if(is_high)
            ATR_DN_Buffer[i] = low_atr;
         ATR_DN_Line_Buffer[i] = high_dot;

         if(sell_mode_0)
           {
            ATR_DN_Buffer[i] = low_dot_0 - (atr_value * ATR_Mod);
            ATR_DN_Line_Buffer[i] = low_dot_0 - (atr_value * ATR_Mod);
            high_dot = low_dot_0 - (atr_value * ATR_Mod);
           }

         low_dot = 0;
        }
      if(sell_mode)
        {
         if(is_low)
            ATR_UP_Buffer[i] = up_atr;
         ATR_UP_Line_Buffer[i] = low_dot;

         if(buy_mode_0)
           {
            ATR_UP_Buffer[i] = high_dot_0 + (atr_value * ATR_Mod);
            ATR_UP_Line_Buffer[i] = high_dot_0 + (atr_value * ATR_Mod);
            low_dot = high_dot_0 + (atr_value * ATR_Mod);
           }

         high_dot = 0;
        }

      buy_mode_0 = buy_mode;
      sell_mode_0 = sell_mode;
      high_dot_0 = high_dot;
      low_dot_0 = low_dot;
     }

//--- return value of prev_calculated for next call
   return(rates_total);
  }
//+------------------------------------------------------------------+
