#ifndef KTR_BROKER_MQH
#define KTR_BROKER_MQH
#include "Recovery.mqh"
struct KTRIntent { bool busy; bool uncertain; ulong order; string comment; datetime sent; };
KTRRecord ktr_records[];
int ktr_record_index[];
const int KTR_RECORD_HASH_SIZE=262147;
KTREpisode ktr_episode[2];
KTRIntent ktr_intent[2];
bool ktr_dirty=true,ktr_history_ok=false;
datetime ktr_history_time=0;
int KTRIndex(const int dir) { return dir>0?0:1; }
int KTRRecordSlot(const ulong pid)
{
   if(ArraySize(ktr_record_index)!=KTR_RECORD_HASH_SIZE) return -1;
   int slot=(int)(pid%KTR_RECORD_HASH_SIZE);
   while(ktr_record_index[slot]>=0 && ktr_records[ktr_record_index[slot]].pid!=pid) slot=(slot+1)%KTR_RECORD_HASH_SIZE;
   return slot;
}
int KTRFindRecord(const ulong pid)
{ int slot=KTRRecordSlot(pid); return slot<0?-1:ktr_record_index[slot]; }
bool KTRRefreshRecords()
{
   ktr_history_ok=HistorySelect(0,TimeCurrent());
   if(!ktr_history_ok) return false;
   ArrayResize(ktr_records,0); ArrayResize(ktr_record_index,KTR_RECORD_HASH_SIZE);
   ArrayInitialize(ktr_record_index,-1);
   for(int i=MathMax(0,HistoryDealsTotal()-100000);i<HistoryDealsTotal();i++)
   {
      ulong d=HistoryDealGetTicket(i);
      if((ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=Magic_Number || HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol ||
         (ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
      ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(d,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
      ulong pid=(ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID);
      datetime time=(datetime)HistoryDealGetInteger(d,DEAL_TIME);
      int n=KTRFindRecord(pid);
      if(n>=0)
      {
         double v=HistoryDealGetDouble(d,DEAL_VOLUME),prior=ktr_records[n].fill_volume;
         if(prior+v>0) ktr_records[n].fill_price=(ktr_records[n].fill_price*prior+HistoryDealGetDouble(d,DEAL_PRICE)*v)/(prior+v);
         ktr_records[n].fill_volume+=v; ktr_records[n].executed=MathMax(ktr_records[n].executed,time); continue;
      }
      n=ArraySize(ktr_records); ArrayResize(ktr_records,n+1);
      ktr_records[n].pid=pid;
      int slot=KTRRecordSlot(pid); if(slot>=0) ktr_record_index[slot]=n; ktr_records[n].order=(ulong)HistoryDealGetInteger(d,DEAL_ORDER);
      ktr_records[n].fill_volume=HistoryDealGetDouble(d,DEAL_VOLUME); ktr_records[n].fill_price=HistoryDealGetDouble(d,DEAL_PRICE);
      ktr_records[n].dir=type==DEAL_TYPE_BUY?1:-1; ktr_records[n].opened=time; ktr_records[n].executed=time;
      KTRMeta meta;
      bool known=KTRParse(HistoryDealGetString(d,DEAL_COMMENT),meta);
      if(!known) known=KTRParse(HistoryOrderGetString(ktr_records[n].order,ORDER_COMMENT),meta);
      ktr_records[n].known=known; if(known) ktr_records[n].meta=meta;
   }
   ktr_history_time=TimeCurrent(); ktr_dirty=false; return true;
}
void KTRReconcileEpisodes(const bool closing)
{
   static string previous=""; static bool previous_closing=false;
   bool refreshed=ktr_dirty || TimeCurrent()-ktr_history_time>=Broker_History_Refresh_Seconds;
   if(refreshed) KTRRefreshRecords();
   KTRPositionView positions[]; string fingerprint="";
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(PositionGetTicket(i)==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol || (ulong)PositionGetInteger(POSITION_MAGIC)!=Magic_Number) continue;
      int n=ArraySize(positions); ArrayResize(positions,n+1);
      positions[n].pid=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      positions[n].dir=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      positions[n].volume=PositionGetDouble(POSITION_VOLUME);
      fingerprint+=(string)positions[n].pid+":"+DoubleToString(positions[n].volume,8)+";";
   }
   if(!refreshed && fingerprint==previous && previous_closing==closing) return;
   previous=fingerprint; previous_closing=closing;
   // Scan broker history only on transactions/refresh, not on every price tick.
   // Cached records are still reconciled against current position identifiers/volumes.
   KTRRecoverEpisode(1,ktr_records,positions,ktr_history_ok,closing,ktr_episode[0]);
   KTRRecoverEpisode(-1,ktr_records,positions,ktr_history_ok,closing,ktr_episode[1]);
}
bool KTRSeen(const int dir,const datetime event,const int tf)
{
   for(int i=0;i<ArraySize(ktr_records);i++)
      if(ktr_records[i].known && ktr_records[i].dir==dir && ktr_records[i].meta.event==event && ktr_records[i].meta.tf==tf) return true;
   // Rejected/canceled orders also consume an event after restart where comments survive.
   for(int i=HistoryOrdersTotal()-1;i>=0;i--)
   {
      ulong o=HistoryOrderGetTicket(i); if((ulong)HistoryOrderGetInteger(o,ORDER_MAGIC)!=Magic_Number || HistoryOrderGetString(o,ORDER_SYMBOL)!=_Symbol) continue;
      KTRMeta m; if(!KTRParse(HistoryOrderGetString(o,ORDER_COMMENT),m)) continue;
      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)HistoryOrderGetInteger(o,ORDER_TYPE);
      if((type==ORDER_TYPE_BUY?1:-1)==dir && m.event==event && m.tf==tf) return true;
   }
   return false;
}
bool KTRFilling(const string symbol,ENUM_ORDER_TYPE_FILLING &f,const bool entry)
{
   long flags=SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
   if((flags&SYMBOL_FILLING_FOK)!=0) { f=ORDER_FILLING_FOK; return true; }
   if((flags&SYMBOL_FILLING_IOC)!=0) { f=ORDER_FILLING_IOC; return true; }
   if(!entry && SymbolInfoInteger(symbol,SYMBOL_TRADE_EXEMODE)!=SYMBOL_TRADE_EXECUTION_MARKET) { f=ORDER_FILLING_RETURN; return true; }
   return false; // no unbounded RETURN entry remainder
}
bool KTRCancel(const ulong ticket)
{
   static ulong tickets[]; static datetime attempts[];
   int slot=-1,n=ArraySize(tickets);
   for(int i=0;i<n;i++) if(tickets[i]==ticket) { slot=i; break; }
   datetime now=TimeTradeServer()>0?TimeTradeServer():TimeCurrent();
   if(slot>=0 && now-attempts[slot]<3) return false;
   if(slot<0)
   {
      if(n>=256) { for(int i=1;i<n;i++) { tickets[i-1]=tickets[i]; attempts[i-1]=attempts[i]; } n--; }
      slot=n; ArrayResize(tickets,n+1); ArrayResize(attempts,n+1); tickets[slot]=ticket;
   }
   attempts[slot]=now;
   MqlTradeRequest q={}; MqlTradeResult r={}; q.action=TRADE_ACTION_REMOVE; q.order=ticket;
   return OrderSend(q,r) && r.retcode==TRADE_RETCODE_DONE;
}
bool KTRIsClosingOrder(const ulong ticket)
{
   if(!OrderSelect(ticket)) return false;
   string comment=OrderGetString(ORDER_COMMENT);
   if(StringFind(comment,"KTR!daily")==0 || StringFind(comment,"KTR!reversal")==0) return true;
   ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   if(type==ORDER_TYPE_CLOSE_BY) return true;
   ulong pid=(ulong)OrderGetInteger(ORDER_POSITION_ID);
   if(pid==0) return false;
   for(int p=PositionsTotal()-1;p>=0;p--)
   {
      if(PositionGetTicket(p)==0 || (ulong)PositionGetInteger(POSITION_IDENTIFIER)!=pid) continue;
      return (type==ORDER_TYPE_SELL && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) ||
             (type==ORDER_TYPE_BUY && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL);
   }
   return false;
}
void KTRReconcileIntents()
{
   for(int j=0;j<2;j++)
   {
      if(!ktr_intent[j].busy) continue;
      if(ktr_intent[j].order==0)
      {
         for(int i=HistoryOrdersTotal()-1;i>=0;i--)
         {
            ulong o=HistoryOrderGetTicket(i);
            if((ulong)HistoryOrderGetInteger(o,ORDER_MAGIC)==Magic_Number && HistoryOrderGetString(o,ORDER_SYMBOL)==_Symbol &&
               HistoryOrderGetString(o,ORDER_COMMENT)==ktr_intent[j].comment &&
               HistoryOrderGetInteger(o,ORDER_TIME_SETUP)>=ktr_intent[j].sent-2) { ktr_intent[j].order=o; break; }
         }
      }
      ulong o=ktr_intent[j].order;
      if(o!=0 && OrderSelect(o)) { KTRCancel(o); continue; }
      if(o!=0)
      {
         ENUM_ORDER_STATE state=(ENUM_ORDER_STATE)HistoryOrderGetInteger(o,ORDER_STATE);
         if(state==ORDER_STATE_FILLED || state==ORDER_STATE_CANCELED || state==ORDER_STATE_REJECTED || state==ORDER_STATE_EXPIRED)
         { ktr_intent[j].busy=false; ktr_dirty=true; }
      }
   }
   // Recover outstanding KTR requests after attachment. Cancel rather than duplicate.
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong o=OrderGetTicket(i);
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=Magic_Number || OrderGetString(ORDER_SYMBOL)!=_Symbol || KTRIsClosingOrder(o)) continue;
      int j=OrderGetInteger(ORDER_TYPE)==ORDER_TYPE_BUY?0:1;
      ktr_intent[j].busy=true; ktr_intent[j].order=o; KTRCancel(o);
   }
}
bool KTRHasManagedPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(PositionGetTicket(i)==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==Magic_Number) return true;
   }
   return false;
}
bool KTRAnyManagedOrder()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   { if(OrderGetTicket(i)!=0 && (ulong)OrderGetInteger(ORDER_MAGIC)==Magic_Number && OrderGetString(ORDER_SYMBOL)==_Symbol) return true; }
   return false;
}
datetime ktr_close_retry=0;
void KTRCloseAll(const bool account_wide)
{
   if(TimeCurrent()-ktr_close_retry<3) return; ktr_close_retry=TimeCurrent();
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong o=OrderGetTicket(i);
      if((account_wide || ((ulong)OrderGetInteger(ORDER_MAGIC)==Magic_Number && OrderGetString(ORDER_SYMBOL)==_Symbol)) && !KTRIsClosingOrder(o)) KTRCancel(o);
   }
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
      string symbol=PositionGetString(POSITION_SYMBOL);
      if(!account_wide && (symbol!=_Symbol || (ulong)PositionGetInteger(POSITION_MAGIC)!=Magic_Number)) continue;
      ulong pid=(ulong)PositionGetInteger(POSITION_IDENTIFIER); bool outstanding=false;
      for(int o=OrdersTotal()-1;o>=0;o--)
         if(OrderGetTicket(o)>0 && (ulong)OrderGetInteger(ORDER_POSITION_ID)==pid) outstanding=true;
      if(outstanding) continue;
      // Order selection doesn't change position selection; reselect defensively.
      if(!PositionSelectByTicket(ticket)) continue;
      MqlTick tick; if(!SymbolInfoTick(symbol,tick)) continue;
      MqlTradeRequest q={}; MqlTradeResult result={};
      q.action=TRADE_ACTION_DEAL; q.position=ticket; q.symbol=symbol; q.magic=Magic_Number;
      q.type=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
      q.volume=PositionGetDouble(POSITION_VOLUME); q.price=q.type==ORDER_TYPE_BUY?tick.ask:tick.bid;
      q.deviation=Max_Deviation_Points; q.comment=account_wide?"KTR!daily":"KTR!reversal";
      if(!KTRFilling(symbol,q.type_filling,false)) continue;
      if(!OrderSend(q,result) || (result.retcode!=TRADE_RETCODE_DONE && result.retcode!=TRADE_RETCODE_DONE_PARTIAL))
         PrintFormat("[KTR] Close unresolved %I64u retcode=%u; reconciliation will retry",ticket,result.retcode);
   }
   ktr_dirty=true;
}
#endif
