#ifndef KTR_CORE_MQH
#define KTR_CORE_MQH
// Pure closed-data calculations. Arrays are chronological (oldest at index zero).
enum KTR_DIRECTION { TRADE_BUY_ONLY, TRADE_SELL_ONLY, TRADE_BOTH };
enum KTR_FIRST { FIRST_TREND_START, FIRST_SHAPE_SIMILARITY, FIRST_EITHER };
enum KTR_STOP { SL_FRACTAL, SL_ZIGZAG, SL_FIXED_DISTANCE };
enum KTR_RISK { ADD_RISK_SAME, ADD_RISK_FIXED_REDUCTION, ADD_RISK_TREND_END_PROBABILITY };
enum KTR_STATE { IDLE, ACTIVE, SUSPENDED, CLOSING };
int KTRSign(const double a,const double b) { return a>b?1:(a<b?-1:0); }
int KTRTrendStep(const int reading,int &last)
{
   if(reading==0) return 0;
   int change=(last!=0 && last!=reading)?reading:0;
   last=reading; return change;
}
KTR_STATE KTREpisodeState(const int count,const bool first_open,const bool closing)
{
   if(closing) return CLOSING;
   if(count==0) return IDLE;
   return first_open?ACTIVE:SUSPENDED;
}
double KTRCosine(const double &x[],const double &y[],const int ax,const int ay,const int n)
{
   if(n<3 || ax<0 || ay<0 || ax+n>ArraySize(x) || ay+n>ArraySize(y)) return -2;
   double dot=0,nx=0,ny=0;
   for(int k=1;k<n;k++)
   {
      double dx=x[ax+k]-x[ax+k-1],dy=y[ay+k]-y[ay+k-1];
      dot+=dx*dy; nx+=dx*dx; ny+=dy*dy;
   }
   if(nx<=1e-20 || ny<=1e-20) return -2;
   return MathMax(-1.0,MathMin(1.0,dot/MathSqrt(nx*ny)));
}
double KTRAmplitude(const double &x[],const int start,const int n)
{
   if(start<0 || start+n>ArraySize(x) || n<1) return 0;
   double lo=x[start],hi=lo;
   for(int k=start+1;k<start+n;k++) { lo=MathMin(lo,x[k]); hi=MathMax(hi,x[k]); }
   return hi-lo;
}
struct KTRFeature { int pivot; int confirmation; int kind; };
// Cluster's last bar is its canonical pivot. All right bars must be completed.
void KTRFeatures(const double &x[],const int left,const int right,const double tolerance,KTRFeature &out[])
{
   ArrayResize(out,0); int n=ArraySize(x),start=0;
   while(start<n)
   {
      int end=start;
      double lo=x[start],hi=lo;
      while(end+1<n && MathMax(hi,x[end+1])-MathMin(lo,x[end+1])<=tolerance)
      { end++; lo=MathMin(lo,x[end]); hi=MathMax(hi,x[end]); }
      if(start>=left && end+right<n)
      {
         bool valley=true,peak=true;
         for(int k=start-left;k<start;k++) { valley=valley && x[k]>hi+tolerance; peak=peak && x[k]<lo-tolerance; }
         for(int k=end+1;k<=end+right;k++) { valley=valley && x[k]>hi+tolerance; peak=peak && x[k]<lo-tolerance; }
         if(valley || peak)
         {
            int m=ArraySize(out); ArrayResize(out,m+1);
            out[m].pivot=end; out[m].confirmation=end+right; out[m].kind=valley?1:-1;
         }
      }
      start=end+1;
   }
}
bool KTRShapeMatch(const double &x[],const double &ssa[],const KTRFeature &a,const KTRFeature &b,
                   const int window,const int lag,const double similarity,const double amplitude)
{
   if(a.kind!=b.kind || MathAbs(a.pivot-b.pivot)>lag) return false;
   // Windows end at confirmation, and are independently aligned to the pivots.
   int sx=a.confirmation-window+1,sy=b.confirmation-window+1;
   return KTRAmplitude(x,sx,window)>=amplitude && KTRAmplitude(ssa,sy,window)>=amplitude &&
          KTRCosine(x,ssa,sx,sy,window)>=similarity;
}
bool KTRPullback(const int dir,const double high,const double low,const double close,const double level,const double tol)
{ return low<=level+tol && high>=level-tol && dir*(close-level)>0; }
bool KTRRejection(const int dir,const double open,const double high,const double low,const double close,
                  const double level,const double tol,const double ratio,const double epsilon)
{
   double body=MathAbs(close-open),wick=dir>0?MathMin(open,close)-low:high-MathMax(open,close);
   return body>epsilon && dir*(close-open)>0 && wick>=body*ratio && KTRPullback(dir,high,low,close,level,tol);
}
bool KTRCross(const int dir,const double pt,const double pk,const double t,const double k)
{ return dir*(pt-pk)<=0 && dir*(t-k)>0; }
double KTRReducedRisk(const double base,const double reduction,const int entry_index)
{ return base*MathPow(1.0-reduction/100.0,MathMax(0,entry_index-1)); }
double KTREndProbability(const int &durations[],const int age,const int horizon,int &eligible)
{
   eligible=0; int ended=0;
   for(int i=0;i<ArraySize(durations);i++) if(durations[i]>age)
   { eligible++; if(durations[i]<=age+horizon) ended++; }
   return eligible==0?0:(double)ended/eligible;
}
double KTRFloorVolume(const double budget,const double loss_per_lot,const double step,const double minimum,const double maximum)
{
   if(budget<=0 || loss_per_lot<=0 || step<=0) return 0;
   double v=MathFloor(MathMin(maximum,budget/loss_per_lot)/step)*step;
   if(v<minimum || v*loss_per_lot>budget+1e-8) return 0;
   return v;
}
bool KTRRiskFits(const double balance,const double equity,const double open_loss,const double new_loss,const double percent)
{ return balance>0 && equity>0 && open_loss>=0 && new_loss>=0 && equity-open_loss-new_loss>=balance*(1-percent/100.0); }
double KTRRoundStop(const double level,const double tick,const int dir)
{ if(tick<=0) return 0; return (dir>0?MathFloor(level/tick):MathCeil(level/tick))*tick; }
struct KTRSwing { int pivot; int confirmation; int kind; double price; datetime pivot_time; datetime confirmed_at; };
struct KTRZigState
{
   int phase; int sequence; int ph; int pl; double ch; double cl;
   datetime high_time; datetime low_time;
   double high[],low[];
};
void KTRZigInit(KTRZigState &s,const int depth)
{
   s.phase=0; s.sequence=0; s.ph=-1; s.pl=-1; s.ch=0; s.cl=0; s.high_time=0; s.low_time=0;
   ArrayResize(s.high,depth); ArrayResize(s.low,depth);
}
// Incremental, bounded causal detector. Confirmed results never depend on a sliding
// replay window. Backstep is a completed-bar stability requirement (see README).
bool KTRZigStep(KTRZigState &s,const double high,const double low,const datetime time,
                const int depth,const int backstep,const double deviation,KTRSwing &result)
{
   int i=s.sequence++; s.high[i%depth]=high; s.low[i%depth]=low;
   if(i<depth-1) return false;
   double hh=high,ll=low;
   for(int k=0;k<depth;k++) { hh=MathMax(hh,s.high[k]); ll=MathMin(ll,s.low[k]); }
   if(s.phase>=0 && high>=hh && (s.ph<0 || high>=s.ch)) { s.ph=i; s.ch=high; s.high_time=time; }
   if(s.phase<=0 && low<=ll && (s.pl<0 || low<=s.cl)) { s.pl=i; s.cl=low; s.low_time=time; }
   bool top=s.phase>=0 && s.ph>=0 && i-s.ph>=backstep && s.ch-low>=deviation;
   bool bottom=s.phase<=0 && s.pl>=0 && i-s.pl>=backstep && high-s.cl>=deviation;
   if(top==bottom) return false;
   result.pivot=top?s.ph:s.pl; result.price=top?s.ch:s.cl;
   result.kind=top?-1:1; result.confirmation=i;
   result.pivot_time=top?s.high_time:s.low_time; result.confirmed_at=time;
   s.phase=top?-1:1; s.ph=-1; s.pl=-1;
   return true;
}
void KTRZigZag(const double &high[],const double &low[],const int depth,const int backstep,
               const double deviation,KTRSwing &out[])
{
   ArrayResize(out,0); KTRZigState state; KTRZigInit(state,depth);
   for(int i=0;i<ArraySize(high);i++)
   {
      KTRSwing swing;
      if(KTRZigStep(state,high[i],low[i],(datetime)i,depth,backstep,deviation,swing))
      { int n=ArraySize(out); ArrayResize(out,n+1); out[n]=swing; }
   }
}
#endif
