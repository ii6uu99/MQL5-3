//+------------------------------------------------------------------+
//|                                                      DG_DL01.mq5 |
//|                               Copyright 2020, DG Financial Corp. |
//|                                           https://www.google.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2020, DG Financial Corp."
#property link      "https://www.google.com"
#property version   "1.00"


#include <Trade\Trade.mqh>                                         // include the library for execution of trades
#include <Trade\PositionInfo.mqh>                                  // include the library for obtaining information on positions

int               iMA_Handle;                                      // variable for storing the indicator handle
double            iMA_Data[];                                      // dynamic array for storing indicator values
int               MA_Period = 20;                                  // number of candles to be computed 
double            ClosePrices[];                                   // dynamic array for storing the closing price of each bar
double            HighPrices[];                                    // dynamic array for storing the highest price of each bar
double            LowPrices[];                                     // dynamic array for storing the lowest price of each bar


CTrade            m_Trade;                                         // structure for execution of trades
CPositionInfo     m_Position;                                      // structure for obtaining information of positions


int OnInit()
{
   iMA_Handle=iMA(_Symbol, _Period, MA_Period, 0, MODE_SMA, PRICE_CLOSE);  // apply the indicator and get its handle
   if(iMA_Handle == INVALID_HANDLE)                                 // check the availability of the indicator handle
   {
      Print("Failed to get the indicator handle");                  // if the handle is not obtained, print the relevant error message into the log file
      return(-1);                                                   // complete handling the error
   }
  
   ArraySetAsSeries(iMA_Data,true);                                 // set iMA_Data array indexing as time series
   
   ArraySetAsSeries(ClosePrices,true);                              // set ClosePrices array indexing as time series
   ArraySetAsSeries(HighPrices,true);                               // set HighPrices array indexing as time series
   ArraySetAsSeries(LowPrices,true);                                // set LowPrices array indexing as time series

   return(INIT_SUCCEEDED);
}



void OnDeinit(const int reason)
{
   IndicatorRelease(iMA_Handle);                                   // deletes the indicator handle and deallocates the memory space it occupies
   ArrayFree(iMA_Data);                                            // free the dynamic array iMA_Data of data
   ArrayFree(ClosePrices);                                         // free the dynamic array ClosePrices of data
   ArrayFree(HighPrices);                                          // free the dynamic array HighPrices of data
   ArrayFree(LowPrices);                                           // free the dynamic array LowPrices of data
}



void OnTick()
{
 
   int err1 = CopyBuffer(iMA_Handle, 0, 0, 4, iMA_Data);           // copy data from the indicator array into the dynamic array iMA_buf for further work with them
   int err2 = CopyClose(_Symbol, _Period, 0, 4, ClosePrices);      // copy the price chart data into the dynamic array ClosePrices for further work with them
   int err3 = CopyHigh(_Symbol, _Period, 0, 4, HighPrices);         // copy the price chart data into the dynamic array HighPrices for further work with them
   int err4 = CopyLow(_Symbol, _Period, 0, 4, LowPrices);          // copy the price chart data into the dynamic array LowPrices for further work with them
   if(err1 < 0 || err2 < 0 || err3 < 0 || err4 < 0)                // in case of errors
   {
      Print("Failed to copy data from the indicator buffer or price chart buffer");  // then print the relevant error message into the log file
      return;                                                                        // and exit the function
   }


   bool PriceAboveMA = ClosePrices[1] > iMA_Data[1];
 
   bool TwoCandlesMinLower = LowPrices[1] < LowPrices[2] && LowPrices[2] < LowPrices[3]; 


   string InfoComment=StringFormat("---- %s %s %s",
                               DoubleToString(LowPrices[3], _Digits),
                               DoubleToString(LowPrices[2], _Digits),
                               DoubleToString(LowPrices[1], _Digits));

   Print(InfoComment);

   if (PriceAboveMA && TwoCandlesMinLower && PositionsTotal() == 0)
   {
      Comment("LowPrices[1] < LowPrices[2] && LowPrices[2] < LowPrices[3]");
      Print("***************************************************************");
            
      DeletePendingOrders();
      BuyStop(); 
   }
   else if (LowPrices[1] < LowPrices[2])
   {

      Comment("LowPrices[1] < LowPrices[2]");
   }
   else
   {
      Comment("Higher");
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
        Print("---- OnTradeTransaction");

        if(trans.symbol == _Symbol)
        {
                ENUM_DEAL_ENTRY deal_entry=(ENUM_DEAL_ENTRY) HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
                ENUM_DEAL_REASON deal_reason=(ENUM_DEAL_REASON) HistoryDealGetInteger(trans.deal,DEAL_REASON);
                PrintFormat("------- deal entry type=%s trans type=%s trans deal type=%s order-ticket=%d deal-ticket=%d deal-reason=%s",EnumToString(deal_entry),EnumToString(trans.type),EnumToString(trans.deal_type),trans.order,trans.deal,EnumToString(deal_reason));               
        }       
}

void BuyStop()
{
   Print("---- BuyStop");
   double Volume = 100;
   double point = SymbolInfoDouble(_Symbol,SYMBOL_POINT);         // point
   double Ask = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits); // current buy price
   //double price=1000*point;                                   // unnormalized open price
   //price=NormalizeDouble(price,_Digits);                       // normalizing open price
   int CandlePips = MathAbs(HighPrices[1] - LowPrices[1]) / _Point;
   int SL_pips= CandlePips + 1;  // Stop Loss in points
   double price = HighPrices[1];
   int TP_pips=CandlePips * 2;                                          // Take Profit in points
   double SL=price-SL_pips*point;                            // unnormalized SL value
   SL=NormalizeDouble(SL, _Digits);                             // normalizing Stop Loss
   double TP=price+TP_pips*point;                            // unnormalized TP value
   TP=NormalizeDouble(TP,_Digits);                             // normalizing Take Profit
   datetime Expiration=TimeTradeServer()+PeriodSeconds(PERIOD_D1);
   string InfoComment=StringFormat("Buy Stop %s %G lots at %s, SL=%s TP=%s",
                               _Symbol, Volume,
                               DoubleToString(price, _Digits),
                               DoubleToString(SL, _Digits),
                               DoubleToString(TP, _Digits));
//--- everything is ready, sending a Buy Stop pending order to the server 
   if(!m_Trade.BuyStop(Volume, price,_Symbol,SL,TP,ORDER_TIME_GTC,Expiration,InfoComment))
     {
      //--- failure message
      Print("---- BuyStop() method failed. Return code=", m_Trade.ResultRetcode(),
            ". Descrição do código: ", m_Trade.ResultRetcodeDescription());
     }
   else
     {
      Print("---- BuyStop() method executed successfully. Return code=", m_Trade.ResultRetcode(),
            " (", m_Trade.ResultRetcodeDescription(),")");
     }
}


void DeletePendingOrders()
{
   int ord_total = OrdersTotal();
   Print("---- DeletePendingOrders %d", ord_total);
   
   if(ord_total > 0)
   {
      for(int i=ord_total-1;i>=0;i--)
      {
         ulong ticket=OrderGetTicket(i);
         if(OrderSelect(ticket) && OrderGetString(ORDER_SYMBOL)==Symbol())
         {
            m_Trade.OrderDelete(ticket);
         }
      }
   }
}