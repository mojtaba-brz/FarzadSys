#ifndef KTR_ACCOUNT_MQH
#define KTR_ACCOUNT_MQH
struct KTRLedgerDeal
{
   datetime time; ulong pid; int type; int entry; double volume; double price; double money; double cash;
   string symbol;
};
struct KTRExposure { ulong pid; string symbol; int dir; double volume; double price; };
KTRLedgerDeal ktr_ledger[];
KTRExposure ktr_replay_positions[];
datetime ktr_day=0,ktr_account_refresh=0,ktr_sample_time=0,ktr_sample_end=0;
double ktr_day_balance=0,ktr_initial=0,ktr_later_cash=0,ktr_day_min=0,ktr_overall_min=0;
double ktr_commission=0,ktr_replay_balance=0,ktr_replay_cash=0;
bool ktr_daily_lock=false,ktr_liquidating=false,ktr_baseline_estimated=true,ktr_initial_known=false;
bool ktr_history_estimated=true,ktr_cash_history_complete=false;
bool ktr_replay_initial_removed=false,ktr_replay_daily_phase=true,ktr_replay_valid=true;
datetime ktr_older_start=0,ktr_replay_now=0;
double ktr_replay_start_balance=0,ktr_replay_credit=0,ktr_replay_start_credit=0;
const int KTR_MAX_LEDGER_DEALS=100000;
int ktr_replay_cursor=0,ktr_samples=0;
datetime KTRMidnight(const datetime now)
{ MqlDateTime d; TimeToStruct(now,d); d.hour=0; d.min=0; d.sec=0; return StructToTime(d); }
double KTRDealMoney(const ulong deal)
{ return HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_SWAP)+HistoryDealGetDouble(deal,DEAL_FEE); }
bool KTRExternalCash(const int type)
{ return type==DEAL_TYPE_BALANCE || type==DEAL_TYPE_CREDIT || type==DEAL_TYPE_BONUS || type==DEAL_TYPE_CORRECTION; }
void KTRLoadAccountHistory(const bool reset)
{
   if(!HistorySelect(0,TimeCurrent())) { ktr_baseline_estimated=true; return; }
   int total=HistoryDealsTotal(),offset=MathMax(0,total-KTR_MAX_LEDGER_DEALS),n=total-offset;
   ArrayResize(ktr_ledger,n);
   double today=0,first_deposit=0,later_cash=0,sum=0,credits=0; datetime first_time=0;
   ktr_commission=Commission_Reserve_Per_Lot;
   for(int i=0;i<n;i++)
   {
      ulong d=HistoryDealGetTicket(i+offset); KTRLedgerDeal item;
      item.time=(datetime)HistoryDealGetInteger(d,DEAL_TIME); item.type=(int)HistoryDealGetInteger(d,DEAL_TYPE);
      item.entry=(int)HistoryDealGetInteger(d,DEAL_ENTRY); item.pid=(ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID);
      item.volume=HistoryDealGetDouble(d,DEAL_VOLUME); item.price=HistoryDealGetDouble(d,DEAL_PRICE);
      item.symbol=HistoryDealGetString(d,DEAL_SYMBOL);
      double movement=KTRDealMoney(d);
      item.money=item.type==DEAL_TYPE_CREDIT?0:movement;
      item.cash=KTRExternalCash(item.type)?movement:0; sum+=item.money;
      if(item.type==DEAL_TYPE_CREDIT) credits+=movement;
      if(i==0) first_time=item.time;
      if(item.time>=ktr_day) today+=item.money;
      if(item.cash!=0)
      {
         if(first_deposit==0 && item.type==DEAL_TYPE_BALANCE && item.money>0) first_deposit=item.money;
         else later_cash+=item.cash;
      }
      if(item.volume>0) ktr_commission=MathMax(ktr_commission,
         2*(MathAbs(HistoryDealGetDouble(d,DEAL_COMMISSION))+MathAbs(HistoryDealGetDouble(d,DEAL_FEE)))/item.volume);
      // Broker execution evidence can preserve the daily emergency latch after restart.
      if(item.time>=ktr_day && StringFind(HistoryDealGetString(d,DEAL_COMMENT),"KTR!daily")==0) ktr_daily_lock=true;
      if(item.time>=ktr_day)
      {
         ulong order=(ulong)HistoryDealGetInteger(d,DEAL_ORDER);
         if(StringFind(HistoryOrderGetString(order,ORDER_COMMENT),"KTR!daily")==0) ktr_daily_lock=true;
      }
      ktr_ledger[i]=item;
   }
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   // Tester initial capital is a funding record on its first simulated day,
   // not a trading-day deposit to subtract into a fictitious zero baseline.
   // Only use an evidenced first record from a fully reconciled tester ledger.
   bool tester_initial=MQLInfoInteger(MQL_TESTER) && offset==0 && n>0 &&
      ktr_ledger[0].type==DEAL_TYPE_BALANCE && ktr_ledger[0].money>0 &&
      first_time>=ktr_day && first_time<ktr_day+86400 && MathAbs(sum-balance)<0.02;
   double funding=tester_initial?ktr_ledger[0].money:0;
   ktr_day_balance=KTRDailyBalance(balance,today,funding);
   ktr_baseline_estimated=offset>0 || first_time==0 || first_time>ktr_day || MathAbs(sum-balance)>0.02;
   if(tester_initial)
   {
      ktr_baseline_estimated=false;
      if(reset) PrintFormat("[KTR] Tester first-day baseline reconstructed from initial funding: B_day=%.2f funding=%.2f",ktr_day_balance,funding);
   }
   ktr_cash_history_complete=offset==0 && first_deposit>0 && MathAbs(sum-balance)<0.02 && MathAbs(credits-AccountInfoDouble(ACCOUNT_CREDIT))<0.02;
   ktr_initial_known=ktr_cash_history_complete;
   ktr_initial=Initial_Deposit_Override>0?Initial_Deposit_Override:first_deposit;
   if(Initial_Deposit_Override>0) ktr_initial_known=true;
   ktr_later_cash=later_cash;
   if(ktr_day_balance<=0) ktr_baseline_estimated=true;
   if(reset)
   {
      double equity=AccountInfoDouble(ACCOUNT_EQUITY);
      ktr_day_min=equity; ktr_overall_min=equity-later_cash;
      ktr_replay_now=TimeCurrent();
      ktr_older_start=(datetime)MathMax(first_time,ktr_replay_now-(long)Equity_History_Days*86400);
      // Reconstruct today's risk latch first, then older account-performance samples.
      ktr_sample_time=MathMax(ktr_day,ktr_older_start); ktr_sample_end=ktr_replay_now;
      ktr_replay_daily_phase=true; ktr_replay_initial_removed=false; ktr_replay_valid=true;
      ktr_replay_balance=balance; ktr_replay_cash=0; ktr_replay_cursor=0; ktr_samples=0;
      for(int i=0;i<n;i++) ktr_replay_balance-=ktr_ledger[i].money;
      ktr_replay_start_balance=ktr_replay_balance;
      ktr_replay_credit=AccountInfoDouble(ACCOUNT_CREDIT)-credits; ktr_replay_start_credit=ktr_replay_credit;
      ArrayResize(ktr_replay_positions,0);
   }
   ktr_account_refresh=TimeCurrent();
}
void KTRApplyReplayDeal(const KTRLedgerDeal &d)
{
   ktr_replay_balance+=d.money; ktr_replay_cash+=d.cash;
   if(d.type==DEAL_TYPE_CREDIT) ktr_replay_credit+=d.cash;
   // Initial deposit is the baseline, not a later cash adjustment.
   if(d.type==DEAL_TYPE_BALANCE && d.money>0 && !ktr_replay_initial_removed)
   { ktr_replay_cash-=d.cash; ktr_replay_initial_removed=true; }
   if(d.type!=DEAL_TYPE_BUY && d.type!=DEAL_TYPE_SELL) return;
   int p=-1;
   for(int i=0;i<ArraySize(ktr_replay_positions);i++) if(ktr_replay_positions[i].pid==d.pid) { p=i; break; }
   if(p<0)
   {
      if(d.entry!=DEAL_ENTRY_IN || ArraySize(ktr_replay_positions)>=128) { ktr_replay_valid=false; return; }
      p=ArraySize(ktr_replay_positions); ArrayResize(ktr_replay_positions,p+1);
      ZeroMemory(ktr_replay_positions[p]); ktr_replay_positions[p].pid=d.pid; ktr_replay_positions[p].symbol=d.symbol;
   }
   if(d.entry==DEAL_ENTRY_IN)
   {
      double v=ktr_replay_positions[p].volume;
      ktr_replay_positions[p].price=(ktr_replay_positions[p].price*v+d.price*d.volume)/(v+d.volume);
      ktr_replay_positions[p].volume=v+d.volume; ktr_replay_positions[p].dir=d.type==DEAL_TYPE_BUY?1:-1;
   }
   else
   {
      ktr_replay_positions[p].volume=MathMax(0,ktr_replay_positions[p].volume-d.volume);
      if(ktr_replay_positions[p].volume<1e-10)
      {
         int n=ArraySize(ktr_replay_positions);
         for(int i=p+1;i<n;i++) ktr_replay_positions[i-1]=ktr_replay_positions[i];
         ArrayResize(ktr_replay_positions,n-1);
      }
   }
}
void KTRHistoricalWork()
{
   if(ktr_sample_time>ktr_sample_end && ktr_replay_daily_phase)
   {
      ktr_replay_daily_phase=false; ktr_sample_time=ktr_older_start; ktr_sample_end=ktr_day-1;
      ktr_replay_cursor=0; ktr_replay_balance=ktr_replay_start_balance; ktr_replay_cash=0; ktr_replay_credit=ktr_replay_start_credit;
      ktr_replay_initial_removed=false; ktr_replay_valid=true; ArrayResize(ktr_replay_positions,0);
   }
   if(ktr_sample_time<=0 || ktr_sample_time>ktr_sample_end || ktr_samples>=Equity_Max_Samples) return;
   int step=MathMax(Equity_Sample_Seconds,(int)MathCeil((double)Equity_History_Days*86400/Equity_Max_Samples));
   for(int task=0;task<Equity_Samples_Per_Timer && ktr_sample_time<=ktr_sample_end && ktr_samples<Equity_Max_Samples;task++)
   {
      while(ktr_replay_cursor<ArraySize(ktr_ledger) && ktr_ledger[ktr_replay_cursor].time<=ktr_sample_time)
      { KTRApplyReplayDeal(ktr_ledger[ktr_replay_cursor]); ktr_replay_cursor++; }
      double estimate=ktr_replay_balance+ktr_replay_credit; bool complete=ktr_replay_valid;
      for(int p=0;p<ArraySize(ktr_replay_positions);p++)
      {
         if(ktr_replay_positions[p].volume<=0) continue;
         string symbol=ktr_replay_positions[p].symbol; SymbolSelect(symbol,true);
         MqlTick ticks[];
         // At most one second of ticks per exposure/sample, never an unbounded range.
         ulong end=(ulong)ktr_sample_time*1000;
         int got=CopyTicksRange(symbol,ticks,COPY_TICKS_INFO,end-999,end);
         if(got<=0 || ticks[got-1].bid<=0 || ticks[got-1].ask<=0) { complete=false; continue; }
         double close=ktr_replay_positions[p].dir>0?ticks[got-1].bid:ticks[got-1].ask,profit=0;
         if(!OrderCalcProfit(ktr_replay_positions[p].dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,symbol,
            ktr_replay_positions[p].volume,ktr_replay_positions[p].price,close,profit)) { complete=false; continue; }
         estimate+=profit;
      }
      // Missing any exposure mark invalidates this sample; don't treat absent P&L as zero.
      if(complete)
      {
         ktr_overall_min=MathMin(ktr_overall_min,estimate-ktr_replay_cash);
         if(ktr_sample_time>=ktr_day) ktr_day_min=MathMin(ktr_day_min,estimate);
      }
      ktr_sample_time+=step; ktr_samples++;
   }
   // Sampling and today's conversion/contract values cannot establish exact historical minima.
   ktr_history_estimated=true;
}
void KTRFastEmergency()
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   ktr_day_min=MathMin(ktr_day_min,equity); ktr_overall_min=MathMin(ktr_overall_min,equity-ktr_later_cash);
   if(ktr_day_balance>0 && equity<=ktr_day_balance*(1-Max_Daily_Risk_Percent/100.0))
      ktr_daily_lock=true;
   if(ktr_daily_lock && (PositionsTotal()>0 || OrdersTotal()>0)) ktr_liquidating=true;
   if(ktr_liquidating)
   {
      KTRCloseAll(true);
      if(PositionsTotal()==0 && OrdersTotal()==0) ktr_liquidating=false;
   }
}
void KTRAccountUpdate()
{
   datetime day=KTRMidnight(TimeTradeServer()>0?TimeTradeServer():TimeCurrent());
   bool reset=ktr_day!=day;
   if(reset)
   {
      ktr_day=day; ktr_daily_lock=false;
      // Carry unresolved liquidation across midnight until flat; the new day cannot unlock it.
      KTRLoadAccountHistory(true);
      if(ktr_baseline_estimated) Print("[KTR] Daily baseline Estimated: using available broker cash history and current equity; no exact-history claim");
   }
   else if(ktr_dirty || TimeCurrent()-ktr_account_refresh>=Broker_History_Refresh_Seconds) KTRLoadAccountHistory(false);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   ktr_day_min=MathMin(ktr_day_min,equity); ktr_overall_min=MathMin(ktr_overall_min,equity-ktr_later_cash);
   KTRFastEmergency();
}
bool KTROpenLoss(double &loss)
{
   loss=0;
   // Unassessed pending exposure anywhere on this dedicated account is not ignored.
   if(OrdersTotal()>0) return false;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(PositionGetTicket(i)==0) return false;
      string symbol=PositionGetString(POSITION_SYMBOL); MqlTick tick;
      if(!SymbolInfoTick(symbol,tick)) return false;
      double stop=PositionGetDouble(POSITION_SL),volume=PositionGetDouble(POSITION_VOLUME),profit=0;
      bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
      if(stop<=0 || (buy?stop>=tick.bid:stop<=tick.ask)) return false;
      if(!OrderCalcProfit(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,symbol,volume,buy?tick.bid:tick.ask,stop,profit)) return false;
      loss+=MathMax(0,-profit)+volume*ktr_commission;
   }
   return true;
}
string ktr_panel_prefix="";
void KTRPanel()
{
   if(!Show_Prop_Monitor) return;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY),daily=equity-ktr_day_balance;
   double dd=MathMax(0,ktr_day_balance-ktr_day_min),overall=MathMax(0,ktr_initial-ktr_overall_min);
   string text[5];
   text[0]=StringFormat("Today's P&L: %.2f (%.2f%%)%s",daily,ktr_day_balance>0?100*daily/ktr_day_balance:0,ktr_baseline_estimated?" [Estimated]":"");
   text[1]=StringFormat("Maximum Daily Drawdown: %.2f (%.2f%%) [Estimated]",dd,ktr_day_balance>0?100*dd/ktr_day_balance:0);
   text[2]=ktr_initial_known?StringFormat("Total P&L: %.2f (%.2f%%)%s",equity-ktr_later_cash-ktr_initial,
      100*(equity-ktr_later_cash-ktr_initial)/ktr_initial,(!ktr_cash_history_complete?" [Estimated cash flows]":(Initial_Deposit_Override>0?" [Override]":""))):"Total P&L: Unavailable (initial deposit history)";
   text[3]=ktr_initial_known?StringFormat("Maximum Overall Drawdown: %.2f (%.2f%%) [Estimated]",overall,100*overall/ktr_initial):"Maximum Overall Drawdown: Unavailable";
   text[4]=StringFormat("%s | Historical minima Estimated; sampled ticks/conversion incomplete (%d samples)",AccountInfoString(ACCOUNT_CURRENCY),ktr_samples);
   int width=660,height=5*(Monitor_Font_Size+10)+10;
   int x=Monitor_X,y=Monitor_Y;
   if(Monitor_Corner==CORNER_RIGHT_UPPER || Monitor_Corner==CORNER_RIGHT_LOWER)
      x=MathMax(0,(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)-Monitor_X-width);
   if(Monitor_Corner==CORNER_LEFT_LOWER || Monitor_Corner==CORNER_RIGHT_LOWER)
      y=MathMax(0,(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS)-Monitor_Y-height);
   string bg=ktr_panel_prefix+"bg";
   if(ObjectFind(0,bg)<0) ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER); ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,y); ObjectSetInteger(0,bg,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,height); ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,Monitor_Background_Color);
   for(int i=0;i<5;i++)
   {
      string name=ktr_panel_prefix+(string)i;
      if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x+5); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y+5+i*(Monitor_Font_Size+10));
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,Monitor_Font_Size); ObjectSetInteger(0,name,OBJPROP_COLOR,Monitor_Text_Color);
      ObjectSetString(0,name,OBJPROP_TEXT,text[i]);
   }
}
#endif
