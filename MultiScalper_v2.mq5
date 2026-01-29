// MultiScalper Version 2
// Tidy code and added account protection

#include <Trade/Trade.mqh>

   CTrade                  trade;
   CPositionInfo           posinfo;
   COrderInfo              ord;

         enum              enumSystemType{Fixed_pips_profile=0, Pct_of_Price_profile=1};
         enum              enumLotType{Fixed_Lots=0, Pct_of_Balance=1, Pct_of_Equity=2, Pct_of_Free_Margin=3};
         enum              StartHour{Inactive=0, _0100=1, _0200=2, _0300=3, _0400=4, _0500=5, _0600=6, _0700=7, _0800=8, _0900=9, _1000=10, _1100=11, _1200=12, _1300=13, _1400=14, _1500=15, _1600=16, _1700=17, _1800=18, _1900=19, _2000=20, _2100=21, _2200=22, _2300=23};
         enum              EndHour{EInactive=0, E_0100=1, E_0200=2, E_0300=3, E_0400=4, E_0500=5, E_0600=6, E_0700=7, E_0800=8, E_0900=9, E_1000=10, E_1100=11, E_1200=12, E_1300=13, E_1400=14, E_1500=15, E_1600=16, E_1700=17, E_1800=18, E_1900=19, E_2000=20, E_2100=21, E_2200=22, E_2300=23};
         int               handleRSI, handleMovAvg, handleADX, handleADXDynamic;

         double            BegofDayBalance;
         double            DD_1D_Pct=0, Prf_1D_Pct=0;
         double            EqHigh_1D=0;

   input group "=== Trading Profiles ==="

         input             enumSystemType SType=0;

   input group "=== Common Trading Inputs ==="

         input enumLotType       LotType           = 1;
         input double            FixedLots         = 0.01;
         input double            RiskPercent       = 2;
         input ENUM_TIMEFRAMES   Timeframe         = PERIOD_M5;
         input int               InpMagic          = 12345;
         input string            TradeComment      = "MultiScalper";
         input StartHour         SHInput           = 7;
         input EndHour           EHInput           = 21;

         input int               BarsN             = 100;
         input int               ExpirationBars    = 300;



         input color             ChartColorTradingOff = clrPurple;
         input color             ChartColorTradingOn  = clrBlack;
               bool              Tradingenabled       = true;
         input bool              HideIndicators       = true;
               string            TradingEnabledComm   = "";

   input group "=== Forex Trading Inputs ==="

         input int               TppointsInput           = 200;
         input int               SlPointsInput           = 200;
         input int               TslTriggerPointsInput   = 15;
         input int               TslPointsInput          = 10;
         input double            OrderDistPointsInput    = 100;
         double                  Tppoints, SlPoints, TslTriggerPoints, TslPoints, OrderDistPoints;

   input group "=== as % of Price Profile Inputs ==="

         input double            TPasPct           = 0.4;
         input double            SlasPct           = 0.4;
         input double            TSLasPctofSL      = 5;
         input double            TSLTgrasPctofSL   = 7;
         input double            OrdDisPtasPctofSL = 50;

   input group "=== Smart Exit Settings ==="

         input bool              SmartExitOn             = true;           // Enable Smart Exit Feature
         input int               ADX_Period              = 14;             // ADX Period
         input double            DI_DeclinePct           = 25;             // DI Decline % (Condition 1)
         input int               DI_DeclineBars          = 5;              // Bars to check DI decline
         input double            PriceReversalPct        = 40;             // Price Reversal % of SL distance (Condition 1 & 3)
         input int               RapidReversalBars       = 2;              // Bars for rapid reversal check (Condition 3)

   // Smart Exit tracking variables
   struct SmartExitTracker {
      bool        isTracking;           // Whether we're tracking this position
      ulong       ticket;               // Position ticket
      double      entryPrice;           // Entry price
      double      originalSL;           // Original stop loss (before trailing)
      double      entryDIplus;          // DI+ at entry (for buys)
      double      entryDIminus;         // DI- at entry (for sells)
      datetime    entryBarTime;         // Bar time at entry
      int         barsSinceEntry;       // Count of bars since entry
      bool        condition1Checked;    // Whether condition 1 has been checked at bar 5
      bool        condition3Active;     // Whether condition 3 is still active (first 2 bars)
   };

   SmartExitTracker buyTracker;
   SmartExitTracker sellTracker;

   input group "=== Dynamic BarsN Settings ==="

         input bool              DynamicBarsNOn          = true;           // Enable Dynamic BarsN
         input ENUM_TIMEFRAMES   ADXDynTimeframe         = PERIOD_M5;     // ADX Timeframe for Dynamic BarsN
         input int               ADXDynPeriod            = 14;            // ADX Period for Dynamic BarsN

         int               ActiveBarsN;             // Current active BarsN value
         int               ActiveExpirationBars;    // Current active ExpirationBars value
         int               CurrentADXLevel = -1;    // Track current ADX level for change logging

   input group "=== News Filter ==="

         input bool              NewsFilterOn      = true;
         enum sep_dropdown{comma=0,semicolon=1};
         input sep_dropdown      separator         = 0;
         input string            KeyNews           = "BCB,NFP,JOLTS,Nonfarm,PMI,Retail,GDP,Confidence,Interest Rate";
         input string            NewsCurrencies    = "USD,GBP,EUR,JPY";
         input int               DaysNewsLookup    = 100;
         input int               StopBeforeMin     = 15;
         input int               StartTradingMin   = 15;
               bool              TrDisabledNews    = false;

         ushort      sep_code;
         string      Newstoavoid[];
         datetime    LastNewsAvoided;

   input group "=== RSI Filter ==="

         input bool              RSIFilterOn       = false;
         input ENUM_TIMEFRAMES   RSITimeframe      = PERIOD_H1;
         input int               RSIlowerlvl       = 20;
         input int               RSIUpperlvl       = 80;
         input int               RSI_MA            = 14;
         input ENUM_APPLIED_PRICE   RSI_AppPrice   = PRICE_MEDIAN;

   input group "=== Moving Average Filter ==="

         input bool              MAFilterOn         = false;
         input ENUM_TIMEFRAMES   MATimeframe        = PERIOD_H4;
         input double            PctPricefromMA     = 3;
         input int               MA_Period          = 200;
         input ENUM_MA_METHOD    MA_Mode            = MODE_EMA;
         input ENUM_APPLIED_PRICE   MA_AppPrice     = PRICE_MEDIAN;

   input group "=== Trading Allowed by Days ==="

         input bool          AllowedMonday     = true;
         input bool          AllowedTuesday    = true;
         input bool          AllowedWednesday  = true;
         input bool          AllowedThursday   = true;
         input bool          AllowedFriday     = true;
         input bool          AllowedSaturday   = true;
         input bool          AllowedSunday     = true;
               bool          DayFilterOn       = true;

    input group "=== Drawdown Control Settings ==="

         input double         MaxDDay = 2;

