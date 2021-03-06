//+------------------------------------------------------------------+
//|                                                CTrailingStop.mqh |
//|                                    Copyright 2017, Erwin Beckers |
//|                                              www.erwinbeckers.nl |
//+------------------------------------------------------------------+
#property copyright "Copyright 2017, Erwin Beckers"
#property link      "www.erwinbeckers.nl"
#property strict
// taken from https://www.forexfactory.com/showthread.php?t=446353

#include <CUtils.mqh>;
#include <COrders.mqh>;

enum TrailingMethods
{
   UseTrailingStops,
   UseRiskRewardRatios
};

enum TakeProfitRiskRewardRatios
{
   RR_1_1,
   RR_2_1,
   RR_3_1,
   RR_4_1,
   RR_5_1,
   RR_6_1
};

extern   string   __trailingStop__          = " ------- Trailing stoploss settings ------------";
extern   TrailingMethods            TrailingMethod = UseTrailingStops;   
extern   TakeProfitRiskRewardRatios TakeProfitAt   = RR_2_1;   
extern   double   OrderHiddenSL             = 50;   

extern   double   OrderTS1                  = 30;        
extern   double   OrderTS1Trigger           = 50;

extern   double   OrderTS2                  = 40;     
extern   double   OrderTS2Trigger           = 60; 

extern   double   OrderTS3                  = 50;       
extern   double   OrderTS3Trigger           = 70;
 
extern   double   OrderTS4                  = 60; 
extern   double   OrderTS4Trigger           = 80; 

extern   double   OrderTrail                = 10;

const int MAX_ORDERS = 500;

enum ORDER_STATE
{
   ORDER_OPENED,
   ORDER_OPENED_INITIAL_STOPLOSS,
   ORDER_LEVEL_1,
   ORDER_LEVEL_2,
   ORDER_LEVEL_3,
   ORDER_LEVEL_4,
   ORDER_TRAIL
};

//-------------------------------------------------------------------------
//-------------------------------------------------------------------------
class CTrailingStop
{
private:   
   COrders*    _orderMgnt;
   bool        IsBuy;
   int         Ticket;   
   double      OpenPrice;
   double      StopLoss;
   double      InitialStopLoss;
   double      RiskReward;
   ORDER_STATE State;
   string      _symbol;
   double      MaxRiskReward;
   
	double   _orderHiddenSL;
	double   _orderTS1;      
	double   _orderTS1Trigger;
	double   _orderTS2;
	double   _orderTS2Trigger;
	double   _orderTS3;
	double   _orderTS3Trigger;
	double   _orderTS4;
	double   _orderTS4Trigger;
public: 
   //-------------------------------------------------------------------------
   CTrailingStop(string symbol)
   {
      Ticket     = -1;
      _symbol    = symbol;
      _orderMgnt = new COrders(symbol);
	  
	  _orderHiddenSL = OrderHiddenSL;
	  _orderTS1 = OrderTS1; 
	  _orderTS2 = OrderTS2;
	  _orderTS3 = OrderTS3;  
	  _orderTS4 = OrderTS4;   
	  _orderTS1Trigger = OrderTS1Trigger;
	  _orderTS2Trigger = OrderTS2Trigger;
	  _orderTS3Trigger = OrderTS3Trigger;
	  _orderTS4Trigger = OrderTS4Trigger;
   }
   
   //-------------------------------------------------------------------------
   ~CTrailingStop()
   {
      delete _orderMgnt;
   }
   
