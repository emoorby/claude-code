#property copyright "JEMFX12"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

CTrade trade;

enum ENUM_LST
{
   Fixed = 0,
   RiskPct = 1
};

enum ENUM_Hours
{
   H1 = 1, H2 = 2, H3 = 3, H4 = 4, H5 = 5, H6 = 6, H7 = 7, H8 = 8, H9 = 9, H10 = 10,
   H11 = 11, H12 = 12, H13 = 13, H14 = 14, H15 = 15, H16 = 16, H17 = 17, H18 = 18, H19 = 19, H20 = 20,
   H21 = 21, H22 = 22, H23 = 23, H24 = 24
};

enum ENUM_Minutes
{
   M0 = 0, M5 = 5, M10 = 10, M15 = 15, M20 = 20, M25 = 25, M30 = 30, M35 = 35, M40 = 40, M45 = 45, M50 = 50, M55 = 55
};

enum ENUM_TrSides
{
   Onesided = 0,
   Bothside = 1
};

enum ENUM_SLType
{
   Yes = 0,
   No = 1
};

enum ENUM_TrType
{
   RangePct = 0,
   HighLow = 1,
   Fixedpips = 2
};

enum ENUM_TrStyle
{
   With_Break = 0,
   Opposite_to_Break = 1
};

enum ENUM_IcTypes
{
   Price_above_Cloud = 0,
   Price_above_Ten = 1,
   Price_above_Kij = 2,
   Price_above_SenA = 3,
   Price_above_SenB = 4,
   Ten_above_Kij = 5,
   Ten_above_Kij_above_Cloud = 6,
   Ten_above_Cloud = 7,
   Kij_above_Cloud = 8
};

enum ENUM_sep_dropdown
{
   comma = 0,
   semicolon = 1
};

// Input parameters
input int InpMagic = 1212;
input string TradeComment = "Breakout JT";
input ENUM_TrStyle TradingStyle = 1;
input ENUM_TrSides TradingSides = 0;

input ENUM_Hours RangeStartHour = 8;
input ENUM_Minutes RangeStartMin = 0;
input ENUM_Hours RangeEndHour = 12;
input ENUM_Minutes RangeEndMin = 0;
input color rangecolor = clrBeige;
input int MinRangeSize = 15;
input int MaxRangeSize = 30;
input color rangecolordisabled = clrRed;

input ENUM_LST LotSizeType = 1;
input double FixedLotSize = 0.01;
input double RiskPercent = 2;
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5;
input int OrdDistpct = 10;
input int SLPercent = 100;
input int TPPercent = 180;

input double BreakevenTriggerPct = 50.0;
input double NextMoveTriggerPct = 25.0;

datetime timestart, timeend;
int BarsRangeStart, BarstoCount, BuyTotal, SellTotal;
double RangeHigh, RangeLow, RangeSize;
int lastRangeDay = 0; // Track the day when range was last set

// Simplified Position Data Management using arrays
ulong positionTickets[100]; // Store up to 100 position tickets (MQL5 uses ulong for tickets)
bool positionBreakevenReached[100];
bool positionNextMoveReached[100];
int positionTimeframeLevel[100];
double positionBreakevenPrice[100];
double positionInitialSL[100];
int positionType[100]; // 1 = BUY, 2 = SELL
int positionCount = 0;

input bool NewsFilterOn = true;
input ENUM_sep_dropdown separator = 0;
input string KeyNews = "NFP,JOLTS,Nonfarm,PMI,Retail,GDP,Confidence,Interest Rate";
input string NewsCurrencies = "USD";
input int DaysNewsLookup = 100;
input color InpDisabledColor = clrRed;

string Newstoavoid[];
bool newsprinted = false;

input bool MAFilterOn = true;
input ENUM_TIMEFRAMES MATimeframe = PERIOD_D1;
input int Slow_MA_Period = 200;
input int Fast_MA_Period = 50;
input ENUM_MA_METHOD MA_Mode = MODE_EMA;
input ENUM_APPLIED_PRICE MA_AppPrice = PRICE_MEDIAN;

bool MA_BuyOn = true;
bool MA_SellOn = true;

input bool IchimokuFilter = true;
input ENUM_IcTypes IchiFilterType = 0;
input ENUM_TIMEFRAMES IchiTimeframe = PERIOD_D1;
input int tenkan = 9;
input int kijun = 26;
input int senkou_b = 52;

bool Ichi_BuyOn = true;
bool Ichi_SellOn = true;

double iIchimokuTenkanSen, iIchimokuKijunSen, iIchimokuSenkouSpanA, iIchimokuSenkouSpanB;
double iMAFast, iMASlow;

// Indicator handles
int ichiHandle;
int maFastHandle;
int maSlowHandle;