int OnInit(){

   trade.SetExpertMagicNumber(InpMagic);
   BegofDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   ChartSetInteger(0,CHART_SHOW_GRID,false);

   double ask                 = SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   switch(SType){
      case 0:
            Tppoints          = TppointsInput;
            SlPoints          = SlPointsInput;
            TslTriggerPoints  = TslTriggerPointsInput;
            TslPoints         = TslPointsInput;
            OrderDistPoints   = OrderDistPointsInput;
            break;
      case 1:
            Tppoints          = ask       * TPasPct/100/_Point;
            SlPoints          = ask       * SlasPct/100/_Point;
            OrderDistPoints   = SlPoints  * OrdDisPtasPctofSL/100;
            TslTriggerPoints  = SlPoints  * TSLTgrasPctofSL/100;
            TslPoints         = SlPoints  * TSLasPctofSL/100;
            break;
   }

   int stoplevel = (int) SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   Print("Minimum Stoploss Distance Required by Broker on ", _Symbol, ": ", stoplevel, " points.");

   if(TslPoints<stoplevel){
      Print("Trailing Stoploss value of ", (int)TslPoints, " is smaller than allowed by broker.");
      Print("Overriding to broker Minimum of ", stoplevel, " points.");
      TslPoints = stoplevel;
   }else
   {
      Print("Current Trailing Stop value of ", (int)TslPoints, " is OK.");
    }

   TesterHideIndicators(false);
   if(HideIndicators==true) TesterHideIndicators(true);

   handleRSI = iRSI(_Symbol,RSITimeframe,RSI_MA,RSI_AppPrice);
   handleMovAvg = iMA(_Symbol,MATimeframe,MA_Period,0,MA_Mode,MA_AppPrice);

   // Initialize ADX indicator for Smart Exit
   if(SmartExitOn){
      handleADX = iADX(_Symbol, Timeframe, ADX_Period);
      if(handleADX == INVALID_HANDLE){
         Print("Error creating ADX indicator handle");
         return(INIT_FAILED);
      }
   }

   // Initialize Smart Exit trackers
   ResetSmartExitTracker(buyTracker);
   ResetSmartExitTracker(sellTracker);

   // Initialize Dynamic BarsN ADX handle
   if(DynamicBarsNOn){
      handleADXDynamic = iADX(_Symbol, ADXDynTimeframe, ADXDynPeriod);
      if(handleADXDynamic == INVALID_HANDLE){
         Print("Error creating ADX indicator handle for Dynamic BarsN");
         return(INIT_FAILED);
      }
      ActiveBarsN = BarsN;
      ActiveExpirationBars = ExpirationBars;
      CurrentADXLevel = -1;
   }
   else{
      ActiveBarsN = BarsN;
      ActiveExpirationBars = ExpirationBars;
   }

   return(INIT_SUCCEEDED);
}


