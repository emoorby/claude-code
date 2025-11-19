#property copyright "JEMFX12"
#property version   "1.00"
#property strict

// MQL4 compatibility defines
#define PERIOD_CURRENT 0

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
extern int InpMagic = 1212;
extern string TradeComment = "Breakout JT";
extern ENUM_TrStyle TradingStyle = 1;
extern ENUM_TrSides TradingSides = 0;

extern ENUM_Hours RangeStartHour = 8;
extern ENUM_Minutes RangeStartMin = 0;
extern ENUM_Hours RangeEndHour = 12;
extern ENUM_Minutes RangeEndMin = 0;
extern color rangecolor = clrBeige;
extern int MinRangeSize = 15;
extern int MaxRangeSize = 30;
extern color rangecolordisabled = clrRed;

extern ENUM_LST LotSizeType = 1;
extern double FixedLotSize = 0.01;
extern double RiskPercent = 2;
extern int InpTimeframe = PERIOD_M5;
extern int OrdDistpct = 10;
extern int SLPercent = 100;
extern int TPPercent = 180;

extern double BreakevenTriggerPct = 50.0;
extern double NextMoveTriggerPct = 25.0;

datetime timestart, timeend;
int BarsRangeStart, BarstoCount, BuyTotal, SellTotal;
double RangeHigh, RangeLow, RangeSize;

// Simplified Position Data Management using arrays
int positionTickets[100]; // Store up to 100 position tickets
bool positionBreakevenReached[100];
bool positionNextMoveReached[100];
int positionTimeframeLevel[100];
double positionBreakevenPrice[100];
double positionInitialSL[100];
int positionType[100]; // 1 = BUY, 2 = SELL
int positionCount = 0;

extern bool NewsFilterOn = true;
extern ENUM_sep_dropdown separator = 0;
extern string KeyNews = "NFP,JOLTS,Nonfarm,PMI,Retail,GDP,Confidence,Interest Rate";
extern string NewsCurrencies = "USD";
extern int DaysNewsLookup = 100;
extern color InpDisabledColor = clrRed;

string Newstoavoid[];
bool newsprinted = false;

extern bool MAFilterOn = true;
extern int MATimeframe = PERIOD_D1;
extern int Slow_MA_Period = 200;
extern int Fast_MA_Period = 50;
extern int MA_Mode = MODE_EMA;
extern int MA_AppPrice = PRICE_MEDIAN;

bool MA_BuyOn = true;
bool MA_SellOn = true;

extern bool IchimokuFilter = true;
extern ENUM_IcTypes IchiFilterType = 0;
extern int IchiTimeframe = PERIOD_D1;
extern int tenkan = 9;
extern int kijun = 26;
extern int senkou_b = 52;

bool Ichi_BuyOn = true;
bool Ichi_SellOn = true;

double iIchimokuTenkanSen, iIchimokuKijunSen, iIchimokuSenkouSpanA, iIchimokuSenkouSpanB;
double iMAFast, iMASlow;

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

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectDelete("range");
   ObjectDelete("tradingtime");
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;

   if(IchimokuFilter)
   {
      iIchimokuTenkanSen = iIchimoku(NULL, IchiTimeframe, tenkan, kijun, senkou_b, 1, 0);
      iIchimokuKijunSen = iIchimoku(NULL, IchiTimeframe, tenkan, kijun, senkou_b, 2, 0);
      iIchimokuSenkouSpanA = iIchimoku(NULL, IchiTimeframe, tenkan, kijun, senkou_b, 3, 0);
      iIchimokuSenkouSpanB = iIchimoku(NULL, IchiTimeframe, tenkan, kijun, senkou_b, 4, 0);
   }

   if(MAFilterOn)
   {
      iMAFast = iMA(NULL, MATimeframe, Fast_MA_Period, 0, MA_Mode, MA_AppPrice, 0);
      iMASlow = iMA(NULL, MATimeframe, Slow_MA_Period, 0, MA_Mode, MA_AppPrice, 0);
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
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   return NormalizeDouble(price, digits);
}

