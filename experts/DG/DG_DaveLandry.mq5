//+------------------------------------------------------------------+
//|                                                DG_DaveLandry.mq5 |
//|                               Copyright 2020, DG Financial Corp. |
//|                                           https://www.google.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2020, DG Financial Corp."
#property link      "https://www.google.com"
#property version   "1.0"

#include "BarCounter.mqh"
#include <Trade\Trade.mqh>                                         // include the library for execution of trades
#include <Trade\PositionInfo.mqh>                                  // include the library for obtaining information on positions

input ulong                MagicNumber = 12345;
input int                  PreviousCandlesCount = 1;
input int                  TakeProfitPercentOfCandle = 100;
input double               Volume = 100;

input int                  PreviousCandlesTraillingStop = 0; 

ENUM_ORDER_TYPE_FILLING    OrderTypeFilling = ORDER_FILLING_RETURN;
ulong                      OrderDeviationInPoints = 50;

int                        iMA_Handle;                                      // variable for storing the indicator handle
double                     iMA_Data[];                                      // dynamic array for storing indicator values
input int                  MA_Period = 20;  
input ENUM_MA_METHOD       MA_Method = MODE_SMA;   
input ENUM_APPLIED_PRICE   MA_AppliedPrice = PRICE_CLOSE;                          

input int                  HourToOpenOrder = 10;             
input int                  MinuteToOpenOrder = 00; 

MqlRates          Candles[];

MqlDateTime       CurrentTime;   

CTrade            m_Trade;                                         // structure for execution of trades
CPositionInfo     m_Position;                                      // structure for obtaining information of positions

CBarCounter                BarCounter;

int BufferSize = 4; //PreviousCandlesCount + 1;

int OnInit()
{
   iMA_Handle=iMA(_Symbol, _Period, MA_Period, 0, MA_Method, MA_AppliedPrice);  // apply the indicator and get its handle
   if(iMA_Handle == INVALID_HANDLE)                                 // check the availability of the indicator handle
   {
      Print("Failed to get the indicator handle");                  // if the handle is not obtained, print the relevant error message into the log file
      return(INIT_FAILED);                                                   // complete handling the error
   }
  
   ArraySetAsSeries(iMA_Data,true);                                 // set iMA_Data array indexing as time series
   
   ArraySetAsSeries(Candles, true);

   m_Trade.SetDeviationInPoints(OrderDeviationInPoints);
   m_Trade.SetTypeFilling(OrderTypeFilling);
   m_Trade.SetExpertMagicNumber(MagicNumber);

   return(INIT_SUCCEEDED);
}



void OnDeinit(const int reason)
{
   IndicatorRelease(iMA_Handle);                                   // deletes the indicator handle and deallocates the memory space it occupies
   ArrayFree(iMA_Data);                                            // free the dynamic array iMA_Data of data
   ArrayFree(Candles);
}



void OnTick()
{
   
   ////////////////////////////////////////////////////
   // Copy price information
   //
   if( CopyRates(_Symbol, _Period, 0, BufferSize, Candles) < 0)
   {
      Print("Failed to copy rates");  
      return;
   }  
   
   
   ////////////////////////////////////////////////////
   // Check if this is a new candle
   // If it is not a new candle, abort
   BarCounter.OnTick();
   if (!BarCounter.IsNewBar())
      return;
   //
   ////////////////////////////////////////////////////


   ////////////////////////////////////////////////////
   // Check if trailing stop is activated
   //
   if (PreviousCandlesTraillingStop > 0)
   {
      TraillingStop();
   }
   //
   ////////////////////////////////////////////////////


   ////////////////////////////////////////////////////
   // Check if there is any open position
   //
   if (PositionsTotal() > 0)
      return;
   //
   ////////////////////////////////////////////////////
   
   
   ////////////////////////////////////////////////////
   // Check time allowed to open position
   //
   TimeToStruct(TimeCurrent(), CurrentTime);
   if (CurrentTime.hour <= HourToOpenOrder && CurrentTime.min < MinuteToOpenOrder)
   {
      return;  // current time is not allowed to open order
   }
   //
   ////////////////////////////////////////////////////
   
   
   ////////////////////////////////////////////////////
   // Copy MM data
   //
   if(CopyBuffer(iMA_Handle, 0, 0, BufferSize, iMA_Data) < 0)               
   {
      Print("Failed to copy data from the indicator buffer or price chart buffer");  
      return; 
   }
   //
   ////////////////////////////////////////////////////


   bool PriceAboveMA     = Candles[1].close > iMA_Data[1];
   bool PriceBelowMA     = Candles[1].close < iMA_Data[1];
   bool CandlesMinLower  = true;
   bool CandlesMaxHigher = true;
   for (int i = 1; i < PreviousCandlesCount + 1; ++i)
   {
      CandlesMinLower = CandlesMinLower && Candles[i].low < Candles[i+1].low;
      CandlesMaxHigher= CandlesMaxHigher && Candles[i].high > Candles[i+1].high;
   }
 
   if (PriceAboveMA && CandlesMinLower)
   {   
      if (OrdersTotal() > 0)
         ModifyBuyOrder();
      else
         BuyStop();  
   }
   else if (PriceBelowMA && CandlesMaxHigher)
   {
      if (OrdersTotal() > 0)
         ModifySellOrder();
      else
         SellStop();
   }
   
        
   //double Bid = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
   //double Ask = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
   //double Balance = AccountInfoDouble(ACCOUNT_BALANCE);
   //double Equity  = AccountInfoDouble(ACCOUNT_EQUITY);
}