void OnDeinit(const int reason){
   if(handleADX != INVALID_HANDLE){
      IndicatorRelease(handleADX);
   }
   if(handleADXDynamic != INVALID_HANDLE){
      IndicatorRelease(handleADXDynamic);
   }
}


void OnTick(){

   TrailStop();

   // Smart Exit check - runs on every tick for responsive exits
   if(SmartExitOn){
      CheckSmartExit();
   }

   if(!IsNewBar()) return;

   // Update Dynamic BarsN on every new bar
   UpdateDynamicBarsN();

   // Update bar counts for Smart Exit tracking on new bar
   if(SmartExitOn){
      UpdateSmartExitBarCounts();
   }

   UpdateInitialBalances();
   UpdatePropfirmValues();
   IsTradingAllowedPropValues();

if( IsRSIFilter() || IsUpcomingNews() || IsMAFilter() || !IsTradingAllowedbyDay() || !IsTradingAllowedPropValues()){
      CloseAllOrders();
      Tradingenabled=false;
      ChartSetInteger(0,CHART_COLOR_BACKGROUND,ChartColorTradingOff);
      if(TradingEnabledComm!="Printed")
         Print(_Symbol, ": ", TradingEnabledComm);
      TradingEnabledComm="Printed";
      return;
   }

   Tradingenabled=true;
   if(TradingEnabledComm!=""){
      Print("Trading is enabled again");
      TradingEnabledComm = "";
   }

   ChartSetInteger(0,CHART_COLOR_BACKGROUND,ChartColorTradingOn);

   MqlDateTime time;
   TimeToStruct(TimeCurrent(),time);

   int Hournow = time.hour;

   if(Hournow<SHInput){CloseAllOrders(); return;}
   if(Hournow>=EHInput && EHInput!=0){CloseAllOrders(); return;}

   int BuyTotal=0;
   int SellTotal=0;

   for (int i=OrdersTotal()-1; i>=0; i--){
      ord.SelectByIndex(i);
      if(ord.OrderType()==ORDER_TYPE_BUY_STOP && ord.Symbol()==_Symbol && ord.Magic()==InpMagic) BuyTotal++;
      if(ord.OrderType()==ORDER_TYPE_SELL_STOP && ord.Symbol()==_Symbol && ord.Magic()==InpMagic) SellTotal++;
   }

   for (int i=PositionsTotal()-1; i>=0; i--){
      posinfo.SelectByIndex(i);
      if(posinfo.PositionType()==POSITION_TYPE_BUY && posinfo.Symbol()==_Symbol && posinfo.Magic()==InpMagic) BuyTotal++;
      if(posinfo.PositionType()==POSITION_TYPE_SELL && posinfo.Symbol()==_Symbol && posinfo.Magic()==InpMagic) SellTotal++;
   }

   if(BuyTotal <=0){
      double high = findHigh();
      if(high > 0){
         executeBuy(high);
      }
   }

   if(SellTotal <=0){
      double low = findLow();
      if(low > 0){
         executeSell(low);
      }
   }

}


//+------------------------------------------------------------------+
//| Smart Exit Functions                                              |
//+------------------------------------------------------------------+