   //-------------------------------------------------------------------------
   void SetInitalStoploss(int ticket, double stoploss)
   {
      Ticket = -1;
      if (OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
      {
         if (OrderSymbol() == _symbol)
         {
            Print(_symbol," Trail: Add order ticket:", ticket, " op:", DoubleToStr(OrderOpenPrice(),5),  " sl:",DoubleToStr(stoploss,5));
            IsBuy           = (OrderType()  == OP_BUY ||  OrderType()== OP_BUYLIMIT || OrderType()== OP_BUYSTOP);
            Ticket          = OrderTicket();
            OpenPrice       = OrderOpenPrice();
            InitialStopLoss = OrderStopLoss();
            StopLoss        = OrderStopLoss();
            RiskReward      = 0;
            MaxRiskReward   = 0;
            State           = ORDER_OPENED;
            if (stoploss > 0)
            {
               StopLoss        = stoploss;
               InitialStopLoss = stoploss;
               State            = ORDER_OPENED_INITIAL_STOPLOSS;
            }
            
            Trail();
         }
         else
         {
           Print(_symbol," Trail: symbol wrong:", OrderSymbol());
         }
      }
      else
      {
        Print(_symbol," Trail: ticket wrong:", ticket);
      }
   }
   
   //-------------------------------------------------------------------------
   double GetRiskReward(int ticket)
   {
      if (Ticket != ticket) return 0;
      return RiskReward;
   }
   
   //-------------------------------------------------------------------------
   double GetStoploss(int ticket)
   {
      if (Ticket != ticket) return 0;
      return StopLoss;
   }
   
   //-------------------------------------------------------------------------
   void Trail()
   {
      if (Ticket < 0) return;
      if (!IsTesting() && !IsOptimization())
      {
        if (!MarketInfo(_symbol, MODE_TRADEALLOWED)) return;
      }
      if (!OrderSelect(Ticket, SELECT_BY_TICKET, MODE_TRADES))
      {
         Print(_symbol," Trail: order was closed:", Ticket);
         Ticket     = -1;
         RiskReward = 0;
         MaxRiskReward =0;
         InitialStopLoss = 0;
         StopLoss   = 0;
         OpenPrice  = 0;
         State      = ORDER_OPENED;
         return;
      }
      
      if ( OrderCloseTime() != 0 ) 
      {
         Print(_symbol," Trail: order was closed:", Ticket);
         Ticket     = -1;
         RiskReward = 0;
         MaxRiskReward =0;
         InitialStopLoss = 0;
         StopLoss   = 0;
         OpenPrice  = 0;
         State      = ORDER_OPENED;
         return;
      }
      
      if (TrailingMethod == UseTrailingStops)
      {
         TrailFixed();
         return;
      }
      if (TrailingMethod == UseRiskRewardRatios)
      {
         TrailRiskReward();
         return;
      }
   }
   
   //-------------------------------------------------------------------------
   bool CloseOrder(double riskReward,double maxRiskReward) 
   {
      bool close=false;
      if (maxRiskReward > 6 && riskReward <=5) close=true;
      else if (maxRiskReward > 5 && riskReward <=4) close=true;
      else if (maxRiskReward > 4 && riskReward <=3) close=true;
      else if (maxRiskReward > 3 && riskReward <=2) close=true;
      else if (maxRiskReward > 2 && riskReward <=1) close=true;
      else if (maxRiskReward > 1 && riskReward <=0.1) close=true;
      if (!close) return false;
            
      Print(_symbol," Trail: Order:", Ticket, " Take profit at RR:"+DoubleToStr(riskReward,2)+" (max:"+DoubleToStr(maxRiskReward,2)+")");
      if ( _orderMgnt.CloseOrderByTicket(Ticket) ) Ticket=-1;
      return true;
   }
   
   //-------------------------------------------------------------------------
   void TrailRiskReward()
   {
      double askPrice = _utils.AskPrice(_symbol);
      double bidPrice = _utils.BidPrice(_symbol);
      
      if (IsBuy)
      {
         RiskReward = (bidPrice - OpenPrice) / MathAbs( OpenPrice - InitialStopLoss);
         MaxRiskReward = MathMax(MaxRiskReward, RiskReward);
         if (CloseOrder(RiskReward,MaxRiskReward)) return;
         
         if (bidPrice <= InitialStopLoss)
         {
            Print(_symbol," Trail: Order:", Ticket, " close SL hit (max:"+DoubleToStr(MaxRiskReward,2)+")");
            if ( _orderMgnt.CloseOrderByTicket(Ticket) ) Ticket=-1;
            return;
         }
      }
      else 
      {
         RiskReward = (OpenPrice - askPrice) / MathAbs( InitialStopLoss - OpenPrice);
         if (CloseOrder(RiskReward,MaxRiskReward)) return;
         
         if (askPrice >= InitialStopLoss)
         {
            Print(_symbol," Trail: Order:", Ticket, " close SL hit (max:"+DoubleToStr(MaxRiskReward,2)+")");
            if ( _orderMgnt.CloseOrderByTicket(Ticket) ) Ticket=-1;
            return;
         }
      }
      
      if (RiskReward >= 1 && TakeProfitAt == RR_1_1)
      {  
          Print(_symbol," Trail: Order:", Ticket, " close at 1:1 RR");
         if ( _orderMgnt.CloseOrderByTicket(Ticket) ) Ticket=-1;
         return;
      }
      
      if (RiskReward >= 2 && TakeProfitAt == RR_2_1)
      {  
          Print(_symbol," Trail: Order:", Ticket, " close at 2:1 RR");
         if ( _orderMgnt.CloseOrderByTicket(Ticket) ) Ticket=-1;
         return;
      }
      
      if (RiskReward >= 3 && TakeProfitAt == RR_3_1)
      {  
          Print(_symbol," Trail: Order:", Ticket, " close at 3:1 RR");
          if ( _orderMgnt.CloseOrderByTicket(Ticket) ) Ticket=-1;
         return;
      }
      if (RiskReward >= 4 && TakeProfitAt == RR_4_1)
      {  
          Print(_symbol," Trail: Order:", Ticket, " close at 4:1 RR");
          if ( _orderMgnt.CloseOrderByTicket(Ticket) ) Ticket=-1;
         return;
      }
      if (RiskReward >= 5 && TakeProfitAt == RR_5_1)
      {  
          Print(_symbol," Trail: Order:", Ticket, " close at 5:1 RR");
          if ( _orderMgnt.CloseOrderByTicket(Ticket) ) Ticket=-1;
         return;
      }
      if (RiskReward >= 6 && TakeProfitAt == RR_6_1)
      {  
          Print(_symbol," Trail: Order:", Ticket, " close at 6:1 RR");
          if ( _orderMgnt.CloseOrderByTicket(Ticket) ) Ticket=-1;
         return;
      }
   }
   
   //-------------------------------------------------------------------------
   void TrailFixed()
   {
      double      sl=0;
      double      nextLevel = 0;
      ORDER_STATE nextState = State;
      
      double askPrice = _utils.AskPrice(_symbol);
      double bidPrice = _utils.BidPrice(_symbol);
      
      if (!_orderMgnt.IsSpreadOk()) return;
      
      if (IsBuy)
      {
         RiskReward= (bidPrice - OpenPrice) / MathAbs( OpenPrice - InitialStopLoss);
         switch (State)
         {
            case ORDER_OPENED:
               StopLoss  = OpenPrice - _utils.PipsToPrice(_symbol,_orderHiddenSL);
               nextLevel = OpenPrice + _utils.PipsToPrice(_symbol,_orderTS1Trigger);
               nextState = ORDER_LEVEL_1;
            break;
            
            case ORDER_OPENED_INITIAL_STOPLOSS:
               // stoploss already set..
               nextLevel = OpenPrice + _utils.PipsToPrice(_symbol,_orderTS1Trigger);
               nextState = ORDER_LEVEL_1;
            break;
            
            case ORDER_LEVEL_1:
               StopLoss  = OpenPrice + _utils.PipsToPrice(_symbol,_orderTS1);
               nextLevel = OpenPrice + _utils.PipsToPrice(_symbol,_orderTS2Trigger);
               nextState = ORDER_LEVEL_2;
            break;
            
            case ORDER_LEVEL_2:
               StopLoss  = OpenPrice + _utils.PipsToPrice(_symbol,_orderTS2);
               nextLevel = OpenPrice + _utils.PipsToPrice(_symbol,_orderTS3Trigger);
               nextState = ORDER_LEVEL_3;
            break;
            
            case ORDER_LEVEL_3:
               StopLoss  = OpenPrice + _utils.PipsToPrice(_symbol,_orderTS3);
               nextLevel = OpenPrice + _utils.PipsToPrice(_symbol,_orderTS4Trigger);
               nextState = ORDER_LEVEL_4;
            break;
            
            case ORDER_LEVEL_4:
               StopLoss  = OpenPrice + _utils.PipsToPrice(_symbol,_orderTS4);
               nextLevel = OpenPrice + _utils.PipsToPrice(_symbol,_orderTS4Trigger + OrderTrail) ;
               nextState = ORDER_TRAIL;
            break;
            
            case ORDER_TRAIL:
               sl=askPrice - _utils.PipsToPrice(_symbol, OrderTrail);
               if (sl > StopLoss) StopLoss = sl;
            break;
         }
         
         if (bidPrice <= StopLoss)
         {
            Print(_symbol," Trail: Order:", Ticket," Close SL hit profit:", DoubleToStr(OrderProfit() + OrderSwap() + OrderCommission(),2));
            _orderMgnt.CloseOrderByTicket(Ticket);
         }
         else if (bidPrice >= nextLevel)
         {
            Print(_symbol," Trail: Order:", Ticket," op:", DoubleToStr(OpenPrice,5), "  bid:", DoubleToStr(bidPrice,5), " next level reached:", nextLevel, " nextstate:", nextState);
            State = nextState;
         }
      }
      else // of buy orders
      {
         RiskReward= (OpenPrice - askPrice) / MathAbs( InitialStopLoss - OpenPrice);
         // handle sell orders
         switch (State)
         {
            case ORDER_OPENED:
               StopLoss  = OpenPrice + _utils.PipsToPrice(_symbol,_orderHiddenSL );
               nextLevel = OpenPrice - _utils.PipsToPrice(_symbol,_orderTS1Trigger );
               nextState = ORDER_LEVEL_1;
            break;
            
            case ORDER_OPENED_INITIAL_STOPLOSS:
               // stoploss already set
               nextLevel = OpenPrice - _utils.PipsToPrice(_symbol,_orderTS1Trigger);
               nextState = ORDER_LEVEL_1;
            break;
            
            case ORDER_LEVEL_1:
               StopLoss  = OpenPrice - _utils.PipsToPrice(_symbol,_orderTS1);
               nextLevel = OpenPrice - _utils.PipsToPrice(_symbol,_orderTS2Trigger);
               nextState = ORDER_LEVEL_2;
            break;
            
            case ORDER_LEVEL_2:
               StopLoss  = OpenPrice - _utils.PipsToPrice(_symbol,_orderTS2);
               nextLevel = OpenPrice - _utils.PipsToPrice(_symbol,_orderTS3Trigger);
               nextState = ORDER_LEVEL_3;
            break;
            
            case ORDER_LEVEL_3:
               StopLoss  = OpenPrice - _utils.PipsToPrice(_symbol,_orderTS3);
               nextLevel = OpenPrice - _utils.PipsToPrice(_symbol,_orderTS4Trigger);
               nextState = ORDER_LEVEL_4;
            break;
            
            case ORDER_LEVEL_4:
               StopLoss  = OpenPrice - _utils.PipsToPrice(_symbol,_orderTS4);
               nextLevel = OpenPrice - _utils.PipsToPrice(_symbol,_orderTS4Trigger + OrderTrail);
               nextState = ORDER_TRAIL;
            break;
            
            case ORDER_TRAIL:
               sl = bidPrice + _utils.PipsToPrice(_symbol,OrderTrail);
               if (sl < StopLoss) StopLoss = sl;
            break;
         }
         //Print(" trailing sorder:", Ticket, " op:", OpenPrice, " ask:", askPrice, " bid:", bidPrice, " next:", NormalizeDouble(nextLevel,5), "  State:",State);
         if (askPrice >= StopLoss)
         {
            Print(_symbol," Trail: Order:", Ticket," Close SL hit profit:", DoubleToStr(OrderProfit() + OrderSwap() + OrderCommission(),2));
            _orderMgnt.CloseOrderByTicket(Ticket);
         }
         else if (askPrice <= nextLevel)
         {
            Print(_symbol," Trail: Order:", Ticket," op:", DoubleToStr(OpenPrice,5), "  ask:", DoubleToStr(askPrice,5), " next level reached:", nextLevel, " nextstate:", nextState);
            State = nextState;
         }
      }
   }
}; // class