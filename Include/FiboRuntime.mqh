#ifndef RPU_FIBO_RUNTIME
#define RPU_FIBO_RUNTIME
#include "FiboCore.mqh"
input group "Fibonacci Confirmation v2"
input ENUM_FIBO_MODE Fibo_Mode=FIB_OBSERVE_ONLY;
input ENUM_TIMEFRAMES Fibo_Timeframe=PERIOD_M15;
input int Pivot_Left_Bars=3;
input int Pivot_Right_Bars=3;
input double Min_Swing_ATR=1.5;
input int ATR_Period=14;
input int Swing_History_Bars=500;
input int Setup_Expiry_Bars=96;
input group "Fibonacci Appearance"
input bool Show_Pullback_Fibonacci=true;
input bool Show_Countertrend_Fibonacci=true;
input color Pullback_Fibonacci_Color=clrDodgerBlue;
input color Countertrend_Fibonacci_Color=clrOrange;
input bool Show_Fibonacci_Zones=true;
input color Pullback_Zone_Color=clrMidnightBlue;
input color Countertrend_Zone_Color=clrSaddleBrown;
// Development-only CSV diagnostics; deliberately absent from EA inputs.
// TODO: Remove observation CSV export once the EA is finalized. Recovery snapshots
// are independent safety state and must remain when debug export is removed.
const bool DEBUG_FIBO_CSV=true;
const string DEBUG_FIBO_CSV_PREFIX="RSI_Pull_Up_Fibo_Debug_";

FiboEngine fib;
bool PullbackConfirmed=false,CountertrendConfirmed=false,FiboConfirmed=true,FiboReady=false;
ENUM_FIBO_MODE ActiveFiboMode=FIB_OBSERVE_ONLY;
int fib_atr=INVALID_HANDLE, fib_csv=INVALID_HANDLE, projection_zone=0;
bool fib_initialized=false, fib_replaying=false, fib_persistence_ok=true;
datetime fib_bar=0, fib_retry=0;
double fib_price=0;
string fib_source="UNAVAILABLE",fib_file="",fib_config="",fib_run="",fib_problem="Starting";
string drawn_pullback="",drawn_countertrend="";
long signal_cycle=1, request_cycle=0;
bool observed_rsi=false;
struct FiboCloseCandidate { ulong position,order,deal; double price; long cycle; };
FiboCloseCandidate fib_closes[];