void ResetSmartExitTracker(SmartExitTracker &tracker){
   tracker.isTracking = false;
   tracker.ticket = 0;
   tracker.entryPrice = 0;
   tracker.originalSL = 0;
   tracker.entryDIplus = 0;
   tracker.entryDIminus = 0;
   tracker.entryBarTime = 0;
   tracker.barsSinceEntry = 0;
   tracker.condition1Checked = false;
   tracker.condition3Active = true;
}

void InitializeSmartExitTracker(SmartExitTracker &tracker, ulong ticket, double entryPrice, double sl, bool isBuy){
   tracker.isTracking = true;
   tracker.ticket = ticket;
   tracker.entryPrice = entryPrice;
   tracker.originalSL = sl;
   tracker.entryBarTime = iTime(_Symbol, Timeframe, 0);
   tracker.barsSinceEntry = 0;
   tracker.condition1Checked = false;
   tracker.condition3Active = true;

   // Get current DI values
   double DIplus[], DIminus[];
   ArraySetAsSeries(DIplus, true);
   ArraySetAsSeries(DIminus, true);

   if(CopyBuffer(handleADX, 1, 0, 1, DIplus) > 0 && CopyBuffer(handleADX, 2, 0, 1, DIminus) > 0){
      tracker.entryDIplus = DIplus[0];
      tracker.entryDIminus = DIminus[0];
   }

   Print("Smart Exit: Initialized tracker for ", (isBuy ? "BUY" : "SELL"),
         " ticket=", ticket, " entry=", entryPrice, " SL=", sl,
         " DI+=", tracker.entryDIplus, " DI-=", tracker.entryDIminus);
}

void UpdateSmartExitBarCounts(){
   datetime currentBarTime = iTime(_Symbol, Timeframe, 0);

   // Update buy tracker
   if(buyTracker.isTracking && currentBarTime != buyTracker.entryBarTime){
      int barIndex = iBarShift(_Symbol, Timeframe, buyTracker.entryBarTime);
      buyTracker.barsSinceEntry = barIndex;

      // Disable condition 3 after rapid reversal window
      if(buyTracker.barsSinceEntry > RapidReversalBars){
         buyTracker.condition3Active = false;
      }
   }

   // Update sell tracker
   if(sellTracker.isTracking && currentBarTime != sellTracker.entryBarTime){
      int barIndex = iBarShift(_Symbol, Timeframe, sellTracker.entryBarTime);
      sellTracker.barsSinceEntry = barIndex;

      // Disable condition 3 after rapid reversal window
      if(sellTracker.barsSinceEntry > RapidReversalBars){
         sellTracker.condition3Active = false;
      }
   }
}

void CheckSmartExit(){
   // Check for active positions and initialize tracking if needed
   for(int i = PositionsTotal() - 1; i >= 0; i--){
      if(posinfo.SelectByIndex(i)){
         if(posinfo.Magic() == InpMagic && posinfo.Symbol() == _Symbol){
            ulong ticket = posinfo.Ticket();

            if(posinfo.PositionType() == POSITION_TYPE_BUY){
               // Initialize tracker if this is a new position
               if(!buyTracker.isTracking || buyTracker.ticket != ticket){
                  InitializeSmartExitTracker(buyTracker, ticket, posinfo.PriceOpen(), posinfo.StopLoss(), true);
               }

               // Check exit conditions for buy
               if(CheckSmartExitConditions(buyTracker, true)){
                  Print("Smart Exit: Closing BUY position ticket=", ticket);
                  trade.PositionClose(ticket);
                  ResetSmartExitTracker(buyTracker);
               }
            }
            else if(posinfo.PositionType() == POSITION_TYPE_SELL){
               // Initialize tracker if this is a new position
               if(!sellTracker.isTracking || sellTracker.ticket != ticket){
                  InitializeSmartExitTracker(sellTracker, ticket, posinfo.PriceOpen(), posinfo.StopLoss(), false);
               }

               // Check exit conditions for sell
               if(CheckSmartExitConditions(sellTracker, false)){
                  Print("Smart Exit: Closing SELL position ticket=", ticket);
                  trade.PositionClose(ticket);
                  ResetSmartExitTracker(sellTracker);
               }
            }
         }
      }
   }

   // Reset trackers if positions no longer exist
   if(buyTracker.isTracking){
      bool found = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--){
         if(posinfo.SelectByIndex(i)){
            if(posinfo.Ticket() == buyTracker.ticket){
               found = true;
               break;
            }
         }
      }
      if(!found){
         ResetSmartExitTracker(buyTracker);
      }
   }

   if(sellTracker.isTracking){
      bool found = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--){
         if(posinfo.SelectByIndex(i)){
            if(posinfo.Ticket() == sellTracker.ticket){
               found = true;
               break;
            }
         }
      }
      if(!found){
         ResetSmartExitTracker(sellTracker);
      }
   }
}

