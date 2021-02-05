//+------------------------------------------------------------------+
//|                                                      DG_VWAP.mq5 |
//|                               Copyright 2020, DG Financial Corp. |
//|                                           https://www.google.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2021, DG Financial Corp."
#property link      "https://www.google.com"
#property version   "1.0"

#include "BarCounter.mqh"
#include "TransactionInfo.mqh"
#include <Trade\Trade.mqh>                                         // include the library for execution of trades
#include <Trade\PositionInfo.mqh>                                  // include the library for obtaining information on positions

enum ENUM_ORDER_ALLOWED
{
   BUY_ONLY, 
   SELL_ONLY,
   BUY_AND_SELL              
};

input ulong                MagicNumber = 10007;
input double               Volume = 100;

input group                "Buy/Sell Filer #1"
input ENUM_ORDER_ALLOWED   OrderAllowed = BUY_AND_SELL;
input ENUM_TIMEFRAMES      TimeFrame = PERIOD_CURRENT;
input int                  TakeProfitPercentOfCandle = 100;
input int                  PreviousCandlesLowHighCount = 2;
input int                  PreviousCandlesTraillingStop = 0; 
input int                  WaitCandlesAfterStopLoss = 0;

input group                "Mean Average #2"
input bool                 MAFilter = false;
int                        iMAFastHandle; 
double                     iMAFast[];                                      
input int                  MAFastPeriod = 8;  
int                        iMASlowHandle;                                      
double                     iMASlow[];                                      
input int                  MASlowPeriod = 20;  
input ENUM_MA_METHOD       MA_Method = MODE_SMA;   
input ENUM_APPLIED_PRICE   MA_AppliedPrice = PRICE_CLOSE;                          


input group                "Time #3"
input int                  MinHourToOpenOrder = 9;             
input int                  MinMinuteToOpenOrder = 0; 

input int                  MaxHourToOpenOrder = 12;             
input int                  MaxMinuteToOpenOrder = 0; 

input group                "Order Settings #4"
ulong                      OrderDeviationInPoints = 50;
input ENUM_ORDER_TYPE_TIME OrderLifeTime = ORDER_TIME_DAY;
ENUM_ORDER_TYPE_FILLING    OrderTypeFilling = ORDER_FILLING_RETURN;

MqlRates          Candles[];

MqlDateTime       CurrentTime;   

CTrade            m_Trade;                                         // structure for execution of trades
CPositionInfo     m_Position;                                      // structure for obtaining information of positions

CBarCounter                BarCounter;

ulong LastCandleTransaction = 0;

double Normalize(double value)
{
   return NormalizeDouble(value, _Digits);
}

int OnInit()
{
   ////////////////////////////////////////////////////
   // Fast MA
   //
   iMAFastHandle = iMA(_Symbol, TimeFrame, MAFastPeriod, 0, MA_Method, MA_AppliedPrice);  
   if(iMAFastHandle == INVALID_HANDLE)                                 
   {
      Print("Failed to get the indicator handle");                  
      return(INIT_FAILED);                                          
   }
   ArraySetAsSeries(iMAFast,true);        
   //
   ////////////////////////////////////////////////////

   ////////////////////////////////////////////////////
   // Slow MA
   //
   iMASlowHandle = iMA(_Symbol, TimeFrame, MASlowPeriod, 0, MA_Method, MA_AppliedPrice);  
   if(iMASlowHandle == INVALID_HANDLE)                                 
   {
      Print("Failed to get the indicator handle");                  
      return(INIT_FAILED);                                          
   }
   ArraySetAsSeries(iMASlow,true);        
   //
   ////////////////////////////////////////////////////

   ArraySetAsSeries(Candles, true);

   m_Trade.SetDeviationInPoints(OrderDeviationInPoints);
   m_Trade.SetTypeFilling(OrderTypeFilling);
   m_Trade.SetExpertMagicNumber(MagicNumber);
   
   BarCounter.ResetPerDay(true);

   return(INIT_SUCCEEDED);
}



void OnDeinit(const int reason)
{
   IndicatorRelease(iMAFastHandle);
   IndicatorRelease(iMASlowHandle);
   ArrayFree(iMAFast);
   ArrayFree(iMASlow);
   ArrayFree(Candles);
}