//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize position arrays
   positionCount = 0;
   ArrayInitialize(positionTickets, 0);
   ArrayInitialize(positionBreakevenReached, false);
   ArrayInitialize(positionNextMoveReached, false);
   ArrayInitialize(positionTimeframeLevel, 0);
   ArrayInitialize(positionBreakevenPrice, 0);
   ArrayInitialize(positionInitialSL, 0);
   ArrayInitialize(positionType, 0);

   // Initialize range tracking
   lastRangeDay = 0;
   BarsRangeStart = 0;

   // Create indicator handles
   if(IchimokuFilter)
   {
      ichiHandle = iIchimoku(_Symbol, IchiTimeframe, tenkan, kijun, senkou_b);
      if(ichiHandle == INVALID_HANDLE)
      {
         Print("Error creating Ichimoku indicator");
         return(INIT_FAILED);
      }
   }

   if(MAFilterOn)
   {
      maFastHandle = iMA(_Symbol, MATimeframe, Fast_MA_Period, 0, MA_Mode, MA_AppPrice);
      maSlowHandle = iMA(_Symbol, MATimeframe, Slow_MA_Period, 0, MA_Mode, MA_AppPrice);
      if(maFastHandle == INVALID_HANDLE || maSlowHandle == INVALID_HANDLE)
      {
         Print("Error creating MA indicators");
         return(INIT_FAILED);
      }
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(3);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectDelete(0, "range");
   ObjectDelete(0, "tradingtime");

   if(ichiHandle != INVALID_HANDLE) IndicatorRelease(ichiHandle);
   if(maFastHandle != INVALID_HANDLE) IndicatorRelease(maFastHandle);
   if(maSlowHandle != INVALID_HANDLE) IndicatorRelease(maSlowHandle);
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;

   if(IchimokuFilter)
   {
      double tenkanBuffer[], kijunBuffer[], senkouABuffer[], senkouBBuffer[];
      ArraySetAsSeries(tenkanBuffer, true);
      ArraySetAsSeries(kijunBuffer, true);
      ArraySetAsSeries(senkouABuffer, true);
      ArraySetAsSeries(senkouBBuffer, true);

      if(CopyBuffer(ichiHandle, 0, 0, 2, tenkanBuffer) > 0 &&
         CopyBuffer(ichiHandle, 1, 0, 2, kijunBuffer) > 0 &&
         CopyBuffer(ichiHandle, 2, 0, 2, senkouABuffer) > 0 &&
         CopyBuffer(ichiHandle, 3, 0, 2, senkouBBuffer) > 0)
      {
         iIchimokuTenkanSen = tenkanBuffer[0];
         iIchimokuKijunSen = kijunBuffer[0];
         iIchimokuSenkouSpanA = senkouABuffer[0];
         iIchimokuSenkouSpanB = senkouBBuffer[0];
      }
   }

   if(MAFilterOn)
   {
      double maFastBuffer[], maSlowBuffer[];
      ArraySetAsSeries(maFastBuffer, true);
      ArraySetAsSeries(maSlowBuffer, true);

      if(CopyBuffer(maFastHandle, 0, 0, 1, maFastBuffer) > 0 &&
         CopyBuffer(maSlowHandle, 0, 0, 1, maSlowBuffer) > 0)
      {
         iMAFast = maFastBuffer[0];
         iMASlow = maSlowBuffer[0];
      }
   }

   if(IsUpcomingNews()) return;

   CheckforTradeSides();
   CheckforOpenOrdersandPositions();
   UpdatePositionDataArrays();

   if((BuyTotal > 0 || SellTotal > 0))
   {
      NewStopLossManagement();
   }

   ConvertTimes();

   if(IsInsideTime())
   {
      RangeHigh = GetHigh();
      RangeLow = GetLow();
      RangeSize = RangeHigh - RangeLow;

      ShowRange(RangeHigh, RangeLow);
   }

   PrepareOrder();
}

//+------------------------------------------------------------------+
// Helper function to normalize price to correct digits
//+------------------------------------------------------------------+
double NormalizePrice(double price)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}

//+------------------------------------------------------------------+
// Helper function to check if SL modification is valid
//+------------------------------------------------------------------+
bool IsValidSLModification(ENUM_ORDER_TYPE orderType, double newSL, double currentSL, double currentPrice)
{
   // Normalize values
   newSL = NormalizePrice(newSL);
   currentSL = NormalizePrice(currentSL);
   currentPrice = NormalizePrice(currentPrice);

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minDiff = NormalizeDouble(2 * point, digits); // Minimum meaningful difference

   // Check if new SL is different from current SL
   if(MathAbs(newSL - currentSL) < minDiff)
   {
      // SL is unchanged, no need to modify
      return false;
   }

   // Get minimum stop level (broker requirement)
   double minStopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;

   // Add tolerance for validation (10 points or minStopLevel, whichever is smaller)
   double tolerance = MathMin(10 * point, minStopLevel * 0.5);
   if(tolerance == 0) tolerance = 10 * point; // Fallback if minStopLevel is 0

   // For BUY orders, SL must be below current price
   if(orderType == ORDER_TYPE_BUY)
   {
      // Allow tolerance for price fluctuations
      if(newSL > currentPrice + tolerance)
      {
         Print("Invalid BUY SL: SL=", newSL, " must be below price=", currentPrice, " (tolerance=", tolerance, ")");
         return false;
      }

      // Check minimum distance with tolerance
      double distance = currentPrice - newSL;
      if(distance < 0) distance = 0; // Handle case where price pulled back

      if(minStopLevel > 0 && distance < (minStopLevel - tolerance))
      {
         Print("BUY SL too close to price: Distance=", distance/point, " points, Required=", minStopLevel/point, " points");
         return false;
      }
   }
   // For SELL orders, SL must be above current price
   else if(orderType == ORDER_TYPE_SELL)
   {
      // Allow tolerance for price fluctuations
      if(newSL < currentPrice - tolerance)
      {
         Print("Invalid SELL SL: SL=", newSL, " must be above price=", currentPrice, " (tolerance=", tolerance, ")");
         return false;
      }

      // Check minimum distance with tolerance
      double distance = newSL - currentPrice;
      if(distance < 0) distance = 0; // Handle case where price pulled back

      if(minStopLevel > 0 && distance < (minStopLevel - tolerance))
      {
         Print("SELL SL too close to price: Distance=", distance/point, " points, Required=", minStopLevel/point, " points");
         return false;
      }
   }

   return true;
}