bool CheckSmartExitConditions(SmartExitTracker &tracker, bool isBuy){
   if(!tracker.isTracking) return false;

   // Get current DI values
   double DIplus[], DIminus[];
   ArraySetAsSeries(DIplus, true);
   ArraySetAsSeries(DIminus, true);

   // Need enough bars for condition 1 check
   int barsNeeded = DI_DeclineBars + 1;

   if(CopyBuffer(handleADX, 1, 0, barsNeeded, DIplus) <= 0 ||
      CopyBuffer(handleADX, 2, 0, barsNeeded, DIminus) <= 0){
      return false;
   }

   double currentDIplus = DIplus[0];
   double currentDIminus = DIminus[0];
   double prevDIplus = DIplus[1];  // Previous bar for crossover detection
   double prevDIminus = DIminus[1];

   double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double slDistance = MathAbs(tracker.entryPrice - tracker.originalSL);
   double priceReversal = isBuy ? (tracker.entryPrice - currentPrice) : (currentPrice - tracker.entryPrice);
   double reversalPct = (slDistance > 0) ? (priceReversal / slDistance) * 100 : 0;

   // Condition 2: DI Crossover (check on every tick)
   if(isBuy){
      // For buy: exit when DI- crosses above DI+ (bearish signal)
      if(prevDIplus > prevDIminus && currentDIminus >= currentDIplus){
         Print("Smart Exit Condition 2: DI- crossed above DI+ for BUY position");
         Print("  Previous: DI+=", prevDIplus, " DI-=", prevDIminus);
         Print("  Current: DI+=", currentDIplus, " DI-=", currentDIminus);
         return true;
      }
   }
   else{
      // For sell: exit when DI+ crosses above DI- (bullish signal)
      if(prevDIminus > prevDIplus && currentDIplus >= currentDIminus){
         Print("Smart Exit Condition 2: DI+ crossed above DI- for SELL position");
         Print("  Previous: DI+=", prevDIplus, " DI-=", prevDIminus);
         Print("  Current: DI+=", currentDIplus, " DI-=", currentDIminus);
         return true;
      }
   }

   // Condition 3: Rapid price reversal within first N bars
   if(tracker.condition3Active && tracker.barsSinceEntry <= RapidReversalBars){
      if(reversalPct >= PriceReversalPct){
         Print("Smart Exit Condition 3: Rapid reversal of ", DoubleToString(reversalPct, 2),
               "% within ", tracker.barsSinceEntry, " bars for ", (isBuy ? "BUY" : "SELL"));
         Print("  Entry=", tracker.entryPrice, " Current=", currentPrice, " SL Distance=", slDistance);
         return true;
      }
   }

   // Condition 1: DI decline + price reversal (check only at bar 5)
   if(!tracker.condition1Checked && tracker.barsSinceEntry == DI_DeclineBars){
      tracker.condition1Checked = true;

      double DIatEntry, DIatBar5;
      if(isBuy){
         DIatEntry = tracker.entryDIplus;
         DIatBar5 = currentDIplus;
      }
      else{
         DIatEntry = tracker.entryDIminus;
         DIatBar5 = currentDIminus;
      }

      double DIDecline = (DIatEntry > 0) ? ((DIatEntry - DIatBar5) / DIatEntry) * 100 : 0;

      Print("Smart Exit Condition 1 Check at bar ", DI_DeclineBars, ":");
      Print("  DI at entry=", DIatEntry, " DI now=", DIatBar5, " Decline=", DoubleToString(DIDecline, 2), "%");
      Print("  Price reversal=", DoubleToString(reversalPct, 2), "%");

      if(DIDecline >= DI_DeclinePct && reversalPct >= PriceReversalPct){
         Print("Smart Exit Condition 1: DI declined ", DoubleToString(DIDecline, 2),
               "% and price reversed ", DoubleToString(reversalPct, 2), "% for ", (isBuy ? "BUY" : "SELL"));
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Dynamic BarsN Functions                                           |
//+------------------------------------------------------------------+

void UpdateDynamicBarsN(){
   if(!DynamicBarsNOn) return;

   double ADXVal[];
   ArraySetAsSeries(ADXVal, true);

   if(CopyBuffer(handleADXDynamic, 0, 0, 1, ADXVal) <= 0){
      Print("Error reading ADX for Dynamic BarsN");
      return;
   }

   double adxNow = ADXVal[0];
   int newLevel = -1;

   // Evaluate from highest threshold down so most specific match wins
   if(adxNow > 50){
      newLevel = 5;
      ActiveBarsN = 15;
      ActiveExpirationBars = 100;
   }
   else if(adxNow > 40){
      newLevel = 4;
      ActiveBarsN = 30;
      ActiveExpirationBars = 100;
   }
   else if(adxNow > 30){
      newLevel = 3;
      ActiveBarsN = 50;
      ActiveExpirationBars = 100;
   }
   else if(adxNow >= 25){
      newLevel = 2;
      ActiveBarsN = 80;
      ActiveExpirationBars = 120;
   }
   else if(adxNow >= 20){
      newLevel = 1;
      ActiveBarsN = 100;
      ActiveExpirationBars = 170;
   }
   else{
      newLevel = 0;
      ActiveBarsN = 100;
      ActiveExpirationBars = 300;
   }

   // Log only when ADX level changes
   if(newLevel != CurrentADXLevel){
      string tfString = GetTimeframeString(ADXDynTimeframe);
      Print("ADX Level switched to: ", CurrentADXLevel, " | ADX ", tfString, " = ",
            DoubleToString(adxNow, 2), " | BarsN = ", ActiveBarsN,
            " | ExpirationBars = ", ActiveExpirationBars);
      CurrentADXLevel = newLevel;
   }
}

string GetTimeframeString(ENUM_TIMEFRAMES tf){
   switch(tf){
      case PERIOD_M1:  return "M1";
      case PERIOD_M2:  return "M2";
      case PERIOD_M3:  return "M3";
      case PERIOD_M4:  return "M4";
      case PERIOD_M5:  return "M5";
      case PERIOD_M6:  return "M6";
      case PERIOD_M10: return "M10";
      case PERIOD_M12: return "M12";
      case PERIOD_M15: return "M15";
      case PERIOD_M20: return "M20";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H3:  return "H3";
      case PERIOD_H4:  return "H4";
      case PERIOD_H6:  return "H6";
      case PERIOD_H8:  return "H8";
      case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default:         return "Unknown";
   }
}

//+------------------------------------------------------------------+


bool IsNewBar(){
      static datetime previousTime = 0;
      datetime currentTime = iTime(_Symbol,Timeframe,0);
      if(previousTime!=currentTime){
         previousTime=currentTime;
         return true;
      }
      return false;
}

double findHigh(){

      int barsN = ActiveBarsN;
      double highestHigh = 0;

      for(int i = 0; i < 200; i++){
         double high = iHigh(_Symbol,Timeframe,i);
         if(i > barsN && iHighest(_Symbol,Timeframe,MODE_HIGH,barsN*2+1,i-barsN) == i){
            if(high > highestHigh){
               return high;
            }
      }
        highestHigh = MathMax(high,highestHigh);
       }
       return -1;
}

double findLow(){
      int barsN = ActiveBarsN;
      double lowestLow = DBL_MAX;
      for(int i = 0; i < 200; i++){
         double low = iLow(_Symbol,Timeframe,i);
         if(i > barsN && iLowest(_Symbol,Timeframe,MODE_LOW,barsN*2+1,i-barsN) == i){
            if(low < lowestLow){
               return low;
            }
         }
         lowestLow = MathMin(low,lowestLow);
      }
      return -1;
}

double calcLots(double slPoints){

      double lots             = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
      double AccountBalance   = AccountInfoDouble(ACCOUNT_BALANCE);
      double EquityBalance    = AccountInfoDouble(ACCOUNT_EQUITY);
      double FreeMargin       = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

      double risk = 0;

      switch(LotType){
         case 0: lots=  FixedLots; return lots;
         case 1: risk = AccountBalance * RiskPercent / 100; break;
         case 2: risk = EquityBalance * RiskPercent / 100; break;
         case 3: risk = FreeMargin * RiskPercent / 100; break;
      }

      double ticksize = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      double tickvalue = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
      double lotstep = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

      double moneyPerLotstep = slPoints / ticksize * tickvalue * lotstep;
             lots = MathFloor(risk / moneyPerLotstep) * lotstep;


      double minvolume=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
      double maxvolume=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MAX);
      double volumelimit = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_LIMIT);

      if(volumelimit!=0) lots = MathMin(lots,volumelimit);
      if(maxvolume!=0) lots = MathMin(lots,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX));
      if(minvolume!=0) lots = MathMax(lots,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN));
      lots = NormalizeDouble(lots,2);

      return lots;

}