void OnTick()
{
   int BufferSize = (int)BarCounter.GetCounter() + 10;

   ////////////////////////////////////////////////////
   // Copy price information
   //
   if( CopyRates(_Symbol, TimeFrame, 0, BufferSize, Candles) < 0)
   {
      Print("Failed to copy rates");  
      return;
   }  
   
  
   ////////////////////////////////////////////////////
   // Check if this is a new candle
   // If it is not a new candle and we don't use the current candle, abort
   //
   BarCounter.OnTick();
   if (!BarCounter.IsNewBar() || BarCounter.GetCounter() < 4)
      return;
   //
   ////////////////////////////////////////////////////


   ////////////////////////////////////////////////////
   // Check if there is any open position
   //
   if (PositionsTotal() > 0)
   {
      ////////////////////////////////////////////////////
      // Check if trailing stop is activated
      //
      if (PreviousCandlesTraillingStop > 0)
      {
         TraillingStop();
      }
      return;
   }
   //
   ////////////////////////////////////////////////////
   

   ////////////////////////////////////////////////////
   // Copy Fast MA data
   //
   if(CopyBuffer(iMAFastHandle, 0, 0, BufferSize, iMAFast) < 0)               
   {
      Print("Failed to copy data from the indicator buffer or price chart buffer");  
      return; 
   }
   //
   ////////////////////////////////////////////////////

   ////////////////////////////////////////////////////
   // Copy Slow MA data
   //
   if(CopyBuffer(iMASlowHandle, 0, 0, BufferSize, iMASlow) < 0)               
   {
      Print("Failed to copy data from the indicator buffer or price chart buffer");  
      return; 
   }
   //
   ////////////////////////////////////////////////////


   
   ////////////////////////////////////////////////////
   // Check time allowed to open position
   //
   TimeToStruct(TimeCurrent(), CurrentTime);
   bool TimeAllowedToOpenOrder = (CurrentTime.hour >= MinHourToOpenOrder && CurrentTime.min >= MinMinuteToOpenOrder) 
                                 && ((CurrentTime.hour < MaxHourToOpenOrder) || (CurrentTime.hour == MaxHourToOpenOrder && CurrentTime.min <= MaxMinuteToOpenOrder));
   //
   ////////////////////////////////////////////////////


   

   ////////////////////////////////////////////////////
   // Compute VWAP
   //
   double vwap = Normalize(ComputeVWAP((int)BarCounter.GetCounter()));
   //
   ////////////////////////////////////////////////////

   bool Crossing = (Normalize(Candles[1].high) > vwap) && (Normalize(Candles[1].low) < vwap);
   

   bool Below           = (Normalize(Candles[2].high) < vwap);
   bool Above           = (Normalize(Candles[2].low) > vwap);

   bool ClosePrevAbove  = Normalize(Candles[2].close) >= Normalize(Candles[1].low);
   bool ClosePrevBelow  = Normalize(Candles[2].close) <= Normalize(Candles[1].high);

   bool PrevAbove       = Normalize(Candles[2].close) >= vwap;
   bool PrevBelow       = Normalize(Candles[2].close) <= vwap;

   bool PrevHighLower   = Normalize(Candles[2].high) <= Normalize(Candles[1].high);
   bool PrevLowHigher   = Normalize(Candles[2].low) >= Normalize(Candles[1].low);

   
   bool AboveMASlow     = Normalize(Candles[1].close) > Normalize(iMASlow[1]);
   bool BelowMASlow     = Normalize(Candles[1].close) < Normalize(iMASlow[1]);

   bool AboveMAFast     = Normalize(Candles[1].close) > Normalize(iMAFast[1]);
   bool BelowMAFast     = Normalize(Candles[1].close) < Normalize(iMAFast[1]);

   //////////////////////////////////////////////////////
   // Check if MA allows operation
   //
   bool MASellAllowed = true;
   bool MABuyAllowed = true;
   if (MAFilter)
   {
      MASellAllowed = BelowMAFast && BelowMASlow;
      MABuyAllowed = AboveMAFast && AboveMASlow;
   }
   //
   //////////////////////////////////////////////////////

   bool CandlesMinLower  = true;
   bool CandlesMaxHigher = true;
   int  BeginCandle = 1; //UseCurrentCandleForLowHigh ? 0 : 1;
   for (int i = BeginCandle; i < PreviousCandlesLowHighCount + BeginCandle; ++i)
   {
      CandlesMinLower = CandlesMinLower && Candles[i].low <= Candles[i+1].low;
      CandlesMaxHigher= CandlesMaxHigher && Candles[i].high >= Candles[i+1].high;
   }

   if (Crossing && PrevHighLower && OrderAllowed != BUY_ONLY && CandlesMaxHigher && MASellAllowed)
   {
      if (OrdersTotal() > 0)
      {
         ModifySellOrder();
      }
      else
      {
         if (TimeAllowedToOpenOrder)
            SellStop();
      }
   }
   else if (Crossing && PrevLowHigher && OrderAllowed != SELL_ONLY && CandlesMinLower && MABuyAllowed)
   {
      if (OrdersTotal() > 0)
      {
         ModifyBuyOrder();
      }
      else
      {
         if (TimeAllowedToOpenOrder)
            BuyStop();  
      }
   }
   else
   {
      Print("----------- Verificar Condicao -----------");
      DeletePendingOrders();
   }
}



