#ifndef RPU_FIBO_CORE
#define RPU_FIBO_CORE
// Pure, deterministic swing/model logic. No terminal, file, chart or trading calls.
enum ENUM_FIBO_MODE { FIB_DISABLED, FIB_OBSERVE_ONLY, FIB_PULLBACK_ONLY, FIB_COUNTERTREND_ONLY, FIB_BOTH };
enum PIVOT_TYPE { PIVOT_NONE=0, PIVOT_HIGH=1, PIVOT_LOW=-1 };
enum SETUP_STATE { SETUP_NONE, SETUP_ACTIVE, SETUP_INVALIDATED, SETUP_EXPIRED };
struct FiboPivot
{
   PIVOT_TYPE type;
   double price;
   datetime time, confirmed;
};
struct FiboSetup
{
   SETUP_STATE state;
   FiboPivot a,b,c;
   datetime activated, atr_time;
   double atr, upper, lower, e127, e161, tolerance;
   int age;
};
struct FiboEngine
{
   FiboPivot pivots[4];
   int count;
   FiboSetup pullback, countertrend;
   datetime processed;
};
bool FiboFilter(const ENUM_FIBO_MODE mode,const bool pullback,const bool countertrend)
{
   if(mode==FIB_DISABLED || mode==FIB_OBSERVE_ONLY) return true;
   if(mode==FIB_PULLBACK_ONLY) return pullback;
   if(mode==FIB_COUNTERTREND_ONLY) return countertrend;
   return pullback || countertrend;
}
double Retracement(const double low,const double high,const double ratio) { return high-ratio*(high-low); }
double Expansion(const double a,const double b,const double c,const double ratio) { return c-ratio*(a-b); }
bool SwingMagnitude(const double range,const double atr,const double minimum)
{
   return MathIsValidNumber(range) && MathIsValidNumber(atr) && atr>0 && range>0 && range>=minimum*atr;
}
// Chronological closed data only; rightmost completed bar index is explicitly supplied.
// A candle simultaneously qualifying HIGH and LOW is rejected (unknown intrabar order).
PIVOT_TYPE DetectPivot(const MqlRates &bars[],const int candidate,const int closed,const int left,const int right)
{
   if(left<1 || right<1 || candidate<left || candidate+right>closed || closed>=ArraySize(bars)) return PIVOT_NONE;
   for(int i=candidate-left;i<=candidate+right;i++)
      if(!MathIsValidNumber(bars[i].high) || !MathIsValidNumber(bars[i].low) || bars[i].high<bars[i].low || bars[i].low<=0) return PIVOT_NONE;
   bool high=true,low=true;
   for(int i=candidate-left;i<=candidate+right;i++)
   {
      if(i==candidate) continue;
      if(!(bars[candidate].high>bars[i].high)) high=false;
      if(!(bars[candidate].low<bars[i].low)) low=false;
   }
   if(high==low) return PIVOT_NONE;
   return high?PIVOT_HIGH:PIVOT_LOW;
}
// Same-type candidates retain the more extreme price, earliest on ties. Setup copies
// are never edited here. A later qualifying sequence creates a separately identified setup.
bool AcceptPivot(FiboEngine &engine,const FiboPivot &pivot)
{
   if((pivot.type!=PIVOT_HIGH && pivot.type!=PIVOT_LOW) || !MathIsValidNumber(pivot.price) || pivot.price<=0 || pivot.time<=0 || pivot.confirmed<=pivot.time) return false;
   int n=engine.count;
   if(n>0)
   {
      FiboPivot last=engine.pivots[n-1];
      if(pivot.time<=last.time || pivot.confirmed<last.confirmed) return false;
      if(pivot.type==last.type)
      {
         if((pivot.type==PIVOT_HIGH && pivot.price<=last.price) || (pivot.type==PIVOT_LOW && pivot.price>=last.price)) return false;
         engine.pivots[n-1]=pivot;
         return true;
      }
   }
   if(n==4) { for(int i=0;i<3;i++) engine.pivots[i]=engine.pivots[i+1]; n=3; }
   engine.pivots[n]=pivot; engine.count=n+1;
   return true;
}
void PrunePivots(FiboEngine &engine,const datetime earliest)
{
   while(engine.count>0 && engine.pivots[0].time<earliest)
   {
      for(int i=1;i<engine.count;i++) engine.pivots[i-1]=engine.pivots[i];
      engine.count--;
   }
}
bool BuildPullback(const FiboEngine &engine,const double atr,const datetime atr_time,const double minimum,FiboSetup &setup)
{
   if(engine.count!=4) return false;
   FiboPivot l0=engine.pivots[0],h0=engine.pivots[1],l=engine.pivots[2],h=engine.pivots[3];
   if(l0.type!=PIVOT_LOW || h0.type!=PIVOT_HIGH || l.type!=PIVOT_LOW || h.type!=PIVOT_HIGH ||
      h.price<=h0.price || l.price<=l0.price || !SwingMagnitude(h.price-l.price,atr,minimum)) return false;
   ZeroMemory(setup);
   setup.state=SETUP_ACTIVE; setup.a=l; setup.b=h; setup.activated=h.confirmed;
   setup.atr=atr; setup.atr_time=atr_time;
   setup.upper=Retracement(l.price,h.price,0.5); setup.lower=Retracement(l.price,h.price,0.786);
   return true;
}
bool BuildCountertrend(const FiboEngine &engine,const double atr,const datetime atr_time,const double minimum,FiboSetup &setup)
{
   int n=engine.count;
   if(n<3) return false;
   FiboPivot a=engine.pivots[n-3],b=engine.pivots[n-2],c=engine.pivots[n-1];
   if(a.type!=PIVOT_HIGH || b.type!=PIVOT_LOW || c.type!=PIVOT_HIGH || !(a.price>c.price && c.price>b.price) ||
      !SwingMagnitude(a.price-b.price,atr,minimum)) return false;
   ZeroMemory(setup);
   setup.state=SETUP_ACTIVE; setup.a=a; setup.b=b; setup.c=c; setup.activated=c.confirmed;
   setup.atr=atr; setup.atr_time=atr_time; setup.tolerance=0.10*atr;
   setup.e127=Expansion(a.price,b.price,c.price,1.272); setup.e161=Expansion(a.price,b.price,c.price,1.618);
   if(setup.e161<=0) return false;
   return true;
}
// Completion aging occurs BEFORE activating setups confirmed by that completed bar.
void AgeSetup(FiboSetup &setup,const int expiry)
{
   if(setup.state==SETUP_ACTIVE && ++setup.age>=expiry) setup.state=SETUP_EXPIRED;
}
void InvalidatePullback(FiboSetup &setup,const double low)
{
   if(setup.state==SETUP_ACTIVE && low<setup.a.price) setup.state=SETUP_INVALIDATED;
}
void InvalidateCountertrend(FiboSetup &setup,const double low,const double high)
{
   if(setup.state==SETUP_ACTIVE && (high>setup.c.price || low<setup.e161-setup.tolerance)) setup.state=SETUP_INVALIDATED;
}
bool PullbackZone(const FiboSetup &setup,const double price,const datetime now)
{
   return setup.state==SETUP_ACTIVE && now>=setup.activated && price>=setup.lower && price<=setup.upper;
}
int CountertrendZone(const FiboSetup &setup,const double price,const datetime now)
{
   if(setup.state!=SETUP_ACTIVE || now<setup.activated) return 0;
   if(MathAbs(price-setup.e127)<=setup.tolerance) return 1272;
   if(MathAbs(price-setup.e161)<=setup.tolerance) return 1618;
   return 0;
}
#endif