ENUM_TIMEFRAMES EffectiveFiboTF() { return Fibo_Timeframe==PERIOD_CURRENT?_Period:Fibo_Timeframe; }
string SetupState(const SETUP_STATE state)
{
   if(state==SETUP_ACTIVE) return "ACTIVE";
   if(state==SETUP_INVALIDATED) return "INVALIDATED";
   if(state==SETUP_EXPIRED) return "EXPIRED";
   return "NO SETUP";
}
string ModeName()
{
   string s=EnumToString(ActiveFiboMode); StringReplace(s,"FIB_",""); StringReplace(s,"_"," "); return s;
}
string SetupID(const FiboSetup &setup,const bool counter=false)
{
   if(setup.state==SETUP_NONE) return "";
   return (counter?"B:":"A:")+(string)(long)setup.a.time+":"+(string)(long)setup.b.time+":"+
      (counter?(string)(long)setup.c.time+":":"")+(string)(long)setup.activated;
}
string FNumber(const double value) { return DoubleToString(value,10); }
string Stamp(const datetime time) { return time>0?TimeToString(time,TIME_DATE|TIME_SECONDS):""; }
string CsvCell(string value)
{
   StringReplace(value,"\"","\"\""); return "\""+value+"\"";
}
void CsvAdd(string &row,const string value)
{
   if(row!="") row+=",";
   row+=CsvCell(value);
}
// Each outcome is a separate row linked by order/deal/position identifier. A decision
// row is never retrospectively overwritten with a fabricated trade outcome.
void Observe(const string event,const bool attempted=false,const ulong order=0,const ulong deal=0,
             const ulong position=0,const double fill=0,const uint retcode=0,const string note="",
             const bool has_net=false,const double net=0,const long event_cycle=-1)
{
   if(fib_replaying) return; // Historical reconstruction must never emit past signals/trades.
   bool actual_a=FiboReady && fib_price>0 && PullbackZone(fib.pullback,fib_price,TimeCurrent());
   int actual_zone=FiboReady && fib_price>0?CountertrendZone(fib.countertrend,fib_price,TimeCurrent()):0;
   bool actual_b=actual_zone!=0;
   Log("FIB "+event+" | "+ModeName()+" A="+(actual_a?"YES":"NO")+" B="+(actual_b?"YES":"NO")+" | "+note);
   if(fib_csv==INVALID_HANDLE) return;
   string row="";
   CsvAdd(row,fib_run); CsvAdd(row,Stamp(TimeCurrent())); CsvAdd(row,_Symbol); CsvAdd(row,EnumToString(_Period));
   CsvAdd(row,EnumToString(EffectiveFiboTF())); CsvAdd(row,event); CsvAdd(row,(string)(event_cycle>=0?event_cycle:signal_cycle)); CsvAdd(row,(string)(event_cycle>=0?event_cycle:request_cycle));
   CsvAdd(row,ready?"1":"0");
   for(int i=0;i<4;i++) CsvAdd(row,ready?FNumber(rsi[i]):"");
   for(int i=0;i<4;i++) CsvAdd(row,FNumber(RSILevel(i)));
   CsvAdd(row,FNumber(SelectedVolume())); CsvAdd(row,signal_state==ARMED?"ARMED":"CONSUMED");
   CsvAdd(row,fib_price>0?FNumber(fib_price):""); CsvAdd(row,fib_source);
   CsvAdd(row,SetupID(fib.pullback)); CsvAdd(row,SetupState(fib.pullback.state));
   CsvAdd(row,FNumber(fib.pullback.a.price)); CsvAdd(row,Stamp(fib.pullback.a.time)); CsvAdd(row,Stamp(fib.pullback.a.confirmed));
   CsvAdd(row,FNumber(fib.pullback.b.price)); CsvAdd(row,Stamp(fib.pullback.b.time)); CsvAdd(row,Stamp(fib.pullback.b.confirmed));
   CsvAdd(row,FNumber(fib.pullback.lower)); CsvAdd(row,FNumber(fib.pullback.upper)); CsvAdd(row,actual_a?"1":"0");
   CsvAdd(row,FNumber(fib.pullback.atr)); CsvAdd(row,Stamp(fib.pullback.atr_time));
   double ratios[3]={0.5,0.618,0.786};
   for(int i=0;i<3;i++) CsvAdd(row,fib_price>0 && fib.pullback.atr>0?FNumber((fib_price-Retracement(fib.pullback.a.price,fib.pullback.b.price,ratios[i]))/fib.pullback.atr):"");
   CsvAdd(row,SetupID(fib.countertrend,true)); CsvAdd(row,SetupState(fib.countertrend.state));
   CsvAdd(row,FNumber(fib.countertrend.a.price)); CsvAdd(row,Stamp(fib.countertrend.a.time)); CsvAdd(row,Stamp(fib.countertrend.a.confirmed));
   CsvAdd(row,FNumber(fib.countertrend.b.price)); CsvAdd(row,Stamp(fib.countertrend.b.time)); CsvAdd(row,Stamp(fib.countertrend.b.confirmed));
   CsvAdd(row,FNumber(fib.countertrend.c.price)); CsvAdd(row,Stamp(fib.countertrend.c.time)); CsvAdd(row,Stamp(fib.countertrend.c.confirmed));
   CsvAdd(row,FNumber(fib.countertrend.e127)); CsvAdd(row,FNumber(fib.countertrend.e161)); CsvAdd(row,FNumber(fib.countertrend.tolerance));
   CsvAdd(row,actual_b?"1":"0"); CsvAdd(row,(string)actual_zone);
   CsvAdd(row,FNumber(fib.countertrend.atr)); CsvAdd(row,Stamp(fib.countertrend.atr_time));
   CsvAdd(row,fib_price>0 && fib.countertrend.atr>0?FNumber((fib_price-fib.countertrend.e127)/fib.countertrend.atr):"");
   CsvAdd(row,fib_price>0 && fib.countertrend.atr>0?FNumber((fib_price-fib.countertrend.e161)/fib.countertrend.atr):"");
   CsvAdd(row,ModeName()); CsvAdd(row,FiboReady?"1":"0"); CsvAdd(row,FiboFilter(ActiveFiboMode,actual_a,actual_b)?"1":"0");
   CsvAdd(row,attempted?"1":"0"); CsvAdd(row,(string)order); CsvAdd(row,(string)deal); CsvAdd(row,(string)position);
   CsvAdd(row,fill>0?FNumber(fill):""); CsvAdd(row,(string)retcode); CsvAdd(row,has_net?FNumber(net):"");
   CsvAdd(row,currency); CsvAdd(row,note);
   if(FileWriteString(fib_csv,row+"\r\n")==0) Log("CSV write failed: "+IntegerToString(GetLastError()));
   FileFlush(fib_csv);
}
uint SnapshotDigest(const uchar &bytes[])
{
   uint hash=2166136261;
   for(int i=0;i<ArraySize(bytes);i++) hash=(hash^bytes[i])*16777619;
   return hash;
}
bool FiboSave()
{
   if(MQLInfoInteger(MQL_TESTER)) return true;
   // Stage and flush a complete checksummed snapshot before replacing the old file.
   // An abandoned .tmp after a crash is treated as unresolved state on restart.
   string staged=fib_file+".tmp";
   int file=FileOpen(staged,FILE_BIN|FILE_WRITE);
   if(file==INVALID_HANDLE) { fib_persistence_ok=false; Log("Fibonacci state cannot be staged; filtered entries disabled"); return false; }
   bool wrote=FileWriteInteger(file,201)>0;
   wrote=FileWriteInteger(file,StringLen(fib_config))>0 && wrote;
   wrote=FileWriteString(file,fib_config,StringLen(fib_config))>0 && wrote;
   uint count=FileWriteStruct(file,fib); FileFlush(file); FileClose(file);
   wrote=wrote && count==sizeof(FiboEngine);
   file=FileOpen(staged,FILE_BIN|FILE_READ|FILE_WRITE);
   if(file!=INVALID_HANDLE)
   {
      ulong size=FileSize(file); uchar bytes[];
      bool read=size>0 && size<65536 && ArrayResize(bytes,(int)size)==(int)size;
      if(read) read=FileReadArray(file,bytes,0,(int)size)==size;
      wrote=wrote && read;
      if(wrote)
      {
         wrote=FileWriteInteger(file,(int)SnapshotDigest(bytes))>0;
         wrote=FileWriteInteger(file,0x52505532)>0 && wrote;
      }
      FileFlush(file); FileClose(file);
   }
   else wrote=false;
   if(wrote) wrote=FileMove(staged,0,fib_file,FILE_REWRITE);
   fib_persistence_ok=wrote;
   if(!wrote) Log("Fibonacci snapshot commit failed; filtered entries disabled; inspect "+staged);
   return wrote;
}
bool FiboLoad()
{
   if(MQLInfoInteger(MQL_TESTER)) return false;
   if(FileIsExist(fib_file+".tmp"))
   { fib_persistence_ok=false; Log("Uncommitted Fibonacci snapshot found; refusing to restore potentially stale state: "+fib_file+".tmp"); return false; }
   if(!FileIsExist(fib_file)) return false;
   int file=FileOpen(fib_file,FILE_BIN|FILE_READ);
   if(file==INVALID_HANDLE) { fib_persistence_ok=false; return false; }
   int version=FileReadInteger(file),length=FileReadInteger(file);
   string config=length>0 && length<512?FileReadString(file,length):"";
   FiboEngine restored; ZeroMemory(restored);
   uint count=FileReadStruct(file,restored); ulong body=FileTell(file);
   uint digest=version==201?(uint)FileReadInteger(file):0;
   int sentinel=FileReadInteger(file);
   bool valid=(version==200 || version==201) && length>0 && length<512 && count==sizeof(FiboEngine) &&
      sentinel==0x52505532 && restored.count>=0 && restored.count<=4 && FileSize(file)==body+(version==201?8:4);
   if(valid && version==201)
   {
      uchar bytes[];
      valid=body<65536 && ArrayResize(bytes,(int)body)==(int)body && FileSeek(file,0,SEEK_SET);
      if(valid) valid=FileReadArray(file,bytes,0,(int)body)==body && SnapshotDigest(bytes)==digest;
   }
   FileClose(file);
   if(!valid)
   { fib_persistence_ok=false; Log("Fibonacci snapshot damaged; refusing to resurrect setups; inspect state file "+fib_file); return false; }
   if(config!=fib_config) return false; // Explicit parameter change starts a new model configuration.
   fib=restored; fib_initialized=true;
   if(version==200) { Log("Upgrading legacy Fibonacci snapshot with integrity protection"); FiboSave(); }
   return true;
}
void SetupEvent(const string model,const FiboSetup &before,const FiboSetup &after,const bool counter=false)
{
   string old_id=SetupID(before,counter),new_id=SetupID(after,counter);
   if(new_id!=old_id) Observe(model+(old_id==""?"_CREATED":"_REPLACED"),false,0,0,0,0,0,old_id+" -> "+new_id);
   else if(before.state!=after.state) Observe(model+"_"+SetupState(after.state),false,0,0,0,0,0,new_id);
}
bool FiboInputsValid()
{
   return PeriodSeconds(Fibo_Timeframe)>0 && Pivot_Left_Bars>=1 && Pivot_Left_Bars<=100 && Pivot_Right_Bars>=1 && Pivot_Right_Bars<=100 &&
      ATR_Period>=1 && ATR_Period<=500 && Swing_History_Bars>=20 && Swing_History_Bars<=100000 && Setup_Expiry_Bars>=1 &&
      MathIsValidNumber(Min_Swing_ATR) && Min_Swing_ATR>0;
}
string FiboCsvHeader()
{
   return "run_id,event_time,symbol,chart_tf,fibo_tf,event,signal_cycle,request_cycle,rsi_ready,rsi0,rsi1,rsi2,rsi3,threshold0,threshold1,threshold2,threshold3,selected_volume,signal_state,price,price_source,a_id,a_state,a_L,a_L_time,a_L_confirmed,a_H,a_H_time,a_H_confirmed,a_lower,a_upper,a_confirmed,a_atr,a_atr_time,a_dist50_atr,a_dist618_atr,a_dist786_atr,b_id,b_state,b_A,b_A_time,b_A_confirmed,b_B,b_B_time,b_B_confirmed,b_C,b_C_time,b_C_confirmed,b_e127,b_e161,b_tolerance,b_confirmed,b_zone,b_atr,b_atr_time,b_dist127_atr,b_dist161_atr,mode,fibo_ready,filter_pass,order_attempted,order,deal,position_id,fill_price,retcode,realized_net,currency,note\r\n";
}
void InitFibonacci()
{
   ActiveFiboMode=Fibo_Mode;
   fib_config=EnumToString(EffectiveFiboTF())+":"+(string)Pivot_Left_Bars+":"+(string)Pivot_Right_Bars+":"+
      FNumber(Min_Swing_ATR)+":"+(string)ATR_Period+":"+(string)Swing_History_Bars+":"+(string)Setup_Expiry_Bars;
   fib_file=key+".fibo.bin";
   fib_run=key+"."+(string)(long)TimeLocal()+"."+(string)GetTickCount64();
   fib_atr=iATR(_Symbol,Fibo_Timeframe,ATR_Period);
   if(fib_atr==INVALID_HANDLE) Log("Fibonacci ATR handle unavailable; RSI-only modes remain operational");
   FiboLoad();
   if(DEBUG_FIBO_CSV)
   {
      string debug_filename=DEBUG_FIBO_CSV_PREFIX+key+"."+(string)ActiveFiboMode+".csv";
      fib_csv=FileOpen(debug_filename,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ,0,CP_UTF8);
      if(fib_csv==INVALID_HANDLE) Log("Cannot open debug Fibonacci CSV "+debug_filename+": "+(string)GetLastError());
      else
      {
         if(FileSize(fib_csv)==0)
            FileWriteString(fib_csv,FiboCsvHeader());
         FileSeek(fib_csv,0,SEEK_END);
         Log("Debug Fibonacci CSV: "+debug_filename);
      }
   }
   Log("Fibonacci price source: "+(SymbolInfoInteger(_Symbol,SYMBOL_CHART_MODE)==SYMBOL_CHART_MODE_LAST?"LAST":"BID"));
}
// Run only when a new Fibonacci candle appears; bootstrap retries are second-throttled.
bool UpdateFiboBars()
{
   datetime current=iTime(_Symbol,Fibo_Timeframe,0);
   if(current>0 && fib_bar==current && fib_initialized) { fib_problem=fib_persistence_ok?"":"Snapshot write failure"; return fib_persistence_ok; }
   if(fib_retry==TimeCurrent()) return false;
   fib_retry=TimeCurrent();
   if(!fib_persistence_ok) { fib_problem="Unsafe snapshot; filtered entries disabled"; return false; }
   if(fib_atr==INVALID_HANDLE) { fib_problem="ATR handle unavailable"; return false; }
   if(current==0 || !SeriesInfoInteger(_Symbol,Fibo_Timeframe,SERIES_SYNCHRONIZED)) { fib_problem="Swing history not synchronized"; return false; }
   int warm=ATR_Period+Pivot_Left_Bars+Pivot_Right_Bars+2;
   int requested=Swing_History_Bars+warm+1;
   MqlRates bars[]; double atr[];
   int copied=CopyRates(_Symbol,Fibo_Timeframe,0,requested,bars);
   if(copied!=requested || BarsCalculated(fib_atr)<requested || CopyBuffer(fib_atr,0,0,requested,atr)!=requested) { fib_problem="Insufficient swing/ATR warmup history"; return false; }
   if(bars[copied-1].time!=current || iTime(_Symbol,Fibo_Timeframe,0)!=current) { fib_problem="Swing history changed during copy"; return false; }
   bool bootstrap=!fib_initialized;
   if(!bootstrap && fib.processed>0 && fib.processed<bars[warm-1].time)
   {
      // Missing bars beyond the recovery window cannot safely reconstruct an active setup.
      // Retain terminal states for diagnostics and discard old pivot candidates.
      if(fib.pullback.state==SETUP_ACTIVE) fib.pullback.state=SETUP_EXPIRED;
      if(fib.countertrend.state==SETUP_ACTIVE) fib.countertrend.state=SETUP_EXPIRED;
      fib.count=0; fib.processed=0; bootstrap=true;
      Observe("RECOVERY_WINDOW_EXCEEDED",false,0,0,0,0,0,"Expired cached setups; replaying available closed history");
   }
   fib_replaying=bootstrap;
   for(int i=warm;i<copied-1;i++)
   {
      if(bars[i].time<=fib.processed) continue;
      if(!MathIsValidNumber(atr[i]) || atr[i]==EMPTY_VALUE || atr[i]<=0) { fib_replaying=false; fib_problem="Invalid completed-bar ATR"; return false; }
      FiboSetup old_a=fib.pullback,old_b=fib.countertrend;
      InvalidatePullback(fib.pullback,bars[i].low);
      InvalidateCountertrend(fib.countertrend,bars[i].low,bars[i].high);
      AgeSetup(fib.pullback,Setup_Expiry_Bars); AgeSetup(fib.countertrend,Setup_Expiry_Bars);
      SetupEvent("PULLBACK",old_a,fib.pullback); SetupEvent("COUNTERTREND",old_b,fib.countertrend,true);
      int candidate=i-Pivot_Right_Bars;
      int oldest=MathMax(Pivot_Left_Bars,candidate-Swing_History_Bars+1);
      PrunePivots(fib,bars[oldest].time);
      PIVOT_TYPE type=DetectPivot(bars,candidate,i,Pivot_Left_Bars,Pivot_Right_Bars);
      if(type!=PIVOT_NONE)
      {
         FiboPivot pivot; pivot.type=type; pivot.price=type==PIVOT_HIGH?bars[candidate].high:bars[candidate].low;
         pivot.time=bars[candidate].time; pivot.confirmed=bars[i+1].time;
         if(AcceptPivot(fib,pivot))
         {
            FiboSetup setup;
            if(BuildPullback(fib,atr[i],bars[i].time,Min_Swing_ATR,setup) && setup.activated>fib.pullback.activated)
            { old_a=fib.pullback; fib.pullback=setup; SetupEvent("PULLBACK",old_a,fib.pullback); }
            if(BuildCountertrend(fib,atr[i],bars[i].time,Min_Swing_ATR,setup) && setup.activated>fib.countertrend.activated)
            { old_b=fib.countertrend; fib.countertrend=setup; SetupEvent("COUNTERTREND",old_b,fib.countertrend,true); }
         }
      }
      fib.processed=bars[i].time;
   }
   fib_replaying=false; fib_initialized=true; fib_bar=current;
   FiboSave();
   if(bootstrap) Observe("SETUPS_RECONSTRUCTED",false,0,0,0,0,0,"No historical entry/confirmation events emitted");
   fib_problem=fib_persistence_ok?"":"Snapshot write failure";
   return fib_persistence_ok;
}
void EvaluateFibonacci()
{
   string previous_problem=fib_problem;
   bool old_a=PullbackConfirmed,old_b=CountertrendConfirmed; int old_zone=projection_zone;
   MqlTick quote; fib_price=0;
   bool last=SymbolInfoInteger(_Symbol,SYMBOL_CHART_MODE)==SYMBOL_CHART_MODE_LAST;
   fib_source=last?"LAST":"BID";
   bool quoted=SymbolInfoTick(_Symbol,quote);
   if(quoted) fib_price=last?quote.last:quote.bid;
   FiboReady=UpdateFiboBars();
   if(!MathIsValidNumber(fib_price) || fib_price<=0) { fib_price=0; FiboReady=false; fib_source+=" UNAVAILABLE"; fib_problem="Chart-basis quote unavailable"; }
   if(FiboReady)
   {
      FiboSetup before_a=fib.pullback,before_b=fib.countertrend;
      // Current-bar extrema recover excursions during a disconnection/restart. Since
      // setups activate at bar opens, no pre-activation prices from this bar are used.
      double low=fib_price,high=fib_price; MqlRates forming[1];
      bool have_forming=CopyRates(_Symbol,Fibo_Timeframe,0,1,forming)==1;
      if(have_forming && forming[0].time>=fib.pullback.activated)
         low=MathMin(low,forming[0].low);
      InvalidatePullback(fib.pullback,low);
      low=fib_price;
      if(have_forming && forming[0].time>=fib.countertrend.activated)
      { low=MathMin(low,forming[0].low); high=MathMax(high,forming[0].high); }
      InvalidateCountertrend(fib.countertrend,low,high);
      if(before_a.state!=fib.pullback.state || before_b.state!=fib.countertrend.state)
      {
         FiboSave();
         SetupEvent("PULLBACK",before_a,fib.pullback); SetupEvent("COUNTERTREND",before_b,fib.countertrend,true);
      }
   }
   FiboReady=FiboReady && fib_persistence_ok;
   PullbackConfirmed=FiboReady && PullbackZone(fib.pullback,fib_price,TimeCurrent());
   projection_zone=FiboReady?CountertrendZone(fib.countertrend,fib_price,TimeCurrent()):0;
   CountertrendConfirmed=projection_zone!=0;
   FiboConfirmed=FiboFilter(ActiveFiboMode,PullbackConfirmed,CountertrendConfirmed);
   if(previous_problem!=fib_problem) Log("Fibonacci data: "+(fib_problem==""?"READY":fib_problem));
   if(old_a!=PullbackConfirmed || old_b!=CountertrendConfirmed || old_zone!=projection_zone) Observe("ZONE_TRANSITION");
}
void ProcessClosedFiboPositions()
{
   for(int i=ArraySize(fib_closes)-1;i>=0;i--)
   {
      FiboCloseCandidate item=fib_closes[i]; bool open=false;
      for(int j=PositionsTotal()-1;j>=0;j--)
         if(PositionGetTicket(j)>0 && (ulong)PositionGetInteger(POSITION_IDENTIFIER)==item.position) { open=true; break; }
      if(open || !HistorySelectByPosition(item.position)) continue;
      double net=0; bool entered=false,exited=false;
      for(int j=0;j<HistoryDealsTotal();j++)
      {
         ulong d=HistoryDealGetTicket(j);
         if(HistoryDealGetInteger(d,DEAL_ENTRY)==DEAL_ENTRY_IN) entered=true;
         else exited=true;
         net+=HistoryDealGetDouble(d,DEAL_PROFIT)+HistoryDealGetDouble(d,DEAL_SWAP)+HistoryDealGetDouble(d,DEAL_COMMISSION)+HistoryDealGetDouble(d,DEAL_FEE);
      }
      if(!entered || !exited) continue;
      string marker=key+".closed."+(string)item.position;
      if(MQLInfoInteger(MQL_TESTER) || !GlobalVariableCheck(marker))
      {
         Observe("POSITION_CLOSED",false,item.order,item.deal,item.position,item.price,0,"Whole-position history net incl. entry/exit costs",true,net,item.cycle);
         if(!MQLInfoInteger(MQL_TESTER)) GlobalVariableSet(marker,1);
      }
      int last=ArraySize(fib_closes)-1; fib_closes[i]=fib_closes[last]; ArrayResize(fib_closes,last);
   }
}
void ObserveDeal(const ulong deal)
{
   if(!HistoryDealSelect(deal) || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) return;
   ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER),position=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
   long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
   datetime time=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
   double price=HistoryDealGetDouble(deal,DEAL_PRICE);
   double net=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_SWAP)+HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE);
   bool owned=(ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)==Magic_Number;
   if(!owned && entry!=DEAL_ENTRY_IN && HistorySelectByPosition(position))
   {
      for(int i=0;i<HistoryDealsTotal();i++)
      {
         ulong d=HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(d,DEAL_ENTRY)==DEAL_ENTRY_IN && (ulong)HistoryDealGetInteger(d,DEAL_MAGIC)==Magic_Number) { owned=true; break; }
      }
   }
   if(!owned) return;
   string position_key=key+".pc."+(string)position;
   long cycle=GlobalVariableCheck(position_key)?(long)GlobalVariableGet(position_key):request_cycle;
   if(entry==DEAL_ENTRY_IN)
   {
      string order_key=key+".oc."+(string)order;
      if(GlobalVariableCheck(order_key)) cycle=(long)GlobalVariableGet(order_key);
      GlobalVariableSet(position_key,(double)cycle);
   }
   string marker=key+".deal."+(string)deal;
   bool seen=!MQLInfoInteger(MQL_TESTER) && GlobalVariableCheck(marker);
   if(!seen)
   {
      if(entry==DEAL_ENTRY_IN) Observe("DEAL_ENTRY",false,order,deal,position,price,0,"deal_time="+Stamp(time),false,0,cycle);
      else Observe("DEAL_EXIT",false,order,deal,position,price,0,"Deal net (not necessarily whole position); deal_time="+Stamp(time),true,net,cycle);
      if(!MQLInfoInteger(MQL_TESTER))
      {
         GlobalVariableSet(marker,1);
         double prior=GlobalVariableCheck(key+".lastDeal")?GlobalVariableGet(key+".lastDeal"):0;
         GlobalVariableSet(key+".lastDeal",MathMax(prior,(double)time)); GlobalVariablesFlush();
      }
   }
   if(entry!=DEAL_ENTRY_IN)
   {
      int n=ArraySize(fib_closes),index=n;
      for(int i=0;i<n;i++) if(fib_closes[i].position==position) { index=i; break; }
      if(index==n) ArrayResize(fib_closes,n+1);
      fib_closes[index].position=position; fib_closes[index].order=order; fib_closes[index].deal=deal;
      fib_closes[index].price=price; fib_closes[index].cycle=cycle;
   }
}
void RecoverFiboOutcomes()
{
   if(MQLInfoInteger(MQL_TESTER)) return;
   string checkpoint=key+".lastDeal";
   if(!GlobalVariableCheck(checkpoint)) { GlobalVariableSet(checkpoint,(double)TimeCurrent()); return; }
   datetime since=(datetime)GlobalVariableGet(checkpoint);
   if(!HistorySelect(since,TimeCurrent())) return;
   ulong deals[]; int n=HistoryDealsTotal(); ArrayResize(deals,n);
   for(int i=0;i<n;i++) deals[i]=HistoryDealGetTicket(i);
   // Copy ticket list first; ObserveDeal's position selections change the history view.
   for(int i=0;i<n;i++) ObserveDeal(deals[i]);
   ProcessClosedFiboPositions();
}
void CloseFibonacci()
{
   if(fib_initialized && fib_persistence_ok) FiboSave();
   if(fib_atr!=INVALID_HANDLE) IndicatorRelease(fib_atr);
   if(fib_csv!=INVALID_HANDLE) FileClose(fib_csv);
}
#endif
