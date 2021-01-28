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
input ENUM_ORDER_ALLOWED   OrderAllowed = BUY_AND_SELL;
input ENUM_TIMEFRAMES      TimeFrame = PERIOD_CURRENT;
input int                  TakeProfitPercentOfCandle = 100;
input double               Volume = 100;

input int                  PreviousCandlesTraillingStop = 0; 

ENUM_ORDER_TYPE_FILLING    OrderTypeFilling = ORDER_FILLING_RETURN;
ulong                      OrderDeviationInPoints = 50;

input ENUM_ORDER_TYPE_TIME OrderLifeTime = ORDER_TIME_DAY;

input int                  WaitCandlesAfterStopLoss = 0;

input int                  HourToOpenOrder = 9;             
input int                  MinuteToOpenOrder = 0; 

input int                  HourToCloseOrder = 12;             
input int                  MinuteToCloseOrder = 0; 

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
   ArraySetAsSeries(Candles, true);

   m_Trade.SetDeviationInPoints(OrderDeviationInPoints);
   m_Trade.SetTypeFilling(OrderTypeFilling);
   m_Trade.SetExpertMagicNumber(MagicNumber);
   
   BarCounter.ResetPerDay(true);

   return(INIT_SUCCEEDED);
}



void OnDeinit(const int reason)
{
   ArrayFree(Candles);
}



void OnTick()
{
   
   ////////////////////////////////////////////////////
   // Copy price information
   //
   if( CopyRates(_Symbol, TimeFrame, 0, (int)BarCounter.GetCounter() + 10, Candles) < 0)
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
   // Check time allowed to open position
   //
   TimeToStruct(TimeCurrent(), CurrentTime);
   bool TimeAllowedToOpenOrder = (CurrentTime.hour >= HourToOpenOrder && CurrentTime.min >= MinuteToOpenOrder) 
                                 && ((CurrentTime.hour < HourToCloseOrder) || (CurrentTime.hour == HourToCloseOrder && CurrentTime.min <= MinuteToCloseOrder));
   //
   ////////////////////////////////////////////////////



   

   ////////////////////////////////////////////////////
   // Compute VWAP
   //
   double vwap = Normalize(ComputeVWAP((int)BarCounter.GetCounter()));
   //
   ////////////////////////////////////////////////////

   bool Crossing = (Normalize(Candles[1].high) > vwap) && (Normalize(Candles[1].low) < vwap);
   

   bool Below = (Normalize(Candles[2].high) < vwap);
   bool Above = (Normalize(Candles[2].low) > vwap);

   bool ClosePrevAbove = Normalize(Candles[2].close) >= Normalize(Candles[1].low);
   bool ClosePrevBelow = Normalize(Candles[2].close) <= Normalize(Candles[1].high);

   bool PrevAbove = Normalize(Candles[2].close) >= vwap;
   bool PrevBelow = Normalize(Candles[2].close) <= vwap;

   bool PrevHighLower = Normalize(Candles[2].high) <= Normalize(Candles[1].high);
   bool PrevLowHigher = Normalize(Candles[2].low) >= Normalize(Candles[1].low);

   

   if (Crossing && PrevHighLower)
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
   else if (Crossing && PrevLowHigher)
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