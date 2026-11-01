#ifndef RPU_FIBO_CHART
#define RPU_FIBO_CHART
// Native objects use solid muted zone colors; OBJ_RECTANGLE has no portable alpha.
void FiboText(const string name,const datetime time,const double price,const string text,const color ink)
{
   if(ObjectFind(0,name)<0 && !ObjectCreate(0,name,OBJ_TEXT,0,time,price)) { Log("Fibonacci label creation failed"); return; }
   if(!ObjectMove(0,name,0,time,price)) Log("Fibonacci label move failed");
   ObjectSetString(0,name,OBJPROP_TEXT,text); ObjectSetInteger(0,name,OBJPROP_COLOR,ink);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8); ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}
void FiboRectangle(const string name,const datetime first,const datetime last,const double lower,const double upper,const color ink)
{
   if(ObjectFind(0,name)<0 && !ObjectCreate(0,name,OBJ_RECTANGLE,0,first,lower,last,upper)) { Log("Fibonacci zone creation failed"); return; }
   if(!ObjectMove(0,name,0,first,lower) || !ObjectMove(0,name,1,last,upper)) Log("Fibonacci zone move failed");
   ObjectSetInteger(0,name,OBJPROP_COLOR,ink); ObjectSetInteger(0,name,OBJPROP_FILL,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true); ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}
// MT5 retracement: price2 + r*(price1-price2).
// MT5 expansion: price3 + r*(price2-price1).
// Read back the actual stored coordinates/coefficients and verify every labeled level.
bool VerifyGraphicalLevels(const string object,const bool counter,const FiboSetup &setup)
{
   double p0=ObjectGetDouble(0,object,OBJPROP_PRICE,0),p1=ObjectGetDouble(0,object,OBJPROP_PRICE,1);
   double p2=counter?ObjectGetDouble(0,object,OBJPROP_PRICE,2):0;
   int count=(int)ObjectGetInteger(0,object,OBJPROP_LEVELS);
   double tolerance=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE)*1e-6;
   for(int i=0;i<count;i++)
   {
      double ratio=ObjectGetDouble(0,object,OBJPROP_LEVELVALUE,i);
      double native=counter?p2+ratio*(p1-p0):p1+ratio*(p0-p1);
      double expected=counter?Expansion(setup.a.price,setup.b.price,setup.c.price,ratio):Retracement(setup.a.price,setup.b.price,ratio);
      if(MathAbs(native-expected)>MathMax(1e-10,tolerance)) return false;
   }
   return true;
}
void DrawFiboModel(const bool counter)
{
   FiboSetup setup=counter?fib.countertrend:fib.pullback;
   string root=prefix+(counter?"FIB.B.":"FIB.A.");
   bool show=counter?Show_Countertrend_Fibonacci:Show_Pullback_Fibonacci;
   string tag=SetupID(setup,counter)+":"+(string)setup.state+":"+(FiboReady?"READY":"STALE")+":"+(string)(long)fib_bar+":"+(show?"ON":"OFF");
   if(counter) { if(drawn_countertrend==tag) return; drawn_countertrend=tag; }
   else { if(drawn_pullback==tag) return; drawn_pullback=tag; }
   if(!show || setup.state==SETUP_NONE) { ObjectsDeleteAll(0,root); return; }
   bool active=setup.state==SETUP_ACTIVE && FiboReady;
   color ink=active?(counter?Countertrend_Fibonacci_Color:Pullback_Fibonacci_Color):clrGray;
   string object=root+"object";
   ENUM_OBJECT type=counter?OBJ_EXPANSION:OBJ_FIBO;
   if(ObjectFind(0,object)<0)
   {
      bool created=counter?ObjectCreate(0,object,type,0,setup.a.time,setup.a.price,setup.b.time,setup.b.price,setup.c.time,setup.c.price):
         ObjectCreate(0,object,type,0,setup.a.time,setup.a.price,setup.b.time,setup.b.price);
      if(!created) { Log("Fibonacci object creation failed"); return; }
   }
   if(!ObjectMove(0,object,0,setup.a.time,setup.a.price) || !ObjectMove(0,object,1,setup.b.time,setup.b.price)) Log("Fibonacci anchor update failed");
   if(counter && !ObjectMove(0,object,2,setup.c.time,setup.c.price)) Log("Expansion C anchor update failed");
   double pullback[7]={0,0.236,0.382,0.5,0.618,0.786,1};
   double expansion[3]={1,1.272,1.618};
   int levels=counter?3:7;
   ObjectSetInteger(0,object,OBJPROP_LEVELS,levels);
   ObjectSetInteger(0,object,OBJPROP_COLOR,ink); ObjectSetInteger(0,object,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,object,OBJPROP_HIDDEN,true); ObjectSetInteger(0,object,OBJPROP_RAY_RIGHT,active);
   for(int i=0;i<levels;i++)
   {
      double ratio=counter?expansion[i]:pullback[i];
      double price=counter?Expansion(setup.a.price,setup.b.price,setup.c.price,ratio):Retracement(setup.a.price,setup.b.price,ratio);
      ObjectSetDouble(0,object,OBJPROP_LEVELVALUE,i,ratio);
      ObjectSetString(0,object,OBJPROP_LEVELTEXT,i,DoubleToString(ratio*100,1)+"%  "+DoubleToString(price,_Digits));
      ObjectSetInteger(0,object,OBJPROP_LEVELCOLOR,i,ink);
      ObjectSetInteger(0,object,OBJPROP_LEVELSTYLE,i,active?STYLE_SOLID:STYLE_DOT);
   }
   if(!VerifyGraphicalLevels(object,counter,setup)) Log("ERROR: Fibonacci coordinate/level readback mismatch");
   string state=SetupState(setup.state)+(setup.state==SETUP_ACTIVE && !FiboReady?" / DATA UNAVAILABLE":"");
   FiboText(root+"anchor0",setup.a.time,setup.a.price,(counter?"A ":"L ")+DoubleToString(setup.a.price,_Digits),ink);
   FiboText(root+"anchor1",setup.b.time,setup.b.price,(counter?"B ":"H ")+DoubleToString(setup.b.price,_Digits),ink);
   FiboText(root+"status",setup.activated,counter?setup.c.price:setup.b.price,(counter?"B: ":"A: ")+state,ink);
   if(counter) FiboText(root+"anchor2",setup.c.time,setup.c.price,"C "+DoubleToString(setup.c.price,_Digits),ink);
   if(!active || !Show_Fibonacci_Zones) { ObjectDelete(0,root+"zone0"); ObjectDelete(0,root+"zone1"); return; }
   datetime end=(datetime)((long)fib_bar+5*PeriodSeconds(Fibo_Timeframe));
   if(counter)
   {
      FiboRectangle(root+"zone0",setup.activated,end,setup.e127-setup.tolerance,setup.e127+setup.tolerance,Countertrend_Zone_Color);
      FiboRectangle(root+"zone1",setup.activated,end,setup.e161-setup.tolerance,setup.e161+setup.tolerance,Countertrend_Zone_Color);
   }
   else FiboRectangle(root+"zone0",setup.activated,end,setup.lower,setup.upper,Pullback_Zone_Color);
}
void DrawFibonacci() { DrawFiboModel(false); DrawFiboModel(true); }
#endif