void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
      

//     Print("################################################### INFO < ", BarCounter.GetCounter());
//     PrintTransactionInfo(trans, request, result);
//     Print("################################################### INFO >");
      
     if(trans.symbol == _Symbol)
     {
          if (trans.type == TRADE_TRANSACTION_DEAL_ADD) 
          {
              LastCandleTransaction = BarCounter.GetCounter();
              
              switch(trans.deal_type)
              {
                  case DEAL_TYPE_BUY : ModifyBuyStopLoss(trans.order, trans.price_tp); break;
                  case DEAL_TYPE_SELL : ModifySellStopLoss(trans.order, trans.price_tp); break;
                  default: break;
              }
          }
     }       
}



void BuyStop()
{  
   Print("------------------------------------------------ Buy Stop ", BarCounter.GetCounter());
   double ProfitScale  = TakeProfitPercentOfCandle / 100.0;  
   double Price        = MathMax(Candles[1].high, SymbolInfoDouble(_Symbol, SYMBOL_ASK)); 
   double StopLoss     = NormalizeDouble(Candles[1].low, _Digits) - _Point * 2;   
   double TakeProfit   = NormalizeDouble(MathAbs(Candles[1].high - Candles[1].low) * ProfitScale + Candles[1].high, _Digits);  
   datetime Expiration = TimeTradeServer() + PeriodSeconds(PERIOD_D1);   
   string InfoComment  = StringFormat("Buy Stop %s %G lots at %s, SL=%s TP=%s",
                               _Symbol, 
                               Volume,
                               DoubleToString(Price, _Digits),
                               DoubleToString(StopLoss, _Digits),
                               DoubleToString(TakeProfit, _Digits));                          
                                 
   if(!m_Trade.BuyStop(Volume, Price, _Symbol, StopLoss, TakeProfit, OrderLifeTime, Expiration, InfoComment))
   {
      Print("-- Fail    BuyStop: [", m_Trade.ResultRetcode(), "] ", m_Trade.ResultRetcodeDescription());
   }
   else
   {
      Print("-- Success BuyStop: [", m_Trade.ResultRetcode(), "] ", m_Trade.ResultRetcodeDescription());
   }
}

void ModifyBuyOrder()
{
   Print("------------------------------------------------ Modify Buy Order ", BarCounter.GetCounter());
   double ProfitScale  = TakeProfitPercentOfCandle / 100.0;  
   double Price        = MathMax(Candles[1].high, SymbolInfoDouble(_Symbol, SYMBOL_ASK)); 
   double StopLoss     = NormalizeDouble(Candles[1].low, _Digits) - _Point * 3;   
   double TakeProfit   = NormalizeDouble(MathAbs(Candles[1].high - Candles[1].low) * ProfitScale + Candles[1].high, _Digits);  
   datetime Expiration = TimeTradeServer() + PeriodSeconds(PERIOD_D1);   
  
   if (OrdersTotal() == 1)
   {
      ulong Ticket = OrderGetTicket(0);
      if(OrderSelect(Ticket) && OrderGetString(ORDER_SYMBOL)==Symbol())
      {     
         if(!m_Trade.OrderModify(Ticket, Price, StopLoss, TakeProfit, OrderLifeTime, Expiration))
         {
            Print("-- Fail    BuyOrderModify: [", m_Trade.ResultRetcode(), "] ", m_Trade.ResultRetcodeDescription());
         }
         else
         {
            Print("-- Success BuyOrderModify: [", m_Trade.ResultRetcode(), "] ", m_Trade.ResultRetcodeDescription());
         }
      }
   }
   else
   {
      Print("******* Nao deveria ter mais de uma ordem pendente: ", OrdersTotal());
   }
}

void ModifyBuyStopLoss(ulong Ticket, double TakeProfit)
{
   Print("------------------------------------------------ Modify Buy Stop Loss ", BarCounter.GetCounter());
   double StopLoss = MathMin(Candles[1].low, Candles[0].low) - _Point * 1;
   m_Trade.PositionModify(Ticket, StopLoss, TakeProfit);
}



