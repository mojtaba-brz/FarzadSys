// Kumo Trend Rider v1.01 -- independent hedging-account EA.
#property strict
#property version "1.01"
#property description "Closed-candle projected Kumo / shape episodes with account-wide daily protection."
#include "Include/KTR/Core.mqh"
#include "Include/KTR/Inputs.mqh"
#include "Include/KTR/Market.mqh"
#include "Include/KTR/Broker.mqh"
#include "Include/KTR/Account.mqh"
#include "Include/KTR/Execution.mqh"
KTRMarket ktr_main,ktr_lower,ktr_higher;
bool ktr_lower_enabled=false,ktr_higher_enabled=false,ktr_bootstrapped=false,ktr_reversing=false;
datetime ktr_main_bar=0,ktr_lower_bar=0,ktr_higher_bar=0;
int ktr_pending_direction=0;
datetime ktr_pending_bar=0,ktr_pending_event=0;
int ktr_previous_main_trigger[2];
string ktr_last_warning="";
void KTRWarn(const string text)
{ if(ktr_last_warning!=text) { Print("[KTR] ",text); ktr_last_warning=text; } }
bool KTRValidNumber(const double value,const double minimum,const double maximum)
{ return MathIsValidNumber(value) && value>=minimum && value<=maximum; }
bool KTRValidate()
{
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   { Print("[KTR] Hedging accounts only"); return false; }
   if(Magic_Number==0 || Max_Deviation_Points>100000 || Trade_Direction<TRADE_BUY_ONLY || Trade_Direction>TRADE_BOTH ||
      First_Entry_Method<FIRST_TREND_START || First_Entry_Method>FIRST_EITHER || SL_Method<SL_FRACTAL || SL_Method>SL_FIXED_DISTANCE ||
      Additional_Risk_Method<ADD_RISK_SAME || Additional_Risk_Method>ADD_RISK_TREND_END_PROBABILITY) return false;
   if(Shape_Window_Bars<3 || Shape_Window_Bars>500 || Shape_Max_Lag_Bars<0 || Shape_Max_Lag_Bars>100 ||
      Shape_Pivot_Left_Bars<1 || Shape_Pivot_Left_Bars>100 || Shape_Pivot_Right_Bars<1 || Shape_Pivot_Right_Bars>100 ||
      Additional_Entry_Cooldown_Main_Bars<0 || Additional_Entry_Cooldown_Main_Bars>100000 ||
      Max_Additional_Entries_Per_Episode<0 || Max_Additional_Entries_Per_Episode>10000 ||
      Flat_SSB_Min_Bars<2 || Flat_SSB_Min_Bars>500 || Flat_SSB_Max_Age_Bars<Flat_SSB_Min_Bars || Flat_SSB_Max_Age_Bars>10000 ||
      SR_Min_Touches<2 || SR_Min_Touches>100 || SR_Min_Touch_Separation<1 || SR_Min_Touch_Separation>1000 ||
      SR_Lookback_Bars<10 || SR_Lookback_Bars>10000 ||
      Fractal_SL_Buffer_Ticks<0 || Fractal_SL_Buffer_Ticks>100000 || ZigZag_SL_Buffer_Ticks<0 || ZigZag_SL_Buffer_Ticks>100000 ||
      ZigZag_Depth<2 || ZigZag_Depth>500 || ZigZag_Backstep<1 || ZigZag_Backstep>=ZigZag_Depth ||
      Fixed_SL_Distance_Ticks<1 || Fixed_SL_Distance_Ticks>10000000 || ATR_Period<1 || ATR_Period>1000 ||
      Stop_History_Bars<MathMax(120,ZigZag_Depth*3) || Stop_History_Bars>100000 ||
      Trend_End_Horizon_Bars<1 || Trend_End_Horizon_Bars>10000 || Trend_End_Min_Samples<1 || Trend_End_Min_Samples>10000 ||
      Trend_End_History_Bars<120 || Trend_End_History_Bars>100000 ||
      Monitor_Corner<CORNER_LEFT_UPPER || Monitor_Corner>CORNER_RIGHT_LOWER || Monitor_X<0 || Monitor_Y<0 ||
      Monitor_X>10000 || Monitor_Y>10000 || Monitor_Font_Size<6 || Monitor_Font_Size>40 ||
      Equity_History_Days<1 || Equity_History_Days>3650 || Equity_Sample_Seconds<1 || Equity_Sample_Seconds>86400 ||
      Equity_Samples_Per_Timer<1 || Equity_Samples_Per_Timer>10 || Equity_Max_Samples<100 || Equity_Max_Samples>100000 ||
      Broker_History_Refresh_Seconds<1 || Broker_History_Refresh_Seconds>3600 || PeriodSeconds(ATR_Timeframe)<=0) return false;
   if(!KTRValidNumber(Shape_Min_Similarity,-1,1) || !KTRValidNumber(Shape_Min_Amplitude_ATR,0.000001,100) ||
      !KTRValidNumber(Shape_Plateau_Tolerance,0,100) || !KTRValidNumber(Kijun_Touch_ATR,0,100) ||
      !KTRValidNumber(Kijun_Rejection_Min_WickBody,0.01,1000) || !KTRValidNumber(Flat_SSB_Max_Variation_ATR,0,100) ||
      !KTRValidNumber(Flat_SSB_Touch_ATR,0,100) || !KTRValidNumber(SR_Tolerance_ATR,0,100) ||
      !KTRValidNumber(Cloud_Min_Thickness_ATR,0,100) || !KTRValidNumber(Chikou_Clearance_ATR,0,100) ||
      !KTRValidNumber(Fractal_Min_Distance_ATR,0,100) || !KTRValidNumber(ZigZag_Deviation,0.000001,1000000) ||
      !KTRValidNumber(First_Entry_Risk_Percent,0.000001,100) || !KTRValidNumber(Max_Daily_Risk_Percent,0.000001,99.99) ||
      !KTRValidNumber(Additional_Risk_Reduction_Percent,0,100) || !KTRValidNumber(Commission_Reserve_Per_Lot,0,1e9) ||
      !KTRValidNumber(Initial_Deposit_Override,0,1e15)) return false;
   return true;
}
int KTRHistoryNeeded()
{
   int needed=MathMax(Trend_End_History_Bars+100,MathMax(Stop_History_Bars+100,SR_Lookback_Bars+100));
   needed=MathMax(needed,Flat_SSB_Max_Age_Bars+Flat_SSB_Min_Bars+100);
   for(int j=0;j<2;j++) if(ktr_episode[j].opened>0)
      needed=MathMax(needed,iBarShift(_Symbol,_Period,ktr_episode[j].opened,false)+100);
   return MathMin(200000,needed);
}
bool KTROfflineReversal()
{
   bool found=false;
   for(int j=0;j<2;j++)
   {
      if(ktr_episode[j].count==0) continue;
      if(ktr_episode[j].opened==0) { ktr_episode[j].blocked=true; continue; }
      bool covered=false;
      if(ktr_main.ReversalAfter(ktr_episode[j].opened,covered)) found=true;
      if(!covered) { ktr_episode[j].blocked=true; KTRWarn("Insufficient cloud history to assess owned episode; new entries blocked"); }
   }
   return found;
}
bool KTRBootstrap()
{
   KTRReconcileEpisodes(ktr_reversing);
   if(!ktr_main.Load(KTRHistoryNeeded())) return false;
   ktr_main_bar=iTime(_Symbol,_Period,0); KTRSeedShapeHistory(ktr_main);
   ktr_previous_main_trigger[0]=KTRAdditionalMethods(ktr_main,1);
   ktr_previous_main_trigger[1]=KTRAdditionalMethods(ktr_main,-1);
   if(ktr_lower_enabled) { ktr_lower.Load(MathMax(500,Shape_Window_Bars+Shape_Max_Lag_Bars+200)); KTRSeedShapeHistory(ktr_lower); ktr_lower_bar=iTime(_Symbol,Lower_Entry_Timeframe,0); }
   if(ktr_higher_enabled) { ktr_higher.Load(200); ktr_higher_bar=iTime(_Symbol,Higher_Confirmation_Timeframe,0); }
   // Bootstrap never emits historical entries. Offline reversals still require exit.
   if(KTROfflineReversal()) { ktr_reversing=true; ktr_pending_direction=0; KTRCloseAll(false); }
   ktr_bootstrapped=true; Print("[KTR] Closed history verified; broker recovery complete; waiting for fresh signals"); return true;
}
void KTRFinishReversal()
{
   if(!ktr_reversing && ktr_pending_direction==0) return;
   if(ktr_pending_direction!=0 && ktr_pending_bar!=iTime(_Symbol,_Period,0))
   {
      PrintFormat("[KTR] FIRST trend event expired: direction=%s event=%s; closing/session wait exceeded its main signal bar",
         ktr_pending_direction>0?"BUY":"SELL",TimeToString(ktr_pending_event));
      ktr_pending_direction=0;
   }
   if(ktr_reversing)
   {
      KTRCloseAll(false); KTRReconcileIntents();
      if(KTRHasManagedPositions() || KTRAnyManagedOrder() || ktr_intent[0].busy || ktr_intent[1].busy) return;
      ktr_reversing=false; KTRReconcileEpisodes(false);
   }
   int dir=ktr_pending_direction;
   if(dir==0) return;
   if(ktr_daily_lock || ktr_liquidating) { ktr_pending_direction=0; Print("[KTR] FIRST trend event blocked by daily liquidation lock"); return; }
   if((dir>0 && Trade_Direction==TRADE_SELL_ONLY) || (dir<0 && Trade_Direction==TRADE_BUY_ONLY))
   { ktr_pending_direction=0; Print("[KTR] FIRST trend direction skipped by Trade_Direction setting"); return; }
   bool session_known=false;
   if(!KTRTradeSessionOpen(_Symbol,session_known))
   { KTRWarn("FIRST trend event waiting for broker trading session within its current main signal bar"); return; }
   // Not a rejected order queue: no submission has occurred while the session is closed.
   ktr_pending_direction=0;
   KTRSubmitCandidates(ktr_main,ktr_higher,dir>0,dir<0,true,ktr_pending_event,ktr_pending_event,1,1,PeriodSeconds(_Period));
}
void KTRProcessSignals()
{
   if(!ktr_bootstrapped) { KTRBootstrap(); return; }
   KTRFinishReversal();
   if(ktr_reversing || ktr_liquidating || ktr_daily_lock) return;
   datetime main_bar=iTime(_Symbol,_Period,0),lower_bar=ktr_lower_enabled?iTime(_Symbol,Lower_Entry_Timeframe,0):0;
   bool new_main=main_bar>ktr_main_bar,new_lower=ktr_lower_enabled && lower_bar>ktr_lower_bar;
   if(!new_main && !new_lower) return;
   int main_buy_mask=0,main_sell_mask=0;
   if(new_main)
   {
      if(!ktr_main.Load(KTRHistoryNeeded())) { KTRWarn("Main closed indicators unavailable; awaiting synchronized data"); return; }
      ktr_main_bar=main_bar;
      main_buy_mask=KTRFreshAdditionalMask(KTRAdditionalMethods(ktr_main,1),ktr_previous_main_trigger[0],Additional_Require_Fresh_Main_Trigger);
      main_sell_mask=KTRFreshAdditionalMask(KTRAdditionalMethods(ktr_main,-1),ktr_previous_main_trigger[1],Additional_Require_Fresh_Main_Trigger);
   }
   if(ktr_higher_enabled && (iTime(_Symbol,Higher_Confirmation_Timeframe,0)!=ktr_higher_bar || !ktr_higher.ready))
   { if(ktr_higher.Load(200)) ktr_higher_bar=iTime(_Symbol,Higher_Confirmation_Timeframe,0); else ktr_higher.ready=false; }
   // Check every reversal since the original execution, including multiple missed flips.
   bool offline_reversal=KTROfflineReversal();
   bool reversal=new_main && (ktr_main.LatestReversal()!=0 || offline_reversal);
   if(reversal)
   {
      int at=ktr_main.Last();
      PrintFormat("[KTR] Projected-cloud reversal: direction=%s calculation=%s confirmed_bar=%s SSA=%.*f SSB=%.*f offline_exit=%s",
         ktr_main.Direction()>0?"BUY":ktr_main.Direction()<0?"SELL":"NEUTRAL",TimeToString(ktr_main.bars[at].time),TimeToString(main_bar),_Digits,ktr_main.ssa[at],_Digits,ktr_main.ssb[at],offline_reversal?"true":"false");
      ktr_reversing=true; ktr_pending_direction=0;
      KTRSignal consumed; KTRFirstSignals(ktr_main,consumed);
      if(ktr_main.LatestReversal()!=0 && First_Entry_Method!=FIRST_SHAPE_SIMILARITY)
      { ktr_pending_direction=ktr_main.LatestReversal(); ktr_pending_event=ktr_main.bars[ktr_main.Last()].time; ktr_pending_bar=main_bar; }
      KTRReconcileEpisodes(true); KTRFinishReversal();
      // Consume the coincident lower event too; never turn it into a queued addition.
      if(new_lower) ktr_lower_bar=lower_bar;
      return;
   }
   // Capture active episodes BEFORE first entries; no addition from the creating event.
   long eligible_buy=ktr_episode[0].state==ACTIVE?ktr_episode[0].id:0;
   long eligible_sell=ktr_episode[1].state==ACTIVE?ktr_episode[1].id:0;
   if(new_main)
   {
      KTRSignal s; KTRFirstSignals(ktr_main,s);
      KTRSubmitCandidates(ktr_main,ktr_higher,s.buy,s.sell,true,s.buy_event,s.sell_event,s.buy_method,s.sell_method,PeriodSeconds(_Period));
   }
   int bm=0,sm=0; datetime be=0,se=0;
   if(new_main)
   {
      bm=main_buy_mask; sm=main_sell_mask;
      be=ktr_main.bars[ktr_main.Last()].time; se=be;
   }
   // Main-TF methods take precedence over lower-TF methods at a coincident decision.
   // One candidate per direction. Broker timestamp cooldown also deduplicates later calls.
   KTRSignal low; KTRClearSignal(low);
   if(new_lower)
   {
      ktr_lower_bar=lower_bar;
      if(ktr_lower.Load(MathMax(500,Shape_Window_Bars+Shape_Max_Lag_Bars+200))) KTRFirstSignals(ktr_lower,low);
      else KTRWarn("Lower-TF data unavailable; lower event skipped; main methods remain enabled");
      // Mixed-timeframe candidates are submitted separately below with their own IDs.
   }
   if(eligible_buy==0 || ktr_episode[0].id!=eligible_buy) bm=0;
   if(eligible_sell==0 || ktr_episode[1].id!=eligible_sell) sm=0;
   if(bm!=0 || sm!=0) KTRSubmitCandidates(ktr_main,ktr_higher,bm!=0,sm!=0,false,be,se,bm,sm,PeriodSeconds(_Period));
   bool lb=new_lower && low.buy && bm==0 && eligible_buy!=0 && ktr_episode[0].id==eligible_buy;
   bool ls=new_lower && low.sell && sm==0 && eligible_sell!=0 && ktr_episode[1].id==eligible_sell;
   if(lb || ls) KTRSubmitCandidates(ktr_main,ktr_higher,lb,ls,false,low.buy_event,low.sell_event,8|low.buy_method,8|low.sell_method,PeriodSeconds(Lower_Entry_Timeframe));
}
int OnInit()
{
   PrintFormat("[KTR] BUILD KTR-1.01-20261102-H1-DIAGNOSTICS | program=%s | symbol=%s | chart=%s",
      MQLInfoString(MQL_PROGRAM_PATH),_Symbol,EnumToString(_Period));
   if(!KTRValidate()) { Print("[KTR] Invalid numeric/enumerated inputs or account mode"); return INIT_PARAMETERS_INCORRECT; }
   PrintFormat("[KTR] Contract/sizing: currency=%s equity=%.2f first_risk_percent=%.4f first_budget=%.2f volume_min=%.8f volume_step=%.8f volume_max=%.8f tick_size=%.8f point=%.8f stop_method=%s stop_ATR_TF=%s fractal_min_ATR=%.4f",
      AccountInfoString(ACCOUNT_CURRENCY),AccountInfoDouble(ACCOUNT_EQUITY),First_Entry_Risk_Percent,
      AccountInfoDouble(ACCOUNT_EQUITY)*First_Entry_Risk_Percent/100.0,
      SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),
      SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),_Point,EnumToString(SL_Method),EnumToString(ATR_Timeframe),Fractal_Min_Distance_ATR);
   ktr_lower_enabled=Enable_LowerTF_Entry && PeriodSeconds(Lower_Entry_Timeframe)>0 && PeriodSeconds(Lower_Entry_Timeframe)<PeriodSeconds(_Period);
   if(Enable_LowerTF_Entry && !ktr_lower_enabled) Print("[KTR] Lower-TF method disabled: timeframe must be strictly below chart");
   ktr_higher_enabled=First_Confirm_HigherTF || Additional_Confirm_HigherTF;
   if(ktr_higher_enabled && PeriodSeconds(Higher_Confirmation_Timeframe)<=PeriodSeconds(_Period)) return INIT_PARAMETERS_INCORRECT;
   if(!ktr_main.Init(_Period)) return INIT_FAILED;
   if(ktr_lower_enabled && !ktr_lower.Init(Lower_Entry_Timeframe)) { ktr_lower_enabled=false; Print("[KTR] Lower-TF handle unavailable; method disabled"); }
   if(ktr_higher_enabled && !ktr_higher.Init(Higher_Confirmation_Timeframe)) return INIT_FAILED;
   ktr_stop_atr=iATR(_Symbol,ATR_Timeframe,ATR_Period); ktr_fractals=iFractals(_Symbol,_Period);
   if(ktr_stop_atr==INVALID_HANDLE || ktr_fractals==INVALID_HANDLE) return INIT_FAILED;
   ktr_panel_prefix="KTR."+(string)ChartID()+"."+(string)Magic_Number+".";
   Print("[KTR] Dedicated account: emergency limit closes ALL account positions and cancels ALL pending orders. One KTR instance per account required.");
   PrintFormat("[KTR] Entry policy: direction=%s first_method=%s max_additions=%d fresh_main_trigger=%s cooldown_full_main_bars=%d",
      EnumToString(Trade_Direction),EnumToString(First_Entry_Method),Max_Additional_Entries_Per_Episode,Additional_Require_Fresh_Main_Trigger?"true":"false",Additional_Entry_Cooldown_Main_Bars);
   KTRRefreshRecords(); KTRReconcileIntents(); KTRAccountUpdate(); KTRBootstrap();
   if(!EventSetTimer(1)) return INIT_FAILED;
   return INIT_SUCCEEDED;
}
void OnTick()
{
   KTRAccountUpdate(); KTRReconcileIntents(); KTRReconcileEpisodes(ktr_reversing || ktr_liquidating);
   if(!ktr_liquidating) KTRProcessSignals();
}
void OnTimer()
{
   KTRAccountUpdate(); KTRReconcileIntents(); KTRReconcileEpisodes(ktr_reversing || ktr_liquidating);
   if((ktr_reversing || ktr_pending_direction!=0) && !ktr_liquidating) KTRFinishReversal();
   if(!ktr_bootstrapped) KTRBootstrap();
   KTRHistoricalWork(); KTRPanel();
}
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   // Never infer episode state from callback ordering. Broker snapshots are authoritative.
   ktr_dirty=true;
   datetime server=TimeTradeServer()>0?TimeTradeServer():TimeCurrent();
   if(KTRMidnight(server)!=ktr_day) KTRAccountUpdate();
   else KTRFastEmergency(); // no full-history scan inside each trade callback
}
void OnDeinit(const int reason)
{
   EventKillTimer(); ktr_main.Release(); ktr_lower.Release(); ktr_higher.Release();
   if(ktr_stop_atr!=INVALID_HANDLE) IndicatorRelease(ktr_stop_atr);
   if(ktr_fractals!=INVALID_HANDLE) IndicatorRelease(ktr_fractals);
   if(ktr_panel_prefix!="") ObjectsDeleteAll(0,ktr_panel_prefix);
}
