#ifndef KTR_EXECUTION_MQH
#define KTR_EXECUTION_MQH
int ktr_stop_atr=INVALID_HANDLE,ktr_fractals=INVALID_HANDLE;
KTRZigState ktr_zig_state;
KTRSwing ktr_frozen_swings[];
datetime ktr_zig_processed=0;
bool KTRUpdateZig(KTRMarket &m)
{
   int start=MathMax(52,m.Last()-Stop_History_Bars+1);
   if(ktr_zig_processed==0) KTRZigInit(ktr_zig_state,ZigZag_Depth);
   else
   {
      if(m.bars[52].time>ktr_zig_processed) return false; // missing causal replay interval
      start=52; // process every missed bar, even when more than Stop_History_Bars elapsed
   }
   for(int i=start;i<=m.Last();i++)
   {
      if(m.bars[i].time<=ktr_zig_processed) continue;
      KTRSwing swing;
      if(KTRZigStep(ktr_zig_state,m.bars[i].high,m.bars[i].low,m.bars[i].time,
         ZigZag_Depth,ZigZag_Backstep,ZigZag_Deviation*_Point,swing))
      {
         // Confirmed only at the next candle's opening, not its intrabar pivot time.
         swing.confirmed_at=i<m.Last()?m.bars[i+1].time:iTime(_Symbol,_Period,0);
         int n=ArraySize(ktr_frozen_swings); ArrayResize(ktr_frozen_swings,n+1); ktr_frozen_swings[n]=swing;
      }
      ktr_zig_processed=m.bars[i].time;
   }
   int keep=0;
   for(int i=0;i<ArraySize(ktr_frozen_swings);i++)
      if(iBarShift(_Symbol,_Period,ktr_frozen_swings[i].pivot_time,false)<=Stop_History_Bars)
         ktr_frozen_swings[keep++]=ktr_frozen_swings[i];
   ArrayResize(ktr_frozen_swings,keep);
   return true;
}
struct KTRPlan { MqlTradeRequest request; double loss; double margin; double budget; int dir; };
bool KTRStop(KTRMarket &m,const int dir,const double price,double &stop)
{
   int end=m.Last(); double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double av[]; if(CopyBuffer(ktr_stop_atr,0,1,1,av)!=1 || av[0]<=0) return false;
   stop=0;
   if(SL_Method==SL_FIXED_DISTANCE) stop=price-dir*Fixed_SL_Distance_Ticks*tick;
   if(SL_Method==SL_FRACTAL)
   {
      double values[]; int count=MathMin(Stop_History_Bars,ArraySize(m.bars)-2);
      if(CopyBuffer(ktr_fractals,dir>0?1:0,3,count,values)!=count) return false;
      for(int i=count-1;i>=0;i--)
      {
         if(values[i]<=0 || values[i]==EMPTY_VALUE || !MathIsValidNumber(values[i])) continue;
         if(dir*(price-values[i])<Fractal_Min_Distance_ATR*av[0]) continue;
         stop=values[i]-dir*Fractal_SL_Buffer_Ticks*tick; break;
      }
   }
   if(SL_Method==SL_ZIGZAG)
   {
      if(!KTRUpdateZig(m)) return false;
      for(int i=ArraySize(ktr_frozen_swings)-1;i>=0;i--)
      {
         if(ktr_frozen_swings[i].kind!=dir || dir*(price-ktr_frozen_swings[i].price)<=0) continue;
         stop=ktr_frozen_swings[i].price-dir*ZigZag_SL_Buffer_Ticks*tick; break;
      }
   }
   stop=NormalizeDouble(KTRRoundStop(stop,tick,dir),_Digits);
   if(stop<=0 || dir*(price-stop)<=0) return false;
   MqlTick quote; if(!SymbolInfoTick(_Symbol,quote)) return false;
   double distance=MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point;
   return dir>0?quote.bid-stop>distance:stop-quote.ask>distance;
}
double KTRAdditionalRisk(KTRMarket &m,const int entry_index)
{
   double fallback=KTRReducedRisk(First_Entry_Risk_Percent,Additional_Risk_Reduction_Percent,entry_index);
   if(Additional_Risk_Method==ADD_RISK_SAME) return First_Entry_Risk_Percent;
   if(Additional_Risk_Method==ADD_RISK_FIXED_REDUCTION) return fallback;
   int durations[],last=0,start=-1,age=0;
   for(int i=MathMax(52,m.Last()-Trend_End_History_Bars+1);i<=m.Last();i++)
   {
      int dir=KTRSign(m.ssa[i],m.ssb[i]); if(dir==0) continue;
      if(last==0) { last=dir; continue; } // exclude left-censored initial trend
      if(dir!=last)
      {
         if(start>=0) { int n=ArraySize(durations); ArrayResize(durations,n+1); durations[n]=i-start; }
         start=i; last=dir;
      }
   }
   if(start<0) { Print("[KTR] Trend age left-censored; fixed reduction fallback"); return fallback; }
   age=m.Last()-start;
   int eligible=0; double probability=KTREndProbability(durations,age,Trend_End_Horizon_Bars,eligible);
   if(eligible<Trend_End_Min_Samples) { PrintFormat("[KTR] Trend-end fallback: %d eligible completed trends",eligible); return fallback; }
   return First_Entry_Risk_Percent*(1-MathMax(0,MathMin(1,probability)));
}
bool KTRTradingPermitted()
{
   return TerminalInfoInteger(TERMINAL_CONNECTED) && TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) &&
          MQLInfoInteger(MQL_TRADE_ALLOWED) && AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) && AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
}
bool KTRPrepare(KTRMarket &m,const int dir,const bool first,const datetime event,const int method,const int event_tf,KTRPlan &p)
{
   int j=KTRIndex(dir);
   if(ktr_daily_lock || ktr_liquidating || !KTRTradingPermitted() || ktr_episode[j].blocked || ktr_intent[j].busy) return false;
   if(Trade_Direction==TRADE_BUY_ONLY && dir<0) return false;
   if(Trade_Direction==TRADE_SELL_ONLY && dir>0) return false;
   if(first?ktr_episode[j].state!=IDLE:ktr_episode[j].state!=ACTIVE) return false;
   if(KTRSeen(dir,event,event_tf)) return false;
   if(!first)
   {
      datetime last=ktr_episode[j].last_add;
      // A newly created episode never receives an addition in its first signal bar.
      int born=iBarShift(_Symbol,_Period,ktr_episode[j].opened,false);
      if(born<=0) return false;
      if(last>0 && iBarShift(_Symbol,_Period,last,false)<Additional_Entry_Cooldown_Main_Bars) return false;
      if(event<=ktr_episode[j].opened && event_tf==PeriodSeconds(_Period)) return false;
   }
   MqlTick quote; if(!SymbolInfoTick(_Symbol,quote) || quote.ask<=0 || quote.bid<=0) return false;
   long mode=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE),flags=SymbolInfoInteger(_Symbol,SYMBOL_ORDER_MODE);
   if(mode==SYMBOL_TRADE_MODE_DISABLED || mode==SYMBOL_TRADE_MODE_CLOSEONLY ||
      (dir>0 && mode==SYMBOL_TRADE_MODE_SHORTONLY) || (dir<0 && mode==SYMBOL_TRADE_MODE_LONGONLY) ||
      (flags&SYMBOL_ORDER_MARKET)==0 || (flags&SYMBOL_ORDER_SL)==0) return false;
   double price=dir>0?quote.ask:quote.bid,stop=0;
   if(!KTRStop(m,dir,price,stop)) { Print("[KTR] Selected stop unavailable/invalid; signal consumed"); return false; }
   double risk_pct=first?First_Entry_Risk_Percent:KTRAdditionalRisk(m,ktr_episode[j].entries+1);
   double budget=AccountInfoDouble(ACCOUNT_EQUITY)*risk_pct/100.0;
   double worst=price+dir*Max_Deviation_Points*_Point,unit=0;
   ENUM_ORDER_TYPE type=dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!OrderCalcProfit(type,_Symbol,1.0,worst,stop,unit) || unit>=0) return false;
   double loss_per_lot=-unit+ktr_commission;
   double volume=KTRFloorVolume(budget,loss_per_lot,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),
                               SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX));
   if(volume<=0) return false;
   double limit=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_LIMIT),used=0;
   if(limit>0)
   {
      for(int p=PositionsTotal()-1;p>=0;p--)
      {
         if(PositionGetTicket(p)==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
         if((PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1)==dir) used+=PositionGetDouble(POSITION_VOLUME);
      }
      if(used+volume>limit+1e-10) return false;
   }
   ZeroMemory(p); p.dir=dir; p.budget=budget; p.loss=volume*loss_per_lot;
   p.request.action=TRADE_ACTION_DEAL; p.request.magic=Magic_Number; p.request.symbol=_Symbol;
   p.request.type=type; p.request.price=price; p.request.sl=stop; p.request.volume=volume; p.request.deviation=Max_Deviation_Points;
   if(!KTRFilling(_Symbol,p.request.type_filling,true)) return false;
   KTRMeta meta; meta.episode=first?(long)TimeCurrent():ktr_episode[j].id;
   meta.first=first; meta.event=event; meta.method=method; meta.tf=event_tf;
   p.request.comment=KTRComment(meta);
   if(StringLen(p.request.comment)>31) return false; // no unsafe truncation
   MqlTradeCheckResult check={};
   if(!OrderCalcMargin(type,_Symbol,volume,price,p.margin) || !OrderCheck(p.request,check) || (check.retcode!=0 && check.retcode!=TRADE_RETCODE_DONE))
   { PrintFormat("[KTR] Preflight rejected: %u %s",check.retcode,check.comment); return false; }
   return true;
}
string KTRMethodNames(const int mask)
{
   string names="";
   if((mask&1)!=0) names+="TrendStart ";
   if((mask&2)!=0) names+="Tenkan/SSA ";
   if((mask&4)!=0) names+="Kijun/SSA ";
   if((mask&8)!=0) names+="LowerTF ";
   if((mask&16)!=0) names+="KijunPullback ";
   if((mask&32)!=0) names+="TKCross ";
   if((mask&64)!=0) names+="FlatSSB ";
   if((mask&128)!=0) names+="KijunRejection ";
   return names;
}
bool KTRSend(KTRPlan &p)
{
   int j=KTRIndex(p.dir); MqlTradeResult result={};
   ktr_intent[j].busy=true; ktr_intent[j].uncertain=true; ktr_intent[j].order=0;
   ktr_intent[j].comment=p.request.comment; ktr_intent[j].sent=TimeCurrent();
   bool sent=OrderSend(p.request,result); ktr_intent[j].order=result.order;
   if(result.order==0 && result.deal!=0)
      ktr_intent[j].order=(ulong)HistoryDealGetInteger(result.deal,DEAL_ORDER);
   bool accepted=result.retcode==TRADE_RETCODE_DONE || result.retcode==TRADE_RETCODE_DONE_PARTIAL || result.retcode==TRADE_RETCODE_PLACED;
   bool uncertain=result.retcode==TRADE_RETCODE_TIMEOUT || result.retcode==TRADE_RETCODE_CONNECTION || result.retcode==TRADE_RETCODE_ERROR || result.retcode==0;
   ktr_intent[j].uncertain=uncertain;
   if(!accepted && !uncertain) ktr_intent[j].busy=false;
   PrintFormat("[KTR] Submit %s sent=%s retcode=%u order=%I64u deal=%I64u budget=%.2f reserved=%.2f comment=%s",
      p.dir>0?"BUY":"SELL",sent?"true":"false",result.retcode,result.order,result.deal,p.budget,p.loss,p.request.comment);
   KTRMeta meta; if(KTRParse(p.request.comment,meta))
      PrintFormat("[KTR] episode=%I64d role=%s event=%s components=%s",meta.episode,meta.first?"FIRST":"ADDITION",TimeToString(meta.event),KTRMethodNames(meta.method));
   ktr_dirty=true; return accepted;
}
// A joint preflight never assigns a directional priority. Sequential execution cannot be atomic.
void KTRSubmitCandidates(KTRMarket &m,KTRMarket &higher,const bool buy,const bool sell,const bool first,
                        const datetime buy_event,const datetime sell_event,const int buy_method,const int sell_method,const int tf)
{
   if(ktr_intent[0].busy || ktr_intent[1].busy || ktr_daily_lock || ktr_liquidating) return;
   bool b=buy && (Trade_Direction!=TRADE_SELL_ONLY),s=sell && (Trade_Direction!=TRADE_BUY_ONLY);
   // Non-IDLE directions are not first-entry candidates; the other direction can still start.
   if(first) { b=b && ktr_episode[0].state==IDLE; s=s && ktr_episode[1].state==IDLE; }
   if(!b && !s) return;
   bool joint=first && b && s;
   KTRPlan bp,sp;
   bool bok=b && KTRConfirm(m,higher,1,first) && KTRPrepare(m,1,first,buy_event,buy_method,tf,bp);
   bool sok=s && KTRConfirm(m,higher,-1,first) && KTRPrepare(m,-1,first,sell_event,sell_method,tf,sp);
   if(joint && (!bok || !sok)) { Print("[KTR] Joint first entries rejected: both must qualify"); return; }
   // No capacity decision exists when signals failed filters/preparation. In
   // particular a zero first-day baseline must not manufacture a rejected trade.
   if(!bok && !sok) return;
   double open_loss=0;
   if(!KTROpenLoss(open_loss))
   { Print("[KTR] Entry blocked: existing account exposure cannot be assessed (pending order, missing/invalid SL, quote or profit calculation)"); return; }
   double proposed=(bok?bp.loss:0)+(sok?sp.loss:0),margin=(bok?bp.margin:0)+(sok?sp.margin:0);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY),free_margin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(ktr_day_balance<=0)
   {
      PrintFormat("[KTR] Entry blocked: nonpositive daily opening balance; B_day=%.2f equity=%.2f currency=%s baseline_estimated=%s. Initial funding booked during the first tester/account day can reconstruct B_day=0; no positive midnight baseline is assumed",
         ktr_day_balance,equity,AccountInfoString(ACCOUNT_CURRENCY),ktr_baseline_estimated?"true":"false");
      return;
   }
   if(!KTRRiskFits(ktr_day_balance,equity,open_loss,proposed,Max_Daily_Risk_Percent))
   {
      double worst=equity-open_loss-proposed,floor=ktr_day_balance*(1-Max_Daily_Risk_Percent/100.0);
      PrintFormat("[KTR] Daily-risk rejection: B_day=%.2f equity=%.2f open_SL_loss=%.2f proposed_loss=%.2f projected_worst_equity=%.2f required_equity=%.2f projected_risk=%.4f%% limit=%.4f%% currency=%s baseline_estimated=%s",
         ktr_day_balance,equity,open_loss,proposed,worst,floor,
         MathMax(0,ktr_day_balance-worst)/ktr_day_balance*100,Max_Daily_Risk_Percent,
         AccountInfoString(ACCOUNT_CURRENCY),ktr_baseline_estimated?"true":"false");
      return;
   }
   if(margin>free_margin)
   {
      PrintFormat("[KTR] Margin rejection: required_margin=%.2f free_margin=%.2f buy_volume=%.8f sell_volume=%.8f currency=%s",
         margin,free_margin,bok?bp.request.volume:0,sok?sp.request.volume:0,AccountInfoString(ACCOUNT_CURRENCY));
      return;
   }
   bool filled_buy=false,filled_sell=false;
   if(bok) filled_buy=KTRSend(bp);
   if(sok)
   {
      // Check actual equity and exposure again after the first request. Reserve its full
      // planned risk when broker state has not yet exposed the position.
      double refreshed=0;
      bool risk_ok=KTROpenLoss(refreshed);
      double reservation=0;
      if(bok && ktr_intent[0].busy)
      {
         bool visible=false;
         for(int i=PositionsTotal()-1;i>=0;i--)
         { if(PositionGetTicket(i)>0 && PositionGetString(POSITION_COMMENT)==bp.request.comment && (ulong)PositionGetInteger(POSITION_MAGIC)==Magic_Number) visible=true; }
         if(!visible) reservation=bp.loss;
      }
      if(risk_ok && !ktr_daily_lock && KTRRiskFits(ktr_day_balance,AccountInfoDouble(ACCOUNT_EQUITY),refreshed,sp.loss+reservation,Max_Daily_Risk_Percent)) filled_sell=KTRSend(sp);
   }
   if(joint && filled_buy!=filled_sell) Print("[KTR] NON-ATOMIC joint submission: only one request accepted; broker reconciliation remains authoritative");
   KTRRefreshRecords(); KTRReconcileIntents(); KTRReconcileEpisodes(false);
}
#endif