//+------------------------------------------------------------------+
// Helper function to check if SL modification is valid
//+------------------------------------------------------------------+
bool IsValidSLModification(int orderType, double newSL, double currentSL, double currentPrice)
{
   // Normalize values
   newSL = NormalizePrice(newSL);
   currentSL = NormalizePrice(currentSL);
   currentPrice = NormalizePrice(currentPrice);

   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   double minDiff = NormalizeDouble(2 * Point, digits); // Minimum meaningful difference

   // Check if new SL is different from current SL
   if(MathAbs(newSL - currentSL) < minDiff)
   {
      // SL is unchanged, no need to modify
      return false;
   }

   // Get minimum stop level (broker requirement)
   double minStopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   // Add tolerance for validation (10 points or minStopLevel, whichever is smaller)
   double tolerance = MathMin(10 * Point, minStopLevel * 0.5);
   if(tolerance == 0) tolerance = 10 * Point; // Fallback if minStopLevel is 0

   // For BUY orders, SL must be below current price
   if(orderType == OP_BUY)
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
         Print("BUY SL too close to price: Distance=", distance/Point, " points, Required=", minStopLevel/Point, " points");
         return false;
      }
   }
   // For SELL orders, SL must be above current price
   else if(orderType == OP_SELL)
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
         Print("SELL SL too close to price: Distance=", distance/Point, " points, Required=", minStopLevel/Point, " points");
         return false;
      }
   }

   return true;
}