void executeBuy(double entry){

         double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);

         if(ask > entry - OrderDistPoints * _Point) return;

         double tp = entry + Tppoints * _Point;
         double sl = entry - SlPoints*_Point;

         double lots = 0.01;
         if(RiskPercent > 0) lots = calcLots(entry-sl);

         datetime expiration = iTime(_Symbol,Timeframe,0) + ActiveExpirationBars * PeriodSeconds(Timeframe);

         trade.BuyStop(lots,entry,_Symbol,sl,tp,ORDER_TIME_SPECIFIED,expiration);
}

void executeSell(double entry){

         double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
         if(bid < entry + OrderDistPoints * _Point) return;

         double tp = entry - Tppoints * _Point;
         double sl = entry + SlPoints*_Point;

         double lots = 0.01;
         if(RiskPercent > 0) lots = calcLots(sl-entry);

         datetime expiration = iTime(_Symbol,Timeframe,0) + ActiveExpirationBars * PeriodSeconds(Timeframe);

           trade.SellStop(lots,entry,_Symbol,sl,tp,ORDER_TIME_SPECIFIED,expiration);

}


void CloseAllOrders(){

   for(int i=OrdersTotal()-1;i>=0;i--){
      ord.SelectByIndex(i);
      ulong ticket = ord.Ticket();
      if(ord.Symbol()==_Symbol && ord.Magic()==InpMagic){
         trade.OrderDelete(ticket);
      }
   }

}