//+------------------------------------------------------------------+
// Safe PositionModify wrapper with validation
//+------------------------------------------------------------------+
bool SafePositionModify(ulong ticket, double sl, double tp)
{
   if(!PositionSelectByTicket(ticket))
   {
      Print("Error selecting position #", ticket);
      return false;
   }

   ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentPrice = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Normalize all prices
   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);

   // Validate the modification
   if(!IsValidSLModification(orderType, sl, currentSL, currentPrice))
   {
      return false;
   }

   // Attempt the modification
   bool result = trade.PositionModify(ticket, sl, tp);

   if(!result)
   {
      Print("PositionModify failed for #", ticket, ": Error ", GetLastError());
      Print("  Type=", orderType, " NewSL=", sl, " OldSL=", currentSL, " TP=", tp);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
double GetATRTrendIndValue(ENUM_TIMEFRAMES timeframe, int buffer = 1)
{
   static bool fallbackLogged[6] = {false, false, false, false, false, false}; // Track logging per timeframe

   // Try to get custom indicator
   int customHandle = iCustom(_Symbol, timeframe, "ATR_Trend_Ind");
   if(customHandle != INVALID_HANDLE)
   {
      double values[];
      ArraySetAsSeries(values, true);
      if(CopyBuffer(customHandle, 0, 0, buffer + 3, values) > 0)
      {
         for(int i = 0; i < 3; i++)
         {
            if(values[buffer + i] != 0 && values[buffer + i] != EMPTY_VALUE)
            {
               IndicatorRelease(customHandle);
               return values[buffer + i];
            }
         }
      }
      IndicatorRelease(customHandle);
   }

   // If indicator not found, try alternative approach
   int atrHandle = iATR(_Symbol, timeframe, 14);
   if(atrHandle != INVALID_HANDLE)
   {
      double atrValues[];
      ArraySetAsSeries(atrValues, true);
      if(CopyBuffer(atrHandle, 0, 0, 1, atrValues) > 0 && atrValues[0] > 0)
      {
         int tfLevel = GetTimeframeLevel(timeframe);
         if(!fallbackLogged[tfLevel])
         {
            Print("ATR_Trend_Ind not found. Using standard ATR for ", GetTimeframeName(tfLevel), " timeframe.");
            fallbackLogged[tfLevel] = true;
         }
         IndicatorRelease(atrHandle);
         return atrValues[0];
      }
      IndicatorRelease(atrHandle);
   }

   Print("Warning: Could not get ATR value for timeframe ", GetTimeframeName(GetTimeframeLevel(timeframe)));
   return 0;
}

//+------------------------------------------------------------------+
void UpdatePositionDataArrays()
{
   // Build temporary arrays to preserve existing position data
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
   ArrayInitialize(tempBreakevenPrice, 0);
   ArrayInitialize(tempInitialSL, 0);
   ArrayInitialize(tempType, 0);

   // Loop through all open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

            // Check if this position already exists in our array
            int existingIndex = -1;
            for(int j = 0; j < positionCount; j++)
            {
               if(positionTickets[j] == ticket)
               {
                  existingIndex = j;
                  break;
               }
            }

            // Add to temp array
            if(tempCount < ArraySize(tempTickets))
            {
               tempTickets[tempCount] = ticket;

               // If position already existed, preserve its state
               if(existingIndex >= 0)
               {
                  tempBreakevenReached[tempCount] = positionBreakevenReached[existingIndex];
                  tempNextMoveReached[tempCount] = positionNextMoveReached[existingIndex];
                  tempTimeframeLevel[tempCount] = positionTimeframeLevel[existingIndex];
                  tempBreakevenPrice[tempCount] = positionBreakevenPrice[existingIndex];
                  tempInitialSL[tempCount] = positionInitialSL[existingIndex];
                  tempType[tempCount] = positionType[existingIndex];
               }
               else
               {
                  // New position - initialize with default values
                  tempBreakevenReached[tempCount] = false;
                  tempNextMoveReached[tempCount] = false;
                  tempTimeframeLevel[tempCount] = 0;
                  tempBreakevenPrice[tempCount] = 0;
                  tempInitialSL[tempCount] = PositionGetDouble(POSITION_SL);
                  tempType[tempCount] = (posType == POSITION_TYPE_BUY) ? 1 : 2;
               }

               tempCount++;
            }
         }
      }
   }

   // Copy temp arrays back to main arrays
   positionCount = tempCount;
   for(int k = 0; k < positionCount; k++)
   {
      positionTickets[k] = tempTickets[k];
      positionBreakevenReached[k] = tempBreakevenReached[k];
      positionNextMoveReached[k] = tempNextMoveReached[k];
      positionTimeframeLevel[k] = tempTimeframeLevel[k];
      positionBreakevenPrice[k] = tempBreakevenPrice[k];
      positionInitialSL[k] = tempInitialSL[k];
      positionType[k] = tempType[k];
   }
}