void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
     if(trans.symbol == _Symbol)
     {
          ENUM_DEAL_ENTRY deal_entry=(ENUM_DEAL_ENTRY) HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
          ENUM_DEAL_REASON deal_reason=(ENUM_DEAL_REASON) HistoryDealGetInteger(trans.deal,DEAL_REASON);
          //PrintFormat("------- deal entry type=%s trans type=%s trans deal type=%s order-ticket=%d deal-ticket=%d deal-reason=%s",EnumToString(deal_entry),EnumToString(trans.type),EnumToString(trans.deal_type),trans.order,trans.deal,EnumToString(deal_reason));               
            
          Print("-- ", EnumToString(deal_entry), " ", EnumToString(trans.type), " ", 
          EnumToString(trans.deal_type), " ", trans.order, " ", trans.deal, " ", EnumToString(deal_reason));  
     }       
}


void BuyStop()
{  
   double ProfitScale  = TakeProfitPercentOfCandle / 100.0 + 1.0;  
   double Price        = Candles[1].high;  
   double StopLoss     = NormalizeDouble(Candles[1].low, _Digits);   
   double TakeProfit   = NormalizeDouble(MathAbs(Candles[1].high - Candles[1].low) * ProfitScale + Candles[1].high, _Digits);  
   datetime Expiration = TimeTradeServer() + PeriodSeconds(PERIOD_D1);   
   string InfoComment  = StringFormat("Buy Stop %s %G lots at %s, SL=%s TP=%s",
                               _Symbol, 
                               Volume,
                               DoubleToString(Price, _Digits),
                               DoubleToString(StopLoss, _Digits),
                               DoubleToString(TakeProfit, _Digits));                          
                                 
   if(!m_Trade.BuyStop(Volume, Price, _Symbol, StopLoss, TakeProfit, ORDER_TIME_GTC, Expiration, InfoComment))
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
   double ProfitScale  = TakeProfitPercentOfCandle / 100.0 + 1.0;  
   double Price        = Candles[1].high; 
   double StopLoss     = NormalizeDouble(Candles[1].low, _Digits);   
   double TakeProfit   = NormalizeDouble(MathAbs(Candles[1].high - Candles[1].low) * ProfitScale + Candles[1].high, _Digits);  
   datetime Expiration = TimeTradeServer() + PeriodSeconds(PERIOD_D1);   
  
   if (OrdersTotal() == 1)
   {
      ulong Ticket = OrderGetTicket(0);
      if(OrderSelect(Ticket) && OrderGetString(ORDER_SYMBOL)==Symbol())
      {     
         if(!m_Trade.OrderModify(Ticket, Price, StopLoss, TakeProfit, ORDER_TIME_GTC, Expiration))
         {
            Print("-- Fail    OrderModify: [", m_Trade.ResultRetcode(), "] ", m_Trade.ResultRetcodeDescription());
         }
         else
         {
            Print("-- Success OrderModify: [", m_Trade.ResultRetcode(), "] ", m_Trade.ResultRetcodeDescription());
         }
      }
   }
   else
   {
      Print("******* Nao deveria ter mais de uma ordem pendente: ", OrdersTotal());
   }
}



void SellStop()
{  
   double ProfitScale  = TakeProfitPercentOfCandle / 100.0 + 1.0;  
   double Price        = NormalizeDouble(Candles[1].low, _Digits);   
   double StopLoss     = NormalizeDouble(Candles[1].high, _Digits);   
   double TakeProfit   = NormalizeDouble(MathAbs(Candles[1].low - Candles[1].high) * ProfitScale + Candles[1].low, _Digits);  
   datetime Expiration = TimeTradeServer() + PeriodSeconds(PERIOD_D1);   
   string InfoComment  = StringFormat("Buy Stop %s %G lots at %s, SL=%s TP=%s",
                               _Symbol, 
                               Volume,
                               DoubleToString(Price, _Digits),
                               DoubleToString(StopLoss, _Digits),
                               DoubleToString(TakeProfit, _Digits));                          
                                 
   if(!m_Trade.BuyStop(Volume, Price, _Symbol, StopLoss, TakeProfit, ORDER_TIME_GTC, Expiration, InfoComment))
   {
      Print("-- Fail    BuyStop: [", m_Trade.ResultRetcode(), "] ", m_Trade.ResultRetcodeDescription());
   }
   else
   {
      Print("-- Success BuyStop: [", m_Trade.ResultRetcode(), "] ", m_Trade.ResultRetcodeDescription());
   }
}



void ModifySellOrder()
{
   double ProfitScale  = TakeProfitPercentOfCandle / 100.0 + 1.0;  
   double Price        = NormalizeDouble(Candles[1].low, _Digits);  
   double StopLoss     = NormalizeDouble(Candles[1].high, _Digits);   
   double TakeProfit   = NormalizeDouble(MathAbs(Candles[1].low - Candles[1].high) * ProfitScale + Candles[1].low, _Digits);  
   datetime Expiration = TimeTradeServer() + PeriodSeconds(PERIOD_D1);   
  
   if (OrdersTotal() == 1)
   {
      ulong Ticket = OrderGetTicket(0);
      if(OrderSelect(Ticket) && OrderGetString(ORDER_SYMBOL)==Symbol())
      {     
         if(!m_Trade.OrderModify(Ticket, Price, StopLoss, TakeProfit, ORDER_TIME_GTC, Expiration))
         {
            Print("-- Fail    OrderModify: [", m_Trade.ResultRetcode(), "] ", m_Trade.ResultRetcodeDescription());
         }
         else
         {
            Print("-- Success OrderModify: [", m_Trade.ResultRetcode(), "] ", m_Trade.ResultRetcodeDescription());
         }
      }
   }
   else
   {
      Print("******* Nao deveria ter mais de uma ordem pendente: ", OrdersTotal());
   }
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