void TrailStop(){
         double sl = 0;
         double tp = 0;
         double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);

          for (int i=PositionsTotal()-1; i>=0; i--){
            if(posinfo.SelectByIndex(i)){
               ulong ticket = posinfo.Ticket();
               if(posinfo.Magic()==InpMagic && posinfo.Symbol()==_Symbol){
                  if(posinfo.PositionType()==POSITION_TYPE_BUY){
                     if(bid-posinfo.PriceOpen()>TslTriggerPoints*_Point){
                        tp = posinfo.TakeProfit();
                        sl = bid - (TslPoints * _Point);
                        if(sl > posinfo.StopLoss() && sl!=0){
                             trade.PositionModify(ticket,sl,tp);
                        }
                     }
                  }  else if(posinfo.PositionType()==POSITION_TYPE_SELL){
                     if(ask+(TslTriggerPoints*_Point)<posinfo.PriceOpen()){
                        tp = posinfo.TakeProfit();
                        sl = ask + (TslPoints * _Point);
                        if(sl < posinfo.StopLoss() && sl!=0){
                             trade.PositionModify(ticket,sl,tp);
                        }
                     }
                  }
               }
            }
          }
}

bool IsUpcomingNews(){

   if(NewsFilterOn==false) return(false);

   if(TrDisabledNews && TimeCurrent()-LastNewsAvoided < StartTradingMin*PeriodSeconds(PERIOD_M1)) return true;

   TrDisabledNews=false;

   string sep;
   switch(separator){
      case 0: sep = ","; break;
      case 1: sep = ";";
   }

   sep_code = StringGetCharacter(sep,0);

   int k = StringSplit(KeyNews,sep_code,Newstoavoid);

   MqlCalendarValue values[];
   datetime starttime = TimeCurrent(); //iTime(_Symbol,PERIOD_D1,0);
   datetime endtime   = starttime + PeriodSeconds(PERIOD_D1)*DaysNewsLookup;

   CalendarValueHistory(values,starttime,endtime,NULL,NULL);

   for(int i = 0; i < ArraySize(values); i++){
      MqlCalendarEvent event;
      CalendarEventById(values[i].event_id, event);
      MqlCalendarCountry country;
      CalendarCountryById(event.country_id,country);

      if(StringFind(NewsCurrencies,country.currency) < 0) continue;

         for(int j=0; j<k; j++){
            string currentevent = Newstoavoid[j];
            string currentnews = event.name;
            if(StringFind(currentnews,currentevent) < 0) continue;

            Comment("Next News: ", country.currency ,": ", event.name, " -> ", values[i].time);
            if(values[i].time - TimeCurrent() < StopBeforeMin*PeriodSeconds(PERIOD_M1)){
               LastNewsAvoided = values[i].time;
               TrDisabledNews = true;
               if(TradingEnabledComm=="" || TradingEnabledComm!="Printed"){
                  TradingEnabledComm = "Trading is disabled due to upcoming news: " + event.name;
               }
               return true;
            }
       return false;

         }
   }

   return false;
}