//+------------------------------------------------------------------+
int FindPositionIndex(ulong ticket)
{
   for(int i = 0; i < positionCount; i++)
   {
      if(positionTickets[i] == ticket)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
void NewStopLossManagement()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double currentPrice = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double newSL = currentSL;

            double requiredMoveForBreakeven = (RangeSize > 0) ? RangeSize * BreakevenTriggerPct / 100 : 0;

            if(posType == POSITION_TYPE_BUY)
            {
               ManageBuyStopLoss(currentPrice, openPrice, currentSL, newSL, ticket, requiredMoveForBreakeven);
            }
            else if(posType == POSITION_TYPE_SELL)
            {
               ManageSellStopLoss(currentPrice, openPrice, currentSL, newSL, ticket, requiredMoveForBreakeven);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
void ManageBuyStopLoss(double currentPrice, double openPrice, double currentSL, double &newSL, ulong ticket, double requiredMoveForBreakeven)
{
   int posIndex = FindPositionIndex(ticket);
   if(posIndex == -1) return;

   if(!PositionSelectByTicket(ticket)) return;

   double tp = PositionGetDouble(POSITION_TP);
   double priceMove = currentPrice - openPrice;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Convert required moves to points
   double requiredMovePoints = requiredMoveForBreakeven;
   double requiredAdditionalMove = (RangeSize > 0) ? RangeSize * NextMoveTriggerPct / 100 : 0;

   Print("Buy #", ticket, " - PriceMove: ", NormalizeDouble(priceMove/point, 0), " points, Required: ", NormalizeDouble(requiredMovePoints/point, 0), " points, Breakeven: ", positionBreakevenReached[posIndex], ", NextMove: ", positionNextMoveReached[posIndex]);

   if(!positionBreakevenReached[posIndex] && priceMove >= requiredMovePoints)
   {
      newSL = NormalizePrice(openPrice);

      // Use safe position modify
      bool result = SafePositionModify(ticket, newSL, tp);
      if(result)
      {
         positionBreakevenReached[posIndex] = true;
         positionBreakevenPrice[posIndex] = newSL;
         positionInitialSL[posIndex] = currentSL;
         Print("SUCCESS: Buy position #", ticket, " moved to breakeven at ", newSL);
      }
      return;
   }

   if(positionBreakevenReached[posIndex] && !positionNextMoveReached[posIndex])
   {
      double additionalMove = priceMove - requiredMovePoints;

      if(additionalMove >= requiredAdditionalMove)
      {
         positionNextMoveReached[posIndex] = true;
         positionTimeframeLevel[posIndex] = 0;
         Print("Buy position #", ticket, " ready for ATR trailing. Starting at M5 timeframe");
      }
   }

   if(positionBreakevenReached[posIndex] && positionNextMoveReached[posIndex])
   {
      ENUM_TIMEFRAMES currentTF = GetCurrentTimeframe(positionTimeframeLevel[posIndex]);
      double atrTrendValue = GetATRTrendIndValue(currentTF, 1);

      Print("Buy #", ticket, " - ATR Value: ", atrTrendValue, ", Current SL: ", currentSL, ", Timeframe: ", GetTimeframeName(positionTimeframeLevel[posIndex]));

      // Simplified condition for BUY positions: ATR should be above current SL
      if(atrTrendValue > 0 && atrTrendValue > currentSL && atrTrendValue > positionBreakevenPrice[posIndex])
      {
         newSL = NormalizePrice(atrTrendValue);

         // Use safe position modify
         bool result = SafePositionModify(ticket, newSL, tp);
         if(result)
         {
            Print("SUCCESS: Buy #", ticket, " SL updated to ", newSL, " (", GetTimeframeName(positionTimeframeLevel[posIndex]), " ATR)");

            // Progress to next timeframe only if not at Daily yet
            // Once at Daily (level 5), stay there and keep checking
            if(positionTimeframeLevel[posIndex] < 5)
            {
               positionTimeframeLevel[posIndex]++;
               Print("Buy #", ticket, " progressing to ", GetTimeframeName(positionTimeframeLevel[posIndex]), " timeframe");
            }
            else
            {
               Print("Buy #", ticket, " staying at Daily timeframe, will continue monitoring");
            }
         }
      }
      else if(atrTrendValue > 0)
      {
         // Don't spam logs - only print when at lower timeframes or occasionally at D1
         if(positionTimeframeLevel[posIndex] < 5)
         {
            Print("Buy #", ticket, " - ATR condition not met: ATR=", atrTrendValue, ", CurrentSL=", currentSL, ", Breakeven=", positionBreakevenPrice[posIndex]);
         }
      }
   }
}

//+------------------------------------------------------------------+
void ManageSellStopLoss(double currentPrice, double openPrice, double currentSL, double &newSL, ulong ticket, double requiredMoveForBreakeven)
{
   int posIndex = FindPositionIndex(ticket);
   if(posIndex == -1) return;

   if(!PositionSelectByTicket(ticket)) return;

   double tp = PositionGetDouble(POSITION_TP);
   double priceMove = openPrice - currentPrice;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Convert required moves to points
   double requiredMovePoints = requiredMoveForBreakeven;
   double requiredAdditionalMove = (RangeSize > 0) ? RangeSize * NextMoveTriggerPct / 100 : 0;

   Print("Sell #", ticket, " - PriceMove: ", NormalizeDouble(priceMove/point, 0), " points, Required: ", NormalizeDouble(requiredMovePoints/point, 0), " points, Breakeven: ", positionBreakevenReached[posIndex], ", NextMove: ", positionNextMoveReached[posIndex]);

   if(!positionBreakevenReached[posIndex] && priceMove >= requiredMovePoints)
   {
      newSL = NormalizePrice(openPrice);

      // Use safe position modify
      bool result = SafePositionModify(ticket, newSL, tp);
      if(result)
      {
         positionBreakevenReached[posIndex] = true;
         positionBreakevenPrice[posIndex] = newSL;
         positionInitialSL[posIndex] = currentSL;
         Print("SUCCESS: Sell position #", ticket, " moved to breakeven at ", newSL);
      }
      return;
   }

   if(positionBreakevenReached[posIndex] && !positionNextMoveReached[posIndex])
   {
      double additionalMove = priceMove - requiredMovePoints;

      if(additionalMove >= requiredAdditionalMove)
      {
         positionNextMoveReached[posIndex] = true;
         positionTimeframeLevel[posIndex] = 0;
         Print("Sell position #", ticket, " ready for ATR trailing. Starting at M5 timeframe");
      }
   }

   if(positionBreakevenReached[posIndex] && positionNextMoveReached[posIndex])
   {
      ENUM_TIMEFRAMES currentTF = GetCurrentTimeframe(positionTimeframeLevel[posIndex]);
      double atrTrendValue = GetATRTrendIndValue(currentTF, 1);

      Print("Sell #", ticket, " - ATR Value: ", atrTrendValue, ", Current SL: ", currentSL, ", Timeframe: ", GetTimeframeName(positionTimeframeLevel[posIndex]));

      // Simplified condition for SELL positions: ATR should be below current SL
      if(atrTrendValue > 0 && atrTrendValue < currentSL && atrTrendValue < positionBreakevenPrice[posIndex])
      {
         newSL = NormalizePrice(atrTrendValue);

         // Use safe position modify
         bool result = SafePositionModify(ticket, newSL, tp);
         if(result)
         {
            Print("SUCCESS: Sell #", ticket, " SL updated to ", newSL, " (", GetTimeframeName(positionTimeframeLevel[posIndex]), " ATR)");

            // Progress to next timeframe only if not at Daily yet
            // Once at Daily (level 5), stay there and keep checking
            if(positionTimeframeLevel[posIndex] < 5)
            {
               positionTimeframeLevel[posIndex]++;
               Print("Sell #", ticket, " progressing to ", GetTimeframeName(positionTimeframeLevel[posIndex]), " timeframe");
            }
            else
            {
               Print("Sell #", ticket, " staying at Daily timeframe, will continue monitoring");
            }
         }
      }
      else if(atrTrendValue > 0)
      {
         // Don't spam logs - only print when at lower timeframes or occasionally at D1
         if(positionTimeframeLevel[posIndex] < 5)
         {
            Print("Sell #", ticket, " - ATR condition not met: ATR=", atrTrendValue, ", CurrentSL=", currentSL, ", Breakeven=", positionBreakevenPrice[posIndex]);
         }
      }
   }
}

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
void ConvertTimes()
{
   MqlDateTime tm;
   TimeCurrent(tm);
   int currentDay = tm.day;

   // Reset range tracking when a new day begins
   if(lastRangeDay != 0 && lastRangeDay != currentDay)
   {
      BarsRangeStart = 0;
      RangeHigh = 0;
      RangeLow = 0;
      RangeSize = 0;
      lastRangeDay = currentDay; // Update immediately to prevent repeated detection
      Print("New trading day detected (", currentDay, "). Range tracking reset.");
   }

   string currentDate = StringFormat("%d.%02d.%02d", tm.year, tm.mon, tm.day);
   string startTimeStr = StringFormat("%s %02d:%02d", currentDate, RangeStartHour, RangeStartMin);
   string endTimeStr = StringFormat("%s %02d:%02d", currentDate, RangeEndHour, RangeEndMin);

   timestart = StringToTime(startTimeStr);
   timeend = StringToTime(endTimeStr);

   if(BarsRangeStart == 0 && TimeCurrent() >= timestart)
   {
      BarsRangeStart = Bars(_Symbol, InpTimeframe);
      lastRangeDay = currentDay; // Also set here in case we start mid-day
      Print("Range tracking started for day ", currentDay, " at ", TimeToString(TimeCurrent()), ", BarsRangeStart = ", BarsRangeStart);
   }
}

//+------------------------------------------------------------------+
double GetHigh()
{
   double high = 0;
   int highestbar = 0;
   if(TimeCurrent() > timestart && TimeCurrent() < timeend)
   {
      BarstoCount = Bars(_Symbol, InpTimeframe) - BarsRangeStart + 1;
      highestbar = iHighest(_Symbol, InpTimeframe, MODE_HIGH, BarstoCount, 0);
      if(highestbar >= 0)
      {
         high = iHigh(_Symbol, InpTimeframe, highestbar);
         if(high != RangeHigh) return high;
      }
   }
   return RangeHigh;
}

//+------------------------------------------------------------------+
double GetLow()
{
   double low = 0;
   int lowestbar = 0;
   if(TimeCurrent() > timestart && TimeCurrent() < timeend)
   {
      BarstoCount = Bars(_Symbol, InpTimeframe) - BarsRangeStart + 1;
      lowestbar = iLowest(_Symbol, InpTimeframe, MODE_LOW, BarstoCount, 0);
      if(lowestbar >= 0)
      {
         low = iLow(_Symbol, InpTimeframe, lowestbar);
         if(low != RangeLow) return low;
      }
   }
   return RangeLow;
}

//+------------------------------------------------------------------+
void ShowRange(double high, double low)
{
   if(ObjectFind(0, "range") < 0)
   {
      ObjectCreate(0, "range", OBJ_RECTANGLE, 0, timestart, high, timeend, low);
   }
   else
   {
      ObjectMove(0, "range", 0, timestart, high);
      ObjectMove(0, "range", 1, timeend, low);
   }

   ObjectSetInteger(0, "range", OBJPROP_BACK, true);

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double pipSize = point * 10;

   if(RangeSize < MaxRangeSize * pipSize && RangeSize > MinRangeSize * pipSize)
   {
      ObjectSetInteger(0, "range", OBJPROP_COLOR, rangecolor);
   }
   else
   {
      ObjectSetInteger(0, "range", OBJPROP_COLOR, rangecolordisabled);
   }

   if(ObjectFind(0, "tradingtime") < 0)
   {
      ObjectCreate(0, "tradingtime", OBJ_RECTANGLE, 0, timeend, high, TimeCurrent() + 86400, low);
   }
   else
   {
      ObjectMove(0, "tradingtime", 0, timeend, high);
      ObjectMove(0, "tradingtime", 1, TimeCurrent() + 86400, low);
   }
   ObjectSetInteger(0, "tradingtime", OBJPROP_COLOR, rangecolor);
   ObjectSetInteger(0, "tradingtime", OBJPROP_BACK, true);
}

//+------------------------------------------------------------------+
bool IsInsideTime()
{
   MqlDateTime tm;
   TimeCurrent(tm);
   int nowmin = tm.hour * 60 + tm.min;

   MqlDateTime tmStart;
   TimeToStruct(timestart, tmStart);
   int startmin = tmStart.hour * 60 + tmStart.min;

   if(nowmin >= startmin) return true;

   return false;
}

//+------------------------------------------------------------------+
void PrepareOrder()
{
   if(TimeCurrent() > timeend)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double pipSize = point * 10;

      // Validate range values
      if(RangeHigh <= 0 || RangeLow <= 0 || RangeSize <= 0)
      {
         Print("WARNING: Invalid range values - High: ", RangeHigh, ", Low: ", RangeLow, ", Size: ", RangeSize);
         return;
      }

      // Check if range size is within valid limits
      if(RangeSize <= MinRangeSize * pipSize || RangeSize >= MaxRangeSize * pipSize)
      {
         Print("Range size outside limits: ", NormalizeDouble(RangeSize/pipSize, 1), " pips (Min: ", MinRangeSize, ", Max: ", MaxRangeSize, ")");
         return;
      }

      double minDistFromHigh = RangeSize * OrdDistpct / 100;
      double minDistFromLow = RangeSize * OrdDistpct / 100;

      // Check if price is in valid zone for order placement
      if(ask >= RangeHigh - minDistFromHigh || ask <= RangeLow + minDistFromLow)
      {
         Print("Price too close to range boundaries. Ask: ", ask, ", High: ", RangeHigh, ", Low: ", RangeLow, ", MinDist: ", minDistFromHigh/point, " points");
         return;
      }

      // Log order preparation attempt
      Print("Preparing orders - Range: ", RangeHigh, " to ", RangeLow, " (", NormalizeDouble(RangeSize/pipSize, 1), " pips), Ask: ", ask);
      Print("Trading filters - MA_BuyOn: ", MA_BuyOn, ", MA_SellOn: ", MA_SellOn, ", Ichi_BuyOn: ", Ichi_BuyOn, ", Ichi_SellOn: ", Ichi_SellOn);

      if(TradingStyle == 0)  // With_Break
      {
         if(BuyTotal <= 0 && MA_BuyOn == true && Ichi_BuyOn == true)
         {
            double buyPrice = NormalizePrice(RangeHigh);
            double buySL = NormalizePrice(RangeHigh - (RangeSize * SLPercent / 100));
            Print("Attempting BuyStop: Price=", buyPrice, ", SL=", buySL, ", Current Ask=", ask);
            OpenTrade(ORDER_TYPE_BUY_STOP, buyPrice, buySL);
         }
         else if(BuyTotal <= 0)
         {
            Print("BuyStop skipped - BuyTotal:", BuyTotal, ", MA_BuyOn:", MA_BuyOn, ", Ichi_BuyOn:", Ichi_BuyOn);
         }

         if(SellTotal <= 0 && MA_SellOn == true && Ichi_SellOn == true)
         {
            double sellPrice = NormalizePrice(RangeLow);
            double sellSL = NormalizePrice(RangeLow + (RangeSize * SLPercent / 100));
            Print("Attempting SellStop: Price=", sellPrice, ", SL=", sellSL, ", Current Bid=", bid);
            OpenTrade(ORDER_TYPE_SELL_STOP, sellPrice, sellSL);
         }
         else if(SellTotal <= 0)
         {
            Print("SellStop skipped - SellTotal:", SellTotal, ", MA_SellOn:", MA_SellOn, ", Ichi_SellOn:", Ichi_SellOn);
         }
      }
      else if(TradingStyle == 1)  // Opposite_to_Break
      {
         if(BuyTotal <= 0 && MA_BuyOn == true && Ichi_BuyOn == true)
         {
            double buyPrice = NormalizePrice(RangeLow);
            double buySL = NormalizePrice(RangeLow - (RangeSize * SLPercent / 100));
            Print("Attempting BuyLimit: Price=", buyPrice, ", SL=", buySL, ", Current Ask=", ask);
            OpenTrade(ORDER_TYPE_BUY_LIMIT, buyPrice, buySL);
         }
         else if(BuyTotal <= 0)
         {
            Print("BuyLimit skipped - BuyTotal:", BuyTotal, ", MA_BuyOn:", MA_BuyOn, ", Ichi_BuyOn:", Ichi_BuyOn);
         }

         if(SellTotal <= 0 && MA_SellOn == true && Ichi_SellOn == true)
         {
            double sellPrice = NormalizePrice(RangeHigh);
            double sellSL = NormalizePrice(RangeHigh + (RangeSize * SLPercent / 100));
            Print("Attempting SellLimit: Price=", sellPrice, ", SL=", sellSL, ", Current Bid=", bid);
            OpenTrade(ORDER_TYPE_SELL_LIMIT, sellPrice, sellSL);
         }
         else if(SellTotal <= 0)
         {
            Print("SellLimit skipped - SellTotal:", SellTotal, ", MA_SellOn:", MA_SellOn, ", Ichi_SellOn:", Ichi_SellOn);
         }
      }
   }
}

//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type, double price, double sl)
{
   // Normalize prices
   price = NormalizePrice(price);
   sl = NormalizePrice(sl);

   // Check MA filter for buy orders
   if((MAFilterOn == true) &&
      (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP) &&
      (PricevsMovAvg() == "below" || PricevsMovAvg() == "error"))
   {
      Print("Buy order rejected by MA filter. Price vs MA: ", PricevsMovAvg());
      MA_BuyOn = false;
      return;
   }

   // Check MA filter for sell orders
   if((MAFilterOn == true) &&
      (type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP) &&
      (PricevsMovAvg() == "above" || PricevsMovAvg() == "error"))
   {
      Print("Sell order rejected by MA filter. Price vs MA: ", PricevsMovAvg());
      MA_SellOn = false;
      return;
   }

   // Check Ichimoku filter for buy orders
   if((IchimokuFilter == true) &&
      (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP) &&
      (PricevsIchiCloud() == "below" || PricevsIchiCloud() == "Incloud"))
   {
      Print("Buy order rejected by Ichimoku filter. Price vs Cloud: ", PricevsIchiCloud());
      Ichi_BuyOn = false;
      return;
   }

   // Check Ichimoku filter for sell orders
   if((IchimokuFilter == true) &&
      (type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP) &&
      (PricevsIchiCloud() == "above" || PricevsIchiCloud() == "Incloud"))
   {
      Print("Sell order rejected by Ichimoku filter. Price vs Cloud: ", PricevsIchiCloud());
      Ichi_SellOn = false;
      return;
   }

   // Calculate TP
   double tp = NormalizePrice(price + (price - sl) * TPPercent / SLPercent);

   // Calculate lot size
   double lots = 0.01;
   if(LotSizeType == 0)
   {
      lots = FixedLotSize;
   }
   else if(LotSizeType == 1)
   {
      lots = calcLots(price - sl);
   }

   // Validate pending order prices
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minStopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;

   if(type == ORDER_TYPE_BUY_STOP && price < ask + minStopLevel)
   {
      Print("ERROR: BuyStop price too close to market. Price: ", price, ", Ask: ", ask, ", MinDist: ", minStopLevel/point, " points");
      return;
   }
   if(type == ORDER_TYPE_SELL_STOP && price > bid - minStopLevel)
   {
      Print("ERROR: SellStop price too close to market. Price: ", price, ", Bid: ", bid, ", MinDist: ", minStopLevel/point, " points");
      return;
   }
   if(type == ORDER_TYPE_BUY_LIMIT && price > ask - minStopLevel)
   {
      Print("ERROR: BuyLimit price too close to market. Price: ", price, ", Ask: ", ask, ", MinDist: ", minStopLevel/point, " points");
      return;
   }
   if(type == ORDER_TYPE_SELL_LIMIT && price < bid + minStopLevel)
   {
      Print("ERROR: SellLimit price too close to market. Price: ", price, ", Bid: ", bid, ", MinDist: ", minStopLevel/point, " points");
      return;
   }

   bool result = trade.OrderOpen(_Symbol, type, lots, 0, price, sl, tp, ORDER_TIME_GTC, 0, TradeComment);
   if(!result)
   {
      Print("OrderOpen FAILED: ", _Symbol, " Type:", type, " Price:", price, " SL:", sl, " TP:", tp, " Lots:", lots, " Error:", GetLastError());
   }
   else
   {
      Print("Order opened successfully: Ticket #", trade.ResultOrder(), ", Type: ", type, ", Price: ", price, ", SL: ", sl, ", TP: ", tp, ", Lots: ", lots);

      // Update position data for the new order
      UpdatePositionDataArrays();
   }
}

//+------------------------------------------------------------------+
void CloseandResetAll()
{
   // Close all positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         {
            if(!trade.PositionClose(ticket))
            {
               Print("Error closing position #", ticket, ": ", GetLastError());
            }
         }
      }
   }

   // Delete all pending orders
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic)
         {
            if(!trade.OrderDelete(ticket))
            {
               Print("Error deleting order #", ticket, ": ", GetLastError());
            }
         }
      }
   }

   BarsRangeStart = 0;
   BuyTotal = 0;
   SellTotal = 0;
   lastRangeDay = 0;

   // Reset position arrays
   positionCount = 0;
   ArrayInitialize(positionTickets, 0);
   ArrayInitialize(positionBreakevenReached, false);
   ArrayInitialize(positionNextMoveReached, false);
   ArrayInitialize(positionTimeframeLevel, 0);
   ArrayInitialize(positionBreakevenPrice, 0);
   ArrayInitialize(positionInitialSL, 0);
   ArrayInitialize(positionType, 0);

   MA_BuyOn = true;
   MA_SellOn = true;
   Ichi_BuyOn = true;
   Ichi_SellOn = true;

   newsprinted = false;
}