void SellStop()
{  
   Print("------------------------------------------------ Sell Stop ", BarCounter.GetCounter());
   double ProfitScale  = TakeProfitPercentOfCandle / 100.0;  
   double CandleRange  = Candles[1].high - Candles[1].low;
   double Price        = MathMin(Candles[1].low, SymbolInfoDouble(_Symbol, SYMBOL_BID)); 
   double StopLoss     = NormalizeDouble(Candles[1].high, _Digits) + _Point * 1;  
   double TakeProfit   = NormalizeDouble(Candles[1].low - CandleRange * ProfitScale, _Digits);  
   datetime Expiration = TimeTradeServer() + PeriodSeconds(PERIOD_D1);   
   string InfoComment  = StringFormat("Buy Stop %s %G lots at %s, SL=%s TP=%s",
                               _Symbol, 
                               Volume,
                               DoubleToString(Price, _Digits),
                               DoubleToString(StopLoss, _Digits),
                               DoubleToString(TakeProfit, _Digits));                          
                                 
   if(!m_Trade.SellStop(Volume, Price, _Symbol, StopLoss, TakeProfit, OrderLifeTime, Expiration, InfoComment))
   {
      Print("-- Fail    SellStop: [", m_Trade.ResultRetcode(), "] ", m_Trade.ResultRetcodeDescription());
   }
   else
   {
      Print("-- Success SellStop: [", m_Trade.ResultRetcode(), "] ", m_Trade.ResultRetcodeDescription());
   }
}



void ModifySellOrder()
{
   Print("------------------------------------------------ Modify Sell Order ", BarCounter.GetCounter());
   double ProfitScale  = TakeProfitPercentOfCandle / 100.0;  
   double CandleRange  = Candles[1].high - Candles[1].low;
   double Price        = MathMin(Candles[1].low, SymbolInfoDouble(_Symbol, SYMBOL_BID)); 
   double StopLoss     = NormalizeDouble(Candles[1].high, _Digits) + _Point * 3;    
   double TakeProfit   = NormalizeDouble(Candles[1].low - CandleRange * ProfitScale, _Digits);  
   datetime Expiration = TimeTradeServer() + PeriodSeconds(PERIOD_D1);   
  
   if (OrdersTotal() == 1)
   {
      ulong Ticket = OrderGetTicket(0);
      if(OrderSelect(Ticket) && OrderGetString(ORDER_SYMBOL)==Symbol())
      {     
         if(!m_Trade.OrderModify(Ticket, Price, StopLoss, TakeProfit, OrderLifeTime, Expiration))
         {
            Print("-- Fail    SellOrderModify: [", m_Trade.ResultRetcode(), "] ", m_Trade.ResultRetcodeDescription());
         }
         else
         {
            Print("-- Success SellOrderModify: [", m_Trade.ResultRetcode(), "] ", m_Trade.ResultRetcodeDescription());
         }
      }
   }
   else
   {
      Print("******* Nao deveria ter mais de uma ordem pendente: ", OrdersTotal());
   }
}



void ModifySellStopLoss(ulong Ticket, double TakeProfit)
{
   Print("------------------------------------------------ Modify Sell Stop Loss ", BarCounter.GetCounter());
   double StopLoss = MathMax(Candles[1].high, Candles[0].high) + _Point * 1; 
   m_Trade.PositionModify(Ticket, StopLoss, TakeProfit);
}




void DeletePendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket) && OrderGetString(ORDER_SYMBOL) == Symbol())
      {
         m_Trade.OrderDelete(ticket);
      }
   }
}


void TraillingStop()
{
   for (int i = 0; i < PositionsTotal(); i++)
   {
      if (PositionGetSymbol(i) == _Symbol) // && PositionGetInteger(POSITION_MAGIC)
      {
         ulong Ticket = PositionGetInteger(POSITION_TICKET);
         double StopLoss = PositionGetDouble(POSITION_SL);
         double TakeProfit = PositionGetDouble(POSITION_TP);
         
         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            m_Trade.PositionModify(Ticket, Candles[PreviousCandlesTraillingStop].low, TakeProfit);
         }
         else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            m_Trade.PositionModify(Ticket, Candles[PreviousCandlesTraillingStop].high, TakeProfit);
         }
      } 
   }
}


double ComputeVWAP(int barCount)
{
   long volume_sum = 0;
   double price_volume_sum = 0.0;

   for (int i = 1; i <= barCount; ++i)
   {
      double mean_price = (Candles[i].close + Candles[i].high + Candles[i].low) / 3.0;
      price_volume_sum = price_volume_sum + (mean_price * Candles[i].real_volume);
      volume_sum += Candles[i].real_volume;
   }

   return price_volume_sum / volume_sum;
}



bool IsStrongBar(double o, double h, double l, double c, int closePercentage)
{
   int percentage = 0;
   if (c > o)  // bull bar
      percentage = (int)((c - l) / (h - l)) * 100;
   else        // bear bar
      percentage = 100 - (int)((c - l) / (h - l)) * 100;
   return percentage >= closePercentage;
}