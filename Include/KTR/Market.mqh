#ifndef KTR_MARKET_MQH
#define KTR_MARKET_MQH
class KTRMarket
{
public:
   ENUM_TIMEFRAMES tf;
   int ichi,atr_handle;
   MqlRates bars[];
   double tenkan[],kijun[],ssa[],ssb[],atr[];
   bool ready;
   KTRMarket() { ichi=INVALID_HANDLE; atr_handle=INVALID_HANDLE; ready=false; }
   bool Init(const ENUM_TIMEFRAMES period)
   {
      tf=period; ichi=iIchimoku(_Symbol,tf,9,26,52); atr_handle=iATR(_Symbol,tf,ATR_Period);
      return ichi!=INVALID_HANDLE && atr_handle!=INVALID_HANDLE;
   }
   void Release() { if(ichi!=INVALID_HANDLE) IndicatorRelease(ichi); if(atr_handle!=INVALID_HANDLE) IndicatorRelease(atr_handle); }
   double Mid(const int at,const int count)
   {
      double hi=bars[at].high,lo=bars[at].low;
      for(int j=at-count+1;j<at;j++) { hi=MathMax(hi,bars[j].high); lo=MathMin(lo,bars[j].low); }
      return (hi+lo)/2;
   }
   bool Load(const int requested)
   {
      ready=false;
      int available=Bars(_Symbol,tf)-1;
      int n=MathMin(requested,available);
      if(n<120 || BarsCalculated(ichi)<n+1 || BarsCalculated(atr_handle)<n+1) return false;
      ArraySetAsSeries(bars,false);
      if(CopyRates(_Symbol,tf,1,n,bars)!=n) return false;
      // Calculation shift 1 maps to plotted shift 1-26 = -25.
      // Physical memory returned by CopyBuffer is oldest-to-newest.
      if(CopyBuffer(ichi,0,1,n,tenkan)!=n || CopyBuffer(ichi,1,1,n,kijun)!=n ||
         CopyBuffer(ichi,2,1-26,n,ssa)!=n || CopyBuffer(ichi,3,1-26,n,ssb)!=n ||
         CopyBuffer(atr_handle,0,1,n,atr)!=n) return false;
      double epsilon=MathMax(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE)*0.01,1e-9);
      for(int i=n-8;i<n;i++)
      {
         double t=Mid(i,9),k=Mid(i,26),b=Mid(i,52);
         if(!MathIsValidNumber(ssa[i]) || !MathIsValidNumber(ssb[i]) ||
            MathAbs(tenkan[i]-t)>epsilon || MathAbs(kijun[i]-k)>epsilon ||
            MathAbs(ssa[i]-(t+k)/2)>epsilon || MathAbs(ssb[i]-b)>epsilon)
         { Print("[KTR] Ichimoku alignment/OHLC check failed; entries blocked"); return false; }
      }
      ready=atr[n-1]>0 && MathIsValidNumber(atr[n-1]); return ready;
   }
   int Last() { return ArraySize(bars)-1; }
   int Direction() { int i=Last(); return ready?KTRSign(ssa[i],ssb[i]):0; }
   int PreviousDirection(const int before)
   { for(int i=before;i>=52;i--) { int d=KTRSign(ssa[i],ssb[i]); if(d!=0) return d; } return 0; }
   int LatestReversal()
   { int i=Last(),last=PreviousDirection(i-1); return KTRSign(ssa[i],ssb[i])!=0 && last!=0 && last!=Direction()?Direction():0; }
   bool ReversalAfter(const datetime time,bool &covered)
   {
      covered=false;
      if(!ready || bars[53].time>time) return false;
      int last=0;
      for(int i=52;i<=Last();i++)
      {
         int reading=KTRSign(ssa[i],ssb[i]);
         datetime confirmation=(i<Last()?bars[i+1].time:iTime(_Symbol,tf,0));
         if(reading!=0 && confirmation<=time) covered=true;
         int change=KTRTrendStep(reading,last);
         if(change!=0 && confirmation>time) return true;
      }
      // A long neutral interval without a known pre-entry direction cannot prove
      // that the first subsequent non-neutral reading wasn't an offline reversal.
      return false;
   }
};
struct KTRSignal { bool buy; bool sell; datetime buy_event; datetime sell_event; int buy_method; int sell_method; };
void KTRClearSignal(KTRSignal &s) { ZeroMemory(s); }
struct KTRShapeEvent { datetime event; int tf; int dir; };
KTRShapeEvent ktr_shape_events[];
bool KTRShapeConsumed(const int tf,const int dir,const datetime event)
{
   for(int i=ArraySize(ktr_shape_events)-1;i>=0;i--)
      if(ktr_shape_events[i].tf==tf && ktr_shape_events[i].dir==dir && ktr_shape_events[i].event==event) return true;
   return false;
}
void KTRRememberShape(const int tf,const int dir,const datetime event)
{
   if(KTRShapeConsumed(tf,dir,event)) return;
   int n=ArraySize(ktr_shape_events);
   if(n>=8192) { for(int i=1;i<n;i++) ktr_shape_events[i-1]=ktr_shape_events[i]; n--; }
   ArrayResize(ktr_shape_events,n+1); ktr_shape_events[n].tf=tf;
   ktr_shape_events[n].dir=dir; ktr_shape_events[n].event=event;
}
void KTRShapePair(KTRMarket &m,const double &line[],const bool valleys,const bool peaks,
                  const int method,KTRSignal &s,const bool seed=false)
{
   int end=m.Last();
   // Use a fixed price tolerance in ticks. ATR normalization is applied to movement,
   // not to plateau membership, so a changing ATR cannot relabel old plateaus.
   double tolerance=Shape_Plateau_Tolerance*SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   KTRFeature a[],b[];
   // Warmup buffers contain EMPTY_VALUE: copy only independently valid calculation history.
   double x[],y[]; int count=end-51; ArrayResize(x,count); ArrayResize(y,count);
   for(int i=0;i<count;i++) { x[i]=line[i+52]; y[i]=m.ssa[i+52]; }
   KTRFeatures(x,Shape_Pivot_Left_Bars,Shape_Pivot_Right_Bars,tolerance,a);
   KTRFeatures(y,Shape_Pivot_Left_Bars,Shape_Pivot_Right_Bars,tolerance,b);
   for(int j=ArraySize(b)-1;j>=0;j--)
   {
      if(b[j].confirmation<count-1-Shape_Max_Lag_Bars) break;
      for(int k=ArraySize(a)-1;k>=0;k--)
      {
         if(a[k].confirmation<count-1-Shape_Max_Lag_Bars) break;
         if(!seed && MathMax(a[k].confirmation,b[j].confirmation)!=count-1) continue;
         if((b[j].kind>0 && !valleys) || (b[j].kind<0 && !peaks)) continue;
         if(!KTRShapeMatch(x,y,a[k],b[j],Shape_Window_Bars,Shape_Max_Lag_Bars,
                           Shape_Min_Similarity,m.atr[end]*Shape_Min_Amplitude_ATR)) continue;
         datetime event=m.bars[b[j].pivot+52].time; // canonical SSA feature ID
         if(seed) { KTRRememberShape(PeriodSeconds(m.tf),b[j].kind,event); continue; }
         if(KTRShapeConsumed(PeriodSeconds(m.tf),b[j].kind,event)) continue;
         if(b[j].kind>0)
         { s.buy=true; s.buy_event=event; s.buy_method|=method; }
         else { s.sell=true; s.sell_event=event; s.sell_method|=method; }
      }
   }
}
void KTRFirstSignals(KTRMarket &m,KTRSignal &s)
{
   KTRClearSignal(s); if(!m.ready) return;
   if(First_Entry_Method!=FIRST_TREND_START)
   {
      KTRShapePair(m,m.tenkan,Enable_Tenkan_SSA_Valley,Enable_Tenkan_SSA_Peak,2,s);
      KTRShapePair(m,m.kijun,Enable_Kijun_SSA_Valley,Enable_Kijun_SSA_Peak,4,s);
   }
   // Consume a market structure even when confirmations/risk/episode state reject it.
   // Both pairs have been merged before remembering, preserving their diagnostic bits.
   if(s.buy) KTRRememberShape(PeriodSeconds(m.tf),1,s.buy_event);
   if(s.sell) KTRRememberShape(PeriodSeconds(m.tf),-1,s.sell_event);
   if(m.Direction()==0) { KTRClearSignal(s); return; }
   int reversal=m.LatestReversal();
   if(First_Entry_Method!=FIRST_SHAPE_SIMILARITY && reversal!=0)
   {
      if(reversal>0) { if(!s.buy) s.buy_event=m.bars[m.Last()].time; s.buy=true; s.buy_method|=1; }
      else { if(!s.sell) s.sell_event=m.bars[m.Last()].time; s.sell=true; s.sell_method|=1; }
   }
}
void KTRSeedShapeHistory(KTRMarket &m)
{
   if(!m.ready || First_Entry_Method==FIRST_TREND_START) return;
   KTRSignal ignored; KTRClearSignal(ignored);
   KTRShapePair(m,m.tenkan,Enable_Tenkan_SSA_Valley,Enable_Tenkan_SSA_Peak,2,ignored,true);
   KTRShapePair(m,m.kijun,Enable_Kijun_SSA_Valley,Enable_Kijun_SSA_Peak,4,ignored,true);
}
// Flat-level classification and invalidation are frozen when duration first qualifies.
bool KTRFlatInteraction(KTRMarket &m,const int dir,const bool confirmation)
{
   int end=m.Last(),start=MathMax(52,end-Flat_SSB_Max_Age_Bars-Flat_SSB_Min_Bars);
   for(int i=start;i+Flat_SSB_Min_Bars-1<end;)
   {
      int finish=i; double lo=m.ssb[i],hi=lo,tol=m.atr[i]*Flat_SSB_Max_Variation_ATR;
      while(finish+1<end && MathMax(hi,m.ssb[finish+1])-MathMin(lo,m.ssb[finish+1])<=tol)
      { finish++; lo=MathMin(lo,m.ssb[finish]); hi=MathMax(hi,m.ssb[finish]); }
      int known=i+Flat_SSB_Min_Bars-1;
      if(finish>=known && end-known<=Flat_SSB_Max_Age_Bars)
      {
         double level=0; for(int j=i;j<=known;j++) level+=m.ssb[j]; level/=Flat_SSB_Min_Bars;
         double touch=m.atr[end]*Flat_SSB_Touch_ATR;
         bool valid=dir*(m.bars[known].close-level)>0;
         for(int j=known+1;j<end && valid;j++) if(dir*(m.bars[j].close-level)<-m.atr[j]*Flat_SSB_Touch_ATR) valid=false;
         if(valid && KTRPullback(dir,m.bars[end].high,m.bars[end].low,m.bars[end].close,level,touch))
         {
            // Confirmation additionally requires approach from the supported side.
            if(!confirmation || dir*(m.bars[end-1].close-level)>0) return true;
         }
      }
      i=finish+1;
   }
   return false;
}
bool KTRSwingInteraction(KTRMarket &m,const int dir)
{
   int end=m.Last(),start=MathMax(54,end-SR_Lookback_Bars);
   double tol=m.atr[end]*SR_Tolerance_ATR;
   for(int p=start;p+2<end;p++)
   {
      double level=dir>0?m.bars[p].low:m.bars[p].high;
      bool pivot=true;
      for(int j=p-2;j<=p+2;j++) if(j!=p && (dir>0?m.bars[j].low<=level:m.bars[j].high>=level)) pivot=false;
      if(!pivot) continue;
      int touches=1,last=p; bool valid=true;
      for(int q=p+3;q<end;q++)
      {
         if(dir*(m.bars[q].close-level)<-tol) { valid=false; break; }
         if(q+2>=end || q-last<SR_Min_Touch_Separation) continue;
         double value=dir>0?m.bars[q].low:m.bars[q].high;
         bool other=true;
         for(int j=q-2;j<=q+2;j++) if(j!=q && (dir>0?m.bars[j].low<=value:m.bars[j].high>=value)) other=false;
         if(other && MathAbs(value-level)<=tol) { touches++; last=q; }
      }
      if(valid && touches>=SR_Min_Touches && KTRPullback(dir,m.bars[end].high,m.bars[end].low,m.bars[end].close,level,tol)) return true;
   }
   return false;
}
bool KTRConfirm(KTRMarket &m,KTRMarket &higher,const int dir,const bool first)
{
   if(!m.ready || m.Direction()==0) return false;
   int i=m.Last();
   bool price=first?First_Confirm_Price_Kumo:Additional_Confirm_Price_Kumo;
   bool tk=first?First_Confirm_TK:Additional_Confirm_TK;
   bool flat=first?First_Confirm_Flat_SSB:Additional_Confirm_Flat_SSB;
   bool swing=first?First_Confirm_Swing_SR:Additional_Confirm_Swing_SR;
   bool thick=first?First_Confirm_Thickness:Additional_Confirm_Thickness;
   bool htf=first?First_Confirm_HigherTF:Additional_Confirm_HigherTF;
   bool chikou=first?First_Confirm_Chikou:Additional_Confirm_Chikou;
   if(price && (dir>0?m.bars[i].close<=MathMax(m.ssa[i-26],m.ssb[i-26]):m.bars[i].close>=MathMin(m.ssa[i-26],m.ssb[i-26]))) return false;
   if(tk && dir*(m.tenkan[i]-m.kijun[i])<=0) return false;
   if(flat && !KTRFlatInteraction(m,dir,true)) return false;
   if(swing && !KTRSwingInteraction(m,dir)) return false;
   if(thick && MathAbs(m.ssa[i]-m.ssb[i])<m.atr[i]*Cloud_Min_Thickness_ATR) return false;
   if(htf && (!higher.ready || higher.Direction()!=dir)) return false;
   if(chikou && (dir>0?m.bars[i].close<=m.bars[i-26].high+m.atr[i]*Chikou_Clearance_ATR:
                              m.bars[i].close>=m.bars[i-26].low-m.atr[i]*Chikou_Clearance_ATR)) return false;
   return true;
}
int KTRAdditionalMethods(KTRMarket &m,const int dir)
{
   int i=m.Last(),mask=0; double tol=m.atr[i]*Kijun_Touch_ATR;
   if(Enable_Kijun_Pullback && KTRPullback(dir,m.bars[i].high,m.bars[i].low,m.bars[i].close,m.kijun[i],tol)) mask|=16;
   if(Enable_Tenkan_Kijun_Cross && KTRCross(dir,m.tenkan[i-1],m.kijun[i-1],m.tenkan[i],m.kijun[i])) mask|=32;
   if(Enable_Flat_SSB_Bounce && KTRFlatInteraction(m,dir,false)) mask|=64;
   if(Enable_Kijun_Rejection && KTRRejection(dir,m.bars[i].open,m.bars[i].high,m.bars[i].low,
      m.bars[i].close,m.kijun[i],tol,Kijun_Rejection_Min_WickBody,SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE)*0.1)) mask|=128;
   return mask;
}
#endif