//+------------------------------------------------------------------+
void CheckforTradeSides()
{
   if(TradingSides == 1) return;

   int openPos = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         {
            openPos++;
         }
      }
   }

   if(openPos > 0)
   {
      for(int j = OrdersTotal() - 1; j >= 0; j--)
      {
         ulong ticket = OrderGetTicket(j);
         if(ticket > 0)
         {
            if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic)
            {
               if(!trade.OrderDelete(ticket))
               {
                  Print("Error deleting pending order #", ticket, ": ", GetLastError());
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime previousTime = 0;
   datetime timeArray[];
   ArraySetAsSeries(timeArray, true);

   if(CopyTime(_Symbol, PERIOD_CURRENT, 0, 1, timeArray) > 0)
   {
      datetime currentTime = timeArray[0];
      if(previousTime != currentTime)
      {
         previousTime = currentTime;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
double calcLots(double slPoints)
{
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100;

   double ticksize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickvalue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minvolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxvolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(slPoints < 0) slPoints = slPoints * -1;
   double moneyPerLotstep = slPoints / ticksize * tickvalue * lotstep;

   if(moneyPerLotstep == 0) return minvolume;

   double lots = MathFloor(risk / moneyPerLotstep) * lotstep;

   if(maxvolume != 0) lots = MathMin(lots, maxvolume);
   if(minvolume != 0) lots = MathMax(lots, minvolume);
   lots = NormalizeDouble(lots, 2);

   return lots;
}

//+------------------------------------------------------------------+
void CheckforOpenOrdersandPositions()
{
   BuyTotal = 0;
   SellTotal = 0;

   // Count positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            if(posType == POSITION_TYPE_BUY) BuyTotal++;
            if(posType == POSITION_TYPE_SELL) SellTotal++;
         }
      }
   }

   // Count pending orders
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic)
         {
            ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            if(orderType == ORDER_TYPE_BUY_STOP || orderType == ORDER_TYPE_BUY_LIMIT) BuyTotal++;
            if(orderType == ORDER_TYPE_SELL_STOP || orderType == ORDER_TYPE_SELL_LIMIT) SellTotal++;
         }
      }
   }
}