bool IsRSIFilter(){

   if(RSIFilterOn==false) return(false);

   double RSI[];

   CopyBuffer(handleRSI,MAIN_LINE,0,1,RSI);
   ArraySetAsSeries(RSI,true);

   double RSInow = RSI[0];

   if(RSInow>RSIUpperlvl || RSInow<RSIlowerlvl){
      if(TradingEnabledComm=="" || TradingEnabledComm!="Printed"){
         TradingEnabledComm = "Trading is disabled due to RSI filter. RSI now = " + DoubleToString(RSInow);
      }
      return(true);
   }

return false;

}

bool IsMAFilter(){

   if(MAFilterOn==false) return(false);

   double MovAvg[];

   CopyBuffer(handleMovAvg,MAIN_LINE,0,1,MovAvg);
   ArraySetAsSeries(MovAvg,true);

   double MAnow = MovAvg[0];
   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   if( ask > MAnow * (1 + PctPricefromMA/100) ||
       ask < MAnow * (1 - PctPricefromMA/100)
     ){
          if(TradingEnabledComm=="" || TradingEnabledComm!="Printed"){
            TradingEnabledComm = "Trading is disabled due to Mov Avg Filter. Price as % of MA = " + DoubleToString(ask*100/MAnow);
          }
          return true;
      }

return false;
}

bool IsTradingAllowedbyDay(){

      MqlDateTime today;
      TimeCurrent(today);
      string Daytoday = EnumToString((ENUM_DAY_OF_WEEK)today.day_of_week);

      if(AllowedMonday==true && Daytoday=="MONDAY") return true;
      if(AllowedTuesday==true && Daytoday=="TUESDAY") return true;
      if(AllowedWednesday==true && Daytoday=="WEDNESDAY") return true;
      if(AllowedThursday==true && Daytoday=="THURSDAY") return true;
      if(AllowedFriday==true && Daytoday=="FRIDAY") return true;
      if(AllowedSaturday==true && Daytoday=="SATURDAY") return true;
      if(AllowedSunday==true && Daytoday=="SUNDAY") return true;

      if(TradingEnabledComm=="" || TradingEnabledComm!="Printed"){
            TradingEnabledComm = "Trading is not allowed on " + Daytoday;
       }

return false;
}

void UpdateInitialBalances(){

      static   MqlDateTime prevcheck;

      MqlDateTime now;
      TimeCurrent(now);
      if(now.day!=prevcheck.day){
         BegofDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         EqHigh_1D = BegofDayBalance;
         DD_1D_Pct= 0;
         prevcheck = now;
         }
}

void UpdatePropfirmValues(){

      double Equity = AccountInfoDouble(ACCOUNT_EQUITY);

      if(BegofDayBalance!=0){
         Prf_1D_Pct = (Equity - BegofDayBalance) * 100 / BegofDayBalance;
         if(Equity>EqHigh_1D) EqHigh_1D = Equity;
         double curr1D_DD = (Equity - EqHigh_1D) * 100 / EqHigh_1D;
         if (curr1D_DD < DD_1D_Pct){
            DD_1D_Pct = curr1D_DD;
         }
       }
}

  bool IsTradingAllowedPropValues(){

         if(DD_1D_Pct < -MaxDDay){
            if(TradingEnabledComm!="Printed") TradingEnabledComm = "Trading Disabled: Max Drawdown for Day Exceeded";
            return false;
          }

 return true;

 }