//+------------------------------------------------------------------+
// Safe OrderModify wrapper with validation
//+------------------------------------------------------------------+
bool SafeOrderModify(int ticket, double price, double sl, double tp, color clr)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
   {
      Print("Error selecting order #", ticket);
      return false;
   }

   int orderType = OrderType();
   double currentSL = OrderStopLoss();
   double currentPrice = (orderType == OP_BUY) ? Bid : Ask;

   // Normalize all prices
   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);
   price = NormalizePrice(price);

   // Validate the modification
   if(!IsValidSLModification(orderType, sl, currentSL, currentPrice))
   {
      return false;
   }

   // Attempt the modification
   bool result = OrderModify(ticket, price, sl, tp, 0, clr);

   if(!result)
   {
      int error = GetLastError();
      Print("OrderModify failed for #", ticket, ": Error ", error, " (", ErrorDescription(error), ")");
      Print("  Type=", orderType, " Price=", price, " NewSL=", sl, " OldSL=", currentSL, " TP=", tp);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
// Get error description
//+------------------------------------------------------------------+
string ErrorDescription(int errorCode)
{
   switch(errorCode)
   {
      case 0:   return "No error";
      case 1:   return "No error but result unknown";
      case 2:   return "Common error";
      case 3:   return "Invalid trade parameters";
      case 4:   return "Trade server is busy";
      case 5:   return "Old version of the client terminal";
      case 6:   return "No connection with trade server";
      case 7:   return "Not enough rights";
      case 8:   return "Too frequent requests";
      case 9:   return "Malfunctional trade operation";
      case 64:  return "Account disabled";
      case 65:  return "Invalid account";
      case 128: return "Trade timeout";
      case 129: return "Invalid price";
      case 130: return "Invalid stops";
      case 131: return "Invalid trade volume";
      case 132: return "Market is closed";
      case 133: return "Trade is disabled";
      case 134: return "Not enough money";
      case 135: return "Price changed";
      case 136: return "Off quotes";
      case 137: return "Broker is busy";
      case 138: return "Requote";
      case 139: return "Order is locked";
      case 140: return "Long positions only allowed";
      case 141: return "Too many requests";
      case 145: return "Modification denied because order too close to market";
      case 146: return "Trade context is busy";
      case 147: return "Expirations are denied by broker";
      case 148: return "Amount of open and pending orders has reached the limit";
      default:  return "Unknown error";
   }
}

//+------------------------------------------------------------------+
double GetATRTrendIndValue(int timeframe, int buffer = 1)
{
   // Try multiple buffer indices to find the correct ATR value
   for(int i = 0; i < 3; i++)
   {
      double value = iCustom(NULL, timeframe, "ATR_Trend_Ind", 0, buffer + i);
      if(value != 0 && value != EMPTY_VALUE)
      {
         return value;
      }
   }

   // If indicator not found, try alternative approach
   double atrValue = iATR(NULL, timeframe, 14, 0);
   if(atrValue > 0)
   {
      Print("Using fallback ATR value: ", atrValue, " for timeframe ", GetTimeframeName(GetTimeframeLevel(timeframe)));
      return atrValue;
   }

   Print("Warning: Could not get ATR value for timeframe ", GetTimeframeName(GetTimeframeLevel(timeframe)));
   return 0;
}

//+------------------------------------------------------------------+
void UpdatePositionDataArrays()
{
   // Build temporary arrays to preserve existing position data
   int tempTickets[100];
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

   // Loop through all open orders
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagic)
         {
            int posType = OrderType();
            if(posType == OP_BUY || posType == OP_SELL)
            {
               int ticket = OrderTicket();

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
                     tempInitialSL[tempCount] = OrderStopLoss();
                     tempType[tempCount] = (posType == OP_BUY) ? 1 : 2;
                  }

                  tempCount++;
               }
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
int FindPositionIndex(int ticket)
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
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagic)
         {
            int posType = OrderType();
            if(posType == OP_BUY || posType == OP_SELL)
            {
               double currentPrice = (posType == OP_BUY) ? Bid : Ask;
               double openPrice = OrderOpenPrice();
               double currentSL = OrderStopLoss();
               double newSL = currentSL;

               double requiredMoveForBreakeven = (RangeSize > 0) ? RangeSize * BreakevenTriggerPct / 100 : 0;

               if(posType == OP_BUY)
               {
                  ManageBuyStopLoss(currentPrice, openPrice, currentSL, newSL, OrderTicket(), requiredMoveForBreakeven);
               }
               else if(posType == OP_SELL)
               {
                  ManageSellStopLoss(currentPrice, openPrice, currentSL, newSL, OrderTicket(), requiredMoveForBreakeven);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
void ManageBuyStopLoss(double currentPrice, double openPrice, double currentSL, double &newSL, int ticket, double requiredMoveForBreakeven)
{
   int posIndex = FindPositionIndex(ticket);
   if(posIndex == -1) return;

   double tp = OrderTakeProfit();
   double priceMove = currentPrice - openPrice;
   double point = MarketInfo(Symbol(), MODE_POINT);

   // Convert required moves to points
   double requiredMovePoints = requiredMoveForBreakeven;
   double requiredAdditionalMove = (RangeSize > 0) ? RangeSize * NextMoveTriggerPct / 100 : 0;

   Print("Buy #", ticket, " - PriceMove: ", NormalizeDouble(priceMove/point, 0), " points, Required: ", NormalizeDouble(requiredMovePoints/point, 0), " points, Breakeven: ", positionBreakevenReached[posIndex], ", NextMove: ", positionNextMoveReached[posIndex]);

   if(!positionBreakevenReached[posIndex] && priceMove >= requiredMovePoints)
   {
      newSL = NormalizePrice(openPrice);

      // Use safe order modify
      bool result = SafeOrderModify(ticket, OrderOpenPrice(), newSL, tp, clrBlue);
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
      int currentTF = GetCurrentTimeframe(positionTimeframeLevel[posIndex]);
      double atrTrendValue = GetATRTrendIndValue(currentTF, 1);

      Print("Buy #", ticket, " - ATR Value: ", atrTrendValue, ", Current SL: ", currentSL, ", Timeframe: ", GetTimeframeName(positionTimeframeLevel[posIndex]));

      // Simplified condition for BUY positions: ATR should be above current SL
      if(atrTrendValue > 0 && atrTrendValue > currentSL && atrTrendValue > positionBreakevenPrice[posIndex])
      {
         newSL = NormalizePrice(atrTrendValue);

         // Use safe order modify
         bool result = SafeOrderModify(ticket, OrderOpenPrice(), newSL, tp, clrBlue);
         if(result)
         {
            Print("SUCCESS: Buy #", ticket, " SL updated to ", newSL, " (", GetTimeframeName(positionTimeframeLevel[posIndex]), " ATR)");

            // Progress to next timeframe only if modification was successful
            if(positionTimeframeLevel[posIndex] < 5)
            {
               positionTimeframeLevel[posIndex]++;
               Print("Buy #", ticket, " progressing to ", GetTimeframeName(positionTimeframeLevel[posIndex]), " timeframe");
            }
         }
      }
      else if(atrTrendValue > 0)
      {
         Print("Buy #", ticket, " - ATR condition not met: ATR=", atrTrendValue, ", CurrentSL=", currentSL, ", Breakeven=", positionBreakevenPrice[posIndex]);
      }
   }
}

//+------------------------------------------------------------------+
void ManageSellStopLoss(double currentPrice, double openPrice, double currentSL, double &newSL, int ticket, double requiredMoveForBreakeven)
{
   int posIndex = FindPositionIndex(ticket);
   if(posIndex == -1) return;

   double tp = OrderTakeProfit();
   double priceMove = openPrice - currentPrice;
   double point = MarketInfo(Symbol(), MODE_POINT);

   // Convert required moves to points
   double requiredMovePoints = requiredMoveForBreakeven;
   double requiredAdditionalMove = (RangeSize > 0) ? RangeSize * NextMoveTriggerPct / 100 : 0;

   Print("Sell #", ticket, " - PriceMove: ", NormalizeDouble(priceMove/point, 0), " points, Required: ", NormalizeDouble(requiredMovePoints/point, 0), " points, Breakeven: ", positionBreakevenReached[posIndex], ", NextMove: ", positionNextMoveReached[posIndex]);

   if(!positionBreakevenReached[posIndex] && priceMove >= requiredMovePoints)
   {
      newSL = NormalizePrice(openPrice);

      // Use safe order modify
      bool result = SafeOrderModify(ticket, OrderOpenPrice(), newSL, tp, clrRed);
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
      int currentTF = GetCurrentTimeframe(positionTimeframeLevel[posIndex]);
      double atrTrendValue = GetATRTrendIndValue(currentTF, 1);

      Print("Sell #", ticket, " - ATR Value: ", atrTrendValue, ", Current SL: ", currentSL, ", Timeframe: ", GetTimeframeName(positionTimeframeLevel[posIndex]));

      // Simplified condition for SELL positions: ATR should be below current SL
      if(atrTrendValue > 0 && atrTrendValue < currentSL && atrTrendValue < positionBreakevenPrice[posIndex])
      {
         newSL = NormalizePrice(atrTrendValue);

         // Use safe order modify
         bool result = SafeOrderModify(ticket, OrderOpenPrice(), newSL, tp, clrRed);
         if(result)
         {
            Print("SUCCESS: Sell #", ticket, " SL updated to ", newSL, " (", GetTimeframeName(positionTimeframeLevel[posIndex]), " ATR)");

            // Progress to next timeframe only if modification was successful
            if(positionTimeframeLevel[posIndex] < 5)
            {
               positionTimeframeLevel[posIndex]++;
               Print("Sell #", ticket, " progressing to ", GetTimeframeName(positionTimeframeLevel[posIndex]), " timeframe");
            }
         }
      }
      else if(atrTrendValue > 0)
      {
         Print("Sell #", ticket, " - ATR condition not met: ATR=", atrTrendValue, ", CurrentSL=", currentSL, ", Breakeven=", positionBreakevenPrice[posIndex]);
      }
   }
}

//+------------------------------------------------------------------+
int GetCurrentTimeframe(int level)
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
int GetTimeframeLevel(int timeframe)
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
   string currentDate = StringFormat("%d.%02d.%02d", TimeYear(TimeCurrent()), TimeMonth(TimeCurrent()), TimeDay(TimeCurrent()));
   string startTimeStr = StringFormat("%s %02d:%02d", currentDate, RangeStartHour, RangeStartMin);
   string endTimeStr = StringFormat("%s %02d:%02d", currentDate, RangeEndHour, RangeEndMin);

   timestart = StringToTime(startTimeStr);
   timeend = StringToTime(endTimeStr);

   if(BarsRangeStart == 0 && TimeCurrent() >= timestart)
   {
      BarsRangeStart = Bars;
   }
}

//+------------------------------------------------------------------+
double GetHigh()
{
   double high = 0;
   int highestbar = 0;
   if(TimeCurrent() > timestart && TimeCurrent() < timeend)
   {
      BarstoCount = Bars - BarsRangeStart + 1;
      highestbar = iHighest(NULL, InpTimeframe, MODE_HIGH, BarstoCount, 0);
      high = iHigh(NULL, InpTimeframe, highestbar);
      if(high != RangeHigh) return high;
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
      BarstoCount = Bars - BarsRangeStart + 1;
      lowestbar = iLowest(NULL, InpTimeframe, MODE_LOW, BarstoCount, 0);
      low = iLow(NULL, InpTimeframe, lowestbar);
      if(low != RangeLow) return low;
   }
   return RangeLow;
}

//+------------------------------------------------------------------+
void ShowRange(double high, double low)
{
   if(ObjectFind("range") < 0)
   {
      ObjectCreate("range", OBJ_RECTANGLE, 0, timestart, high, timeend, low);
   }
   else
   {
      ObjectMove("range", 0, timestart, high);
      ObjectMove("range", 1, timeend, low);
   }

   ObjectSet("range", OBJPROP_BACK, true);

   double point = MarketInfo(Symbol(), MODE_POINT);
   double pipSize = point * 10;

   if(RangeSize < MaxRangeSize * pipSize && RangeSize > MinRangeSize * pipSize)
   {
      ObjectSet("range", OBJPROP_COLOR, rangecolor);
   }
   else
   {
      ObjectSet("range", OBJPROP_COLOR, rangecolordisabled);
   }

   if(ObjectFind("tradingtime") < 0)
   {
      ObjectCreate("tradingtime", OBJ_RECTANGLE, 0, timeend, high, TimeCurrent() + 86400, low);
   }
   else
   {
      ObjectMove("tradingtime", 0, timeend, high);
      ObjectMove("tradingtime", 1, TimeCurrent() + 86400, low);
   }
   ObjectSet("tradingtime", OBJPROP_COLOR, rangecolor);
   ObjectSet("tradingtime", OBJPROP_BACK, true);
}

//+------------------------------------------------------------------+
bool IsInsideTime()
{
   int nowmin = TimeHour(TimeCurrent()) * 60 + TimeMinute(TimeCurrent());
   int startmin = TimeHour(timestart) * 60 + TimeMinute(timestart);

   if(nowmin >= startmin) return true;

   return false;
}

//+------------------------------------------------------------------+
void PrepareOrder()
{
   if(TimeCurrent() > timeend)
   {
      double ask = Ask;
      double point = MarketInfo(Symbol(), MODE_POINT);
      double pipSize = point * 10;

      if(RangeSize > MinRangeSize * pipSize && RangeSize < MaxRangeSize * pipSize)
      {
         if(ask < RangeHigh - (RangeSize * OrdDistpct / 100) && ask > RangeLow + (RangeSize * OrdDistpct / 100))
         {
            if(TradingStyle == 0)
            {
               if(BuyTotal <= 0 && MA_BuyOn == true && Ichi_BuyOn == true)
               {
                  OpenTrade(OP_BUYSTOP, RangeHigh, RangeHigh - (RangeSize * SLPercent / 100));
               }
               if(SellTotal <= 0 && MA_SellOn == true && Ichi_SellOn == true)
               {
                  OpenTrade(OP_SELLSTOP, RangeLow, RangeLow + (RangeSize * SLPercent / 100));
               }
            }
            if(TradingStyle == 1)
            {
               if(BuyTotal <= 0 && MA_BuyOn == true && Ichi_BuyOn == true)
               {
                  OpenTrade(OP_BUYLIMIT, RangeLow, RangeLow - (RangeSize * SLPercent / 100));
               }
               if(SellTotal <= 0 && MA_SellOn == true && Ichi_SellOn == true)
               {
                  OpenTrade(OP_SELLLIMIT, RangeHigh, RangeHigh + (RangeSize * SLPercent / 100));
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
void OpenTrade(int type, double price, double sl)
{
   if((MAFilterOn == true && MA_BuyOn == true) &&
      (type == OP_BUYLIMIT || type == OP_BUYSTOP) &&
      (PricevsMovAvg() == "below" || PricevsMovAvg() == "error"))
   {
      MA_BuyOn = false;
      return;
   }
   if((MAFilterOn == true && MA_SellOn == true) &&
      (type == OP_SELLLIMIT || type == OP_SELLSTOP) &&
      (PricevsMovAvg() == "above" || PricevsMovAvg() == "error"))
   {
      MA_SellOn = false;
      return;
   }

   if((IchimokuFilter == true && Ichi_BuyOn == true) &&
      (type == OP_BUYLIMIT || type == OP_BUYSTOP) &&
      (PricevsIchiCloud() == "below" || PricevsIchiCloud() == "Incloud"))
   {
      Ichi_BuyOn = false;
      return;
   }
   if((IchimokuFilter == true && Ichi_SellOn == true) &&
      (type == OP_SELLLIMIT || type == OP_SELLSTOP) &&
      (PricevsIchiCloud() == "above" || PricevsIchiCloud() == "Incloud"))
   {
      Ichi_SellOn = false;
      return;
   }

   double tp = price + (price - sl) * TPPercent / SLPercent;

   double lots = 0.01;
   if(LotSizeType == 0)
   {
      lots = FixedLotSize;
   }
   else if(LotSizeType == 1)
   {
      lots = calcLots(price - sl);
   }

   int ticket = OrderSend(Symbol(), type, lots, price, 3, sl, tp, TradeComment, InpMagic, 0, clrBlue);
   if(ticket < 0)
   {
      int error = GetLastError();
      Print("Open Failed for ", Symbol(), ", ", type, ", price=", price, ", sl=", sl, ", tp=", tp, " Error: ", error);
   }
   else
   {
      Print("Order opened successfully: Ticket #", ticket, ", Type: ", type, ", Price: ", price, ", SL: ", sl, ", TP: ", tp);

      // Update position data for the new order
      UpdatePositionDataArrays();
   }
}

//+------------------------------------------------------------------+
void CloseandResetAll()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagic)
         {
            if(OrderType() == OP_BUY || OrderType() == OP_SELL)
            {
               double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
               bool result = OrderClose(OrderTicket(), OrderLots(), closePrice, 3, clrWhite);
               if(!result)
               {
                  Print("Error closing order #", OrderTicket(), ": ", GetLastError());
               }
            }
            else
            {
               bool result = OrderDelete(OrderTicket());
               if(!result)
               {
                  Print("Error deleting order #", OrderTicket(), ": ", GetLastError());
               }
            }
         }
      }
   }

   BarsRangeStart = 0;
   BuyTotal = 0;
   SellTotal = 0;

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
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagic && (OrderType() == OP_BUY || OrderType() == OP_SELL))
         {
            openPos++;
         }
      }
   }

   if(openPos > 0)
   {
      for(int j = OrdersTotal() - 1; j >= 0; j--)
      {
         if(OrderSelect(j, SELECT_BY_POS, MODE_TRADES))
         {
            if(OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagic && (OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP || OrderType() == OP_BUYLIMIT || OrderType() == OP_SELLLIMIT))
            {
               bool result = OrderDelete(OrderTicket());
               if(!result)
               {
                  Print("Error deleting pending order #", OrderTicket(), ": ", GetLastError());
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
   datetime currentTime = Time[0];
   if(previousTime != currentTime)
   {
      previousTime = currentTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
double calcLots(double slPoints)
{
   double risk = AccountBalance() * RiskPercent / 100;

   double ticksize = MarketInfo(Symbol(), MODE_TICKSIZE);
   double tickvalue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double lotstep = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minvolume = MarketInfo(Symbol(), MODE_MINLOT);
   double maxvolume = MarketInfo(Symbol(), MODE_MAXLOT);

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

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagic)
         {
            if(OrderType() == OP_BUYSTOP || OrderType() == OP_BUYLIMIT) BuyTotal++;
            if(OrderType() == OP_SELLSTOP || OrderType() == OP_SELLLIMIT) SellTotal++;
            if(OrderType() == OP_BUY) BuyTotal++;
            if(OrderType() == OP_SELL) SellTotal++;
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
   double ask = Ask;

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