//+------------------------------------------------------------------+
bool IsUpcomingNews()
{
   if(NewsFilterOn == false) return(false);
   return false;
}

//+------------------------------------------------------------------+
string PricevsMovAvg()
{
   if(iMAFast > iMASlow) return "above";
   if(iMAFast < iMASlow) return "below";
   return "error";
}

//+------------------------------------------------------------------+
string PricevsIchiCloud()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(IchiFilterType == 0)
   {
      if(ask > iIchimokuSenkouSpanA && ask > iIchimokuSenkouSpanB) return "above";
      if(ask < iIchimokuSenkouSpanA && ask < iIchimokuSenkouSpanB) return "below";
   }
   if(IchiFilterType == 1)
   {
      if(ask > iIchimokuTenkanSen) return "above";
      if(ask < iIchimokuTenkanSen) return "below";
   }
   if(IchiFilterType == 2)
   {
      if(ask > iIchimokuKijunSen) return "above";
      if(ask < iIchimokuKijunSen) return "below";
   }
   if(IchiFilterType == 3)
   {
      if(ask > iIchimokuSenkouSpanA) return "above";
      if(ask < iIchimokuSenkouSpanA) return "below";
   }
   if(IchiFilterType == 4)
   {
      if(ask > iIchimokuSenkouSpanB) return "above";
      if(ask < iIchimokuSenkouSpanB) return "below";
   }
   if(IchiFilterType == 5)
   {
      if(iIchimokuTenkanSen > iIchimokuKijunSen) return "above";
      if(iIchimokuTenkanSen < iIchimokuKijunSen) return "below";
   }
   if(IchiFilterType == 6)
   {
      if(iIchimokuTenkanSen > iIchimokuKijunSen && iIchimokuKijunSen > iIchimokuSenkouSpanA && iIchimokuKijunSen > iIchimokuSenkouSpanB) return "above";
      if(iIchimokuTenkanSen < iIchimokuKijunSen && iIchimokuKijunSen < iIchimokuSenkouSpanA && iIchimokuKijunSen < iIchimokuSenkouSpanB) return "below";
   }
   if(IchiFilterType == 7)
   {
      if(iIchimokuTenkanSen > iIchimokuSenkouSpanA && iIchimokuTenkanSen > iIchimokuSenkouSpanB) return "above";
      if(iIchimokuTenkanSen < iIchimokuSenkouSpanA && iIchimokuTenkanSen < iIchimokuSenkouSpanB) return "below";
   }
   if(IchiFilterType == 8)
   {
      if(iIchimokuKijunSen > iIchimokuSenkouSpanA && iIchimokuKijunSen > iIchimokuSenkouSpanB) return "above";
      if(iIchimokuKijunSen < iIchimokuSenkouSpanA && iIchimokuKijunSen < iIchimokuSenkouSpanB) return "below";
   }

   return "Incloud";
}
//+------------------------------------------------------------------+
