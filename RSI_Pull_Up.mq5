// RSI Pull Up -- current-candle, BUY-only RSI strategy.
#property strict
#property version "1.00"
#property description "Multi-timeframe RSI BUY strategy with account-currency protective stops."

input group "Position Sizing"
input double Vol=0.01;
input double Vol2=0.02;
input double Vol3=0.03;
input group "RSI Settings"
input double RSI_Entry_Level=30.0;
input double RSI_Confirmation_Level=30.0;
input ENUM_TIMEFRAMES RSI1_Timeframe=PERIOD_M5;
input ENUM_TIMEFRAMES RSI2_Timeframe=PERIOD_M15;
input ENUM_TIMEFRAMES RSI3_Timeframe=PERIOD_H1;
input group "Trade Management"
input double Take_Profit=4.0; // Account currency, per position (estimated gross profit)
input double Stop_Loss=2.0;   // Account currency, per position (estimated gross loss)
input ulong Magic_Number=300130;
input uint Max_Slippage_Points=20;
input bool Enable_Trading=true;
input group "Fibonacci Settings"
input bool Show_Fibonacci=true;
input int Fibonacci_Lookback_Hours=24;
input color Fibonacci_Color=clrDodgerBlue;
enum MONITOR_POSITION { RIGHT_MIDDLE, LEFT_MIDDLE, RIGHT_TOP, LEFT_TOP };
input group "RSI Monitor Settings"
input bool Show_RSI_Monitor=true;
input MONITOR_POSITION Monitor_Position=RIGHT_MIDDLE;
input int Monitor_X_Offset=20;
input int Monitor_Y_Offset=0;
input int Monitor_Font_Size=11;
input color Monitor_Text_Color=clrWhite;
input color Monitor_Background_Color=clrBlack;
input color Confirmation_Background_Color=clrGreen;

enum SIGNAL_STATE { ARMED=0, CONSUMED=1 };
SIGNAL_STATE signal_state=ARMED;
int handles[4];
double rsi[4];
bool ready=false, timeframe_ok=false, pending=false;
ulong pending_order=0;
datetime attempted_bar=0, pending_since=0, last_cancel_try=0;
string key, prefix, status_text="Starting", last_log="", currency;
datetime last_log_time=0, fib_checked=0;
bool owns_instance_lock=false;
string fib_status="";
double fib_high=0, fib_low=0, last_m1_high=0, last_m1_low=0;
datetime last_m1_time=0;
datetime fib_t0=0, fib_t1=0;
double fib_p0=0, fib_p1=0;

void Log(const string message)
{
   if(message==last_log && TimeCurrent()-last_log_time<60) return;
   PrintFormat("[RSI Pull Up] %s | %s %s | %s",TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),_Symbol,EnumToString(_Period),message);
   last_log=message; last_log_time=TimeCurrent();
}
void Status(const string message)
{
   if(status_text!=message) { status_text=message; Log(message); }
}
// Two independent hashes keep keys short enough for terminal Global Variables.
string Scope()
{
   string s=AccountInfoString(ACCOUNT_SERVER)+"|"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"|"+_Symbol+"|"+(string)Magic_Number;
   uint a=2166136261,b=5381;
   for(int i=0;i<StringLen(s);i++) { uint c=StringGetCharacter(s,i); a=(a^c)*16777619; b=b*33+c; }
   return StringFormat("RPU.%08X%08X",a,b)+(MQLInfoInteger(MQL_TESTER)?".test":".live");
}
// Atomic per-terminal instance guard. A second chart must not race the same scope.
// Temporary globals disappear on terminal shutdown; stale chart owners are reclaimed.
bool AcquireInstance()
{
   string lock=key+".instance";
   if(!GlobalVariableTemp(lock)) return false;
   double previous=GlobalVariableGet(lock);
   if(previous!=0)
   {
      for(long chart=ChartFirst();chart>=0;chart=ChartNext(chart))
         if((double)chart==previous) { Log("Another chart already owns this account/symbol/magic scope"); return false; }
   }
   owns_instance_lock=GlobalVariableSetOnCondition(lock,(double)ChartID(),previous);
   return owns_instance_lock;
}
void FibStatus(const string text)
{
   if(fib_status!=text) { fib_status=text; if(text!="") Log(text); }
}
bool Save()
{
   bool ok=true;
   if(GlobalVariableSet(key+".state",(double)signal_state)==0) ok=false;
   if(GlobalVariableSet(key+".bar",(double)attempted_bar)==0) ok=false;
   if(GlobalVariableSet(key+".pending",pending?1.0:0.0)==0) ok=false;
   if(GlobalVariableSet(key+".since",(double)pending_since)==0) ok=false;
   // Store ticket in two exact 32-bit halves; double cannot represent all ulong tickets.
   if(GlobalVariableSet(key+".orderHi",(double)(pending_order>>32))==0) ok=false;
   if(GlobalVariableSet(key+".orderLo",(double)(pending_order & 0xFFFFFFFF))==0) ok=false;
   GlobalVariablesFlush();
   if(!ok) Log("ERROR: could not persist signal/request state; new orders blocked");
   return ok;
}
void Consume()
{
   if(signal_state!=CONSUMED) { signal_state=CONSUMED; Save(); }
}
bool PositionBlocks()
{
   bool netting=AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(PositionGetTicket(i)==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(netting || (ulong)PositionGetInteger(POSITION_MAGIC)==Magic_Number) return true;
   }
   return false;
}
bool OwnedPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(PositionGetTicket(i)>0 && PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==Magic_Number) return true;
   return false;
}
ulong ActiveOrder()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket>0 && OrderGetString(ORDER_SYMBOL)==_Symbol && (ulong)OrderGetInteger(ORDER_MAGIC)==Magic_Number) return ticket;
   }
   return 0;
}
void ClearPending()
{
   pending=false; pending_order=0; pending_since=0; Save();
}
// Reconcile using broker positions/orders/history, never a timeout-based blind retry.
void Reconcile()
{
   ulong active=ActiveOrder();
   if(active>0)
   {
      if(!pending || pending_order!=active) { pending=true; pending_order=active; if(pending_since==0) pending_since=TimeCurrent(); Save(); }
      if(OrderSelect(active) && OrderGetDouble(ORDER_VOLUME_CURRENT)<OrderGetDouble(ORDER_VOLUME_INITIAL)-1e-10)
      { Consume(); CancelRemainder(active); }
      return;
   }
   if(!pending) return;
   if(OwnedPosition()) { Consume(); ClearPending(); return; }
   if(!HistorySelect(pending_since>0?pending_since-60:0,TimeCurrent())) return;
   bool filled=false;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
   {
      ulong d=HistoryDealGetTicket(i);
      if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol || (ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=Magic_Number) continue;
      if(HistoryDealGetInteger(d,DEAL_TYPE)!=DEAL_TYPE_BUY || HistoryDealGetInteger(d,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
      if((pending_order>0 && (ulong)HistoryDealGetInteger(d,DEAL_ORDER)==pending_order) ||
         (pending_order==0 && HistoryDealGetInteger(d,DEAL_TIME)>=pending_since)) { filled=true; break; }
   }
   if(filled) { Consume(); ClearPending(); return; }
   if(pending_order>0 && HistoryOrderSelect(pending_order))
   {
      ENUM_ORDER_STATE state=(ENUM_ORDER_STATE)HistoryOrderGetInteger(pending_order,ORDER_STATE);
      if(state==ORDER_STATE_FILLED) { Consume(); ClearPending(); }
      else if(state==ORDER_STATE_CANCELED || state==ORDER_STATE_REJECTED || state==ORDER_STATE_EXPIRED)
      {
         if(HistoryOrderGetDouble(pending_order,ORDER_VOLUME_CURRENT)<HistoryOrderGetDouble(pending_order,ORDER_VOLUME_INITIAL)-1e-10) Consume();
         ClearPending();
      }
   }
   // An unknown outcome with no broker evidence remains locked, including across restarts.
}
bool ReadRSI()
{
   for(int i=0;i<4;i++)
   {
      double value[1];
      if(handles[i]==INVALID_HANDLE || BarsCalculated(handles[i])<15 || CopyBuffer(handles[i],0,0,1,value)!=1 ||
         !MathIsValidNumber(value[0]) || value[0]==EMPTY_VALUE || value[0]<0 || value[0]>100) return false;
      rsi[i]=value[0];
   }
   return true;
}
SIGNAL_STATE RearmedState(const SIGNAL_STATE current,const double main_rsi,const double level)
{
   return main_rsi>level?ARMED:current;
}
// Pure extremum selector: chronological input, earliest ties, no guessed intra-minute order.
bool FindExtrema(const MqlRates &rates[],const datetime start,const datetime now,int &high,int &low)
{
   high=-1; low=-1;
   for(int i=0;i<ArraySize(rates);i++)
   {
      if(rates[i].time<start || rates[i].time>now) continue;
      if(high<0 || rates[i].high>rates[high].high) high=i;
      if(low<0 || rates[i].low<rates[low].low) low=i;
   }
   return high>=0 && low>=0 && high!=low && rates[high].high>rates[low].low;
}
double SelectedVolume()
{
   if(!ready || !(rsi[0]<RSI_Entry_Level && rsi[1]<RSI_Confirmation_Level)) return 0;
   if(rsi[2]<RSI_Confirmation_Level) return rsi[3]<RSI_Confirmation_Level?Vol3:Vol2;
   return Vol;
}
bool VolumeValid(const double volume,string &reason)
{
   double minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN), maximum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(!MathIsValidNumber(volume) || step<=0 || volume<minimum-1e-10 || volume>maximum+1e-10 || MathAbs(volume/step-MathRound(volume/step))>1e-7)
   { reason="Unsupported requested volume "+DoubleToString(volume,8); return false; }
   double limit=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_LIMIT), total=0;
   if(limit>0)
   {
      for(int i=PositionsTotal()-1;i>=0;i--)
         if(PositionGetTicket(i)>0 && PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) total+=PositionGetDouble(POSITION_VOLUME);
      for(int i=OrdersTotal()-1;i>=0;i--)
         if(OrderGetTicket(i)>0 && OrderGetString(ORDER_SYMBOL)==_Symbol)
         {
            ENUM_ORDER_TYPE t=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            if(t==ORDER_TYPE_BUY || t==ORDER_TYPE_BUY_LIMIT || t==ORDER_TYPE_BUY_STOP || t==ORDER_TYPE_BUY_STOP_LIMIT) total+=OrderGetDouble(ORDER_VOLUME_CURRENT);
         }
      if(total+volume>limit+1e-10) { reason="Symbol directional volume limit exceeded"; return false; }
   }
   return true;
}
bool Profit(const double volume,const double open,const double close,double &profit)
{
   return close>0 && OrderCalcProfit(ORDER_TYPE_BUY,_Symbol,volume,open,close,profit) && MathIsValidNumber(profit);
}
// Bracket, bisect, then compare adjacent ticks. No stop-distance clamping or volume adjustment.
bool MoneyPrice(const double volume,const double open,const double target,double &price,double &estimated)
{
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   if(tick<=0 || open<=tick) return false;
   double distance=tick, edge=open, profit=0;
   bool found=false;
   for(int i=0;i<80;i++)
   {
      edge=target>0?open+distance:MathMax(tick,open-distance);
      if(!Profit(volume,open,edge,profit)) return false;
      if((target>0 && profit>=target) || (target<0 && profit<=target)) { found=true; break; }
      if(target<0 && edge<=tick) return false;
      distance*=2;
   }
   if(!found) return false;
   double lo=MathMin(open,edge), hi=MathMax(open,edge);
   for(int i=0;i<80;i++)
   {
      double mid=(lo+hi)/2;
      if(!Profit(volume,open,mid,profit)) return false;
      if(profit<target) lo=mid; else hi=mid;
   }
   double root=(lo+hi)/2;
   double p1=NormalizeDouble(MathFloor(root/tick)*tick,digits), p2=NormalizeDouble(MathCeil(root/tick)*tick,digits);
   double v1=0,v2=0;
   bool a=Profit(volume,open,p1,v1), b=Profit(volume,open,p2,v2);
   if(!a && !b) return false;
   if(a && (!b || MathAbs(v1-target)<=MathAbs(v2-target))) { price=p1; estimated=v1; }
   else { price=p2; estimated=v2; }
   return target>0?price>open && estimated>0:price<open && estimated<0;
}
bool BuildRequest(const double volume,MqlTradeRequest &request,double &tp_money,double &sl_money,string &reason)
{
   if(!VolumeValid(volume,reason)) return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
   { reason="Trading disabled by terminal, EA, or account permissions"; return false; }
   ENUM_SYMBOL_TRADE_MODE mode=(ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
   long orders=SymbolInfoInteger(_Symbol,SYMBOL_ORDER_MODE);
   if((mode!=SYMBOL_TRADE_MODE_FULL && mode!=SYMBOL_TRADE_MODE_LONGONLY) || (orders & SYMBOL_ORDER_MARKET)==0 || (orders & SYMBOL_ORDER_SL)==0 || (orders & SYMBOL_ORDER_TP)==0)
   { reason="Symbol does not allow protected market BUY orders"; return false; }
   MqlTick quote;
   if(!SymbolInfoTick(_Symbol,quote) || quote.ask<=0 || quote.bid<=0 || quote.ask<quote.bid) { reason="Price data unavailable"; return false; }
   double tp=0,sl=0;
   if(!MoneyPrice(volume,quote.ask,Take_Profit,tp,tp_money) || !MoneyPrice(volume,quote.ask,-Stop_Loss,sl,sl_money))
   { reason="Failed monetary TP/SL calculation"; return false; }
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double stops=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*point;
   // Freeze level applies to later modifications/cancellations; no stop modifications are made.
   if(point<=0 || sl>=quote.bid || tp<=quote.bid || quote.bid-sl+point*1e-6<stops || tp-quote.bid+point*1e-6<stops)
   { reason=StringFormat("Invalid stop distance: bid=%.*f SL=%.*f TP=%.*f minimum=%g; targets left unchanged",_Digits,quote.bid,_Digits,sl,_Digits,tp,stops); return false; }
   request.action=TRADE_ACTION_DEAL; request.symbol=_Symbol; request.magic=Magic_Number;
   request.type=ORDER_TYPE_BUY; request.volume=volume; request.price=quote.ask;
   request.sl=sl; request.tp=tp; request.deviation=Max_Slippage_Points; request.comment="RSI Pull Up";
   long filling=SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK)!=0) request.type_filling=ORDER_FILLING_FOK;
   else if((filling & SYMBOL_FILLING_IOC)!=0) request.type_filling=ORDER_FILLING_IOC;
   else if(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_EXEMODE)!=SYMBOL_TRADE_EXECUTION_MARKET) request.type_filling=ORDER_FILLING_RETURN;
   else { reason="No supported market filling policy"; return false; }
   double margin=0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY,_Symbol,volume,quote.ask,margin)) { reason="Margin calculation failed"; return false; }
   if(margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)) { reason="Insufficient free margin"; return false; }
   MqlTradeCheckResult check={};
   if(!OrderCheck(request,check) || (check.retcode!=0 && check.retcode!=TRADE_RETCODE_DONE))
   { reason=StringFormat("OrderCheck rejected: %u %s (error %d)",check.retcode,check.comment,GetLastError()); return false; }
   return true;
}
void CancelRemainder(const ulong ticket)
{
   if(ticket==0 || !OrderSelect(ticket)) return;
   if(last_cancel_try!=0 && TimeCurrent()-last_cancel_try<5) return;
   last_cancel_try=TimeCurrent();
   MqlTradeRequest cancel={}; MqlTradeResult result={};
   cancel.action=TRADE_ACTION_REMOVE; cancel.order=ticket; cancel.symbol=_Symbol; cancel.magic=Magic_Number;
   // IOC/FOK are preferred. For RETURN partial fills, remove the unfilled remainder.
   // Broker freeze restrictions are respected by the server; failed cancellation stays locked.
   if(!OrderSend(cancel,result) || result.retcode!=TRADE_RETCODE_DONE)
      Log(StringFormat("Remainder cancellation unresolved: order=%I64u retcode=%u %s",ticket,result.retcode,result.comment));
}
void AttemptBuy(const double volume)
{
   MqlTradeRequest request={}; MqlTradeResult result={};
   double tp_money=0,sl_money=0; string reason="";
   attempted_bar=iTime(_Symbol,_Period,0);
   if(attempted_bar==0) { Status("Chart bar history unavailable"); return; }
   if(!Save()) return;
   bool valid=BuildRequest(volume,request,tp_money,sl_money,reason);
   Log(StringFormat("ATTEMPT RSI=[%.5f,%.5f,%.5f,%.5f] conf=[%s,%s,%s] lots=%.8f ask=%.*f TP=%.*f SL=%.*f estimated=[%.4f,%.4f] %s magic=%I64u validation=%s",
      rsi[0],rsi[1],rsi[2],rsi[3],rsi[1]<RSI_Confirmation_Level?"true":"false",rsi[2]<RSI_Confirmation_Level?"true":"false",rsi[3]<RSI_Confirmation_Level?"true":"false",
      volume,_Digits,request.price,_Digits,request.tp,_Digits,request.sl,tp_money,sl_money,currency,Magic_Number,valid?"OK":reason));
   if(!valid) { Status(reason); return; }
   if(PositionBlocks()) { Consume(); Status("Existing position appeared before submission; signal consumed"); return; }
   // Write intent BEFORE submission. A crash in the send window must never reset to armed.
   pending=true; pending_since=TimeCurrent(); pending_order=0;
   if(!Save()) { Status("Persistence failed; order not submitted"); return; }
   bool sent=OrderSend(request,result);
   pending_order=result.order; Save();
   Log(StringFormat("RESULT sent=%s retcode=%u order=%I64u deal=%I64u filled_volume=%.8f fill=%.*f comment=%s error=%d",
      sent?"true":"false",result.retcode,result.order,result.deal,result.volume,_Digits,result.price,result.comment,GetLastError()));
   if(result.retcode==TRADE_RETCODE_DONE || result.retcode==TRADE_RETCODE_DONE_PARTIAL || result.deal>0)
   {
      Consume();
      if(result.retcode==TRADE_RETCODE_DONE_PARTIAL) CancelRemainder(result.order);
      Reconcile();
      Status("Entry executed; signal consumed");
   }
   else if(result.retcode==TRADE_RETCODE_PLACED) Status("Order accepted; execution pending");
   else if(result.retcode==TRADE_RETCODE_TIMEOUT || result.retcode==TRADE_RETCODE_CONNECTION || result.retcode==0 || result.retcode==TRADE_RETCODE_LOCKED)
      Status("Execution outcome unresolved; new requests locked pending broker evidence");
   else { ClearPending(); Status(StringFormat("Order rejected: %u %s; retry no earlier than next chart bar",result.retcode,result.comment)); }
}

bool SetInt(const string name,const ENUM_OBJECT_PROPERTY_INTEGER property,const long value)
{
   if(ObjectGetInteger(0,name,property)==value) return true;
   return ObjectSetInteger(0,name,property,value);
}
void Label(const string name,const string text,const int x,const int y,const color background,const int width,const int height)
{
   string box=name+".bg";
   if(ObjectFind(0,box)<0) ObjectCreate(0,box,OBJ_RECTANGLE_LABEL,0,0,0);
   SetInt(box,OBJPROP_CORNER,CORNER_LEFT_UPPER); SetInt(box,OBJPROP_XDISTANCE,x); SetInt(box,OBJPROP_YDISTANCE,y);
   SetInt(box,OBJPROP_XSIZE,width); SetInt(box,OBJPROP_YSIZE,height); SetInt(box,OBJPROP_BGCOLOR,background);
   SetInt(box,OBJPROP_COLOR,background); SetInt(box,OBJPROP_SELECTABLE,false); SetInt(box,OBJPROP_HIDDEN,true);
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   SetInt(name,OBJPROP_CORNER,CORNER_LEFT_UPPER); SetInt(name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   SetInt(name,OBJPROP_XDISTANCE,x+7); SetInt(name,OBJPROP_YDISTANCE,y+3);
   SetInt(name,OBJPROP_FONTSIZE,Monitor_Font_Size); SetInt(name,OBJPROP_COLOR,Monitor_Text_Color);
   SetInt(name,OBJPROP_SELECTABLE,false); SetInt(name,OBJPROP_HIDDEN,true);
   if(ObjectGetString(0,name,OBJPROP_TEXT)!=text) ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
}
void Monitor()
{
   if(!timeframe_ok)
      Label(prefix+"warning","INVALID TIMEFRAMES: chart < RSI1 < RSI2 < RSI3 required",10,20,clrMaroon,660,30);
   if(!Show_RSI_Monitor) return;
   int row=Monitor_Font_Size*2+8, width=420, count=9;
   int cw=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS), ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   bool right=Monitor_Position==RIGHT_MIDDLE || Monitor_Position==RIGHT_TOP;
   bool middle=Monitor_Position==RIGHT_MIDDLE || Monitor_Position==LEFT_MIDDLE;
   int x=right?cw-width-Monitor_X_Offset:Monitor_X_Offset;
   int y=(middle?(ch-count*row)/2:0)+Monitor_Y_Offset;
   x=MathMax(0,x); y=MathMax(0,y);
   Label(prefix+"row0","RSI Pull Up | "+currency,x,y,Monitor_Background_Color,width,row);
   ENUM_TIMEFRAMES tf[4]; tf[0]=_Period; tf[1]=RSI1_Timeframe; tf[2]=RSI2_Timeframe; tf[3]=RSI3_Timeframe;
   for(int i=0;i<4;i++)
   {
      double level=i==0?RSI_Entry_Level:RSI_Confirmation_Level;
      string title=i==0?"Main RSI":"RSI"+IntegerToString(i);
      string value=ready?DoubleToString(rsi[i],2):"waiting";
      Label(prefix+"row"+IntegerToString(i+1),title+" ("+EnumToString(tf[i])+"): "+value,x,y+(i+1)*row,
         ready && rsi[i]<level?Confirmation_Background_Color:Monitor_Background_Color,width,row);
   }
   Label(prefix+"row5","Signal: "+(signal_state==ARMED?"ARMED":"CONSUMED")+(pending?" | IN FLIGHT":""),x,y+5*row,Monitor_Background_Color,width,row);
   double volume=SelectedVolume();
   Label(prefix+"row6","Entry volume: "+(volume>0?DoubleToString(volume,8):"no valid signal"),x,y+6*row,Monitor_Background_Color,width,row);
   Label(prefix+"row7","Position: "+(PositionBlocks()?"OPEN":"NONE"),x,y+7*row,Monitor_Background_Color,width,row);
   string compact=StringLen(status_text)>46?StringSubstr(status_text,0,43)+"...":status_text;
   Label(prefix+"row8",compact,x,y+8*row,Monitor_Background_Color,width,row);
   ObjectSetString(0,prefix+"row8",OBJPROP_TOOLTIP,status_text);
}
void Fibonacci()
{
   if(!Show_Fibonacci) return;
   datetime now=TimeCurrent();
   MqlRates current[1];
   bool available=CopyRates(_Symbol,PERIOD_M1,0,1,current)==1;
   // Read the actual M1 high/low, including on exchange symbols whose bars use Last.
   // Full-window scans occur once per server second or on any intrabar extremum change.
   if(available && now==fib_checked && current[0].time==last_m1_time && current[0].high==last_m1_high && current[0].low==last_m1_low) return;
   fib_checked=now;
   if(available) { last_m1_time=current[0].time; last_m1_high=current[0].high; last_m1_low=current[0].low; }
   MqlRates rates[];
   datetime start=(datetime)((long)now-(long)Fibonacci_Lookback_Hours*3600);
   int copied=CopyRates(_Symbol,PERIOD_M1,start,now,rates);
   string name=prefix+"fibo";
   if(copied<2) { ObjectDelete(0,name); FibStatus("Insufficient M1 Fibonacci history; trading remains independent"); return; }
   int high=-1,low=-1;
   if(!FindExtrema(rates,start,now,high,low))
   { ObjectDelete(0,name); FibStatus("Fibonacci omitted: extrema chronology is ambiguous or range unavailable"); return; }
   FibStatus("");
   fib_high=rates[high].high; fib_low=rates[low].low;
   datetime t0=rates[low].time<rates[high].time?rates[low].time:rates[high].time;
   datetime t1=rates[low].time<rates[high].time?rates[high].time:rates[low].time;
   double p0=rates[low].time<rates[high].time?fib_low:fib_high;
   double p1=rates[low].time<rates[high].time?fib_high:fib_low;
   bool create=ObjectFind(0,name)<0;
   if(create)
   {
      if(!ObjectCreate(0,name,OBJ_FIBO,0,t0,p0,t1,p1)) { Log("Fibonacci object creation failed"); return; }
      double levels[7]={0,0.236,0.382,0.5,0.618,0.786,1};
      ObjectSetInteger(0,name,OBJPROP_LEVELS,7);
      for(int i=0;i<7;i++)
      {
         // MT5 OBJ_FIBO measures level 0 at the SECOND coordinate. Reverse the
         // internal coefficient so the displayed 0% is the first chronological anchor.
         ObjectSetDouble(0,name,OBJPROP_LEVELVALUE,i,1.0-levels[i]);
         ObjectSetString(0,name,OBJPROP_LEVELTEXT,i,DoubleToString(levels[i]*100,1)+"%");
         ObjectSetInteger(0,name,OBJPROP_LEVELCOLOR,i,Fibonacci_Color);
      }
      ObjectSetInteger(0,name,OBJPROP_COLOR,Fibonacci_Color);
      ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   }
   if(create || t0!=fib_t0 || t1!=fib_t1 || p0!=fib_p0 || p1!=fib_p1)
   {
      if(!ObjectMove(0,name,0,t0,p0) || !ObjectMove(0,name,1,t1,p1)) Log("Fibonacci anchor update failed");
      fib_t0=t0; fib_t1=t1; fib_p0=p0; fib_p1=p1;
   }
}
int OnInit()
{
   ArrayInitialize(handles,INVALID_HANDLE);
   if(!MathIsValidNumber(RSI_Entry_Level) || !MathIsValidNumber(RSI_Confirmation_Level) || RSI_Entry_Level<0 || RSI_Entry_Level>100 || RSI_Confirmation_Level<0 || RSI_Confirmation_Level>100 ||
      !MathIsValidNumber(Take_Profit) || !MathIsValidNumber(Stop_Loss) || Take_Profit<=0 || Stop_Loss<=0 ||
      !MathIsValidNumber(Vol) || !MathIsValidNumber(Vol2) || !MathIsValidNumber(Vol3) || Vol<=0 || Vol2<=0 || Vol3<=0 ||
      Fibonacci_Lookback_Hours<=0 || Fibonacci_Lookback_Hours>87600 || Monitor_Font_Size<6 || Monitor_Font_Size>40)
   { Log("Invalid numeric input settings"); return INIT_PARAMETERS_INCORRECT; }
   currency=AccountInfoString(ACCOUNT_CURRENCY);
   key=Scope(); prefix=key+"."+(string)ChartID()+".";
   if(!AcquireInstance()) return INIT_FAILED;
   // Tester runs start independently; live terminal state survives EA/terminal restarts.
   // Terminal tester globals belong to the test agent, never the live terminal namespace.
   bool recovered=!MQLInfoInteger(MQL_TESTER) && GlobalVariableCheck(key+".state");
   if(recovered)
   {
      signal_state=GlobalVariableGet(key+".state")==0?ARMED:CONSUMED;
      attempted_bar=(datetime)GlobalVariableGet(key+".bar");
      pending=GlobalVariableGet(key+".pending")!=0;
      pending_since=(datetime)GlobalVariableGet(key+".since");
      pending_order=((ulong)GlobalVariableGet(key+".orderHi")<<32)|(ulong)GlobalVariableGet(key+".orderLo");
   }
   // A genuine first attachment is armed, unless an owned position already proves entry.
   if(OwnedPosition()) signal_state=CONSUMED;
   if(!Save()) return INIT_FAILED;
   Reconcile();
   timeframe_ok=PeriodSeconds(_Period)>0 && PeriodSeconds(_Period)<PeriodSeconds(RSI1_Timeframe) &&
      PeriodSeconds(RSI1_Timeframe)<PeriodSeconds(RSI2_Timeframe) && PeriodSeconds(RSI2_Timeframe)<PeriodSeconds(RSI3_Timeframe);
   ENUM_TIMEFRAMES tf[4]; tf[0]=_Period; tf[1]=RSI1_Timeframe; tf[2]=RSI2_Timeframe; tf[3]=RSI3_Timeframe;
   for(int i=0;i<4;i++)
   {
      handles[i]=iRSI(_Symbol,tf[i],14,PRICE_CLOSE);
      if(handles[i]==INVALID_HANDLE) Log("Indicator not initialized: "+EnumToString(tf[i]));
   }
   Log("Persistence scope: "+key+" | account currency: "+currency);
   Status(!timeframe_ok?"INVALID TIMEFRAMES: new entries disabled":(recovered?"Recovered persisted signal state":"First attachment: immediate signal allowed"));
   if(!EventSetTimer(1)) Log("UI timer unavailable; tick updates remain active");
   Monitor();
   return INIT_SUCCEEDED;
}
void OnTick()
{
   Reconcile();
   ready=ReadRSI();
   if(!ready) Status("Indicator/history not ready; entries disabled");
   else
   {
      SIGNAL_STATE next=RearmedState(signal_state,rsi[0],RSI_Entry_Level);
      if(next!=signal_state) { signal_state=next; Save(); }
      double volume=SelectedVolume();
      if(!timeframe_ok) Status("INVALID TIMEFRAMES: new entries disabled");
      else if(volume>0 && signal_state==ARMED && PositionBlocks())
      { Consume(); Status("Existing position blocks entry; signal consumed"); }
      else if(pending) Status("Execution pending/unresolved; new requests locked");
      else if(!Enable_Trading) Status("Trading disabled by Enable Trading input");
      else if(signal_state==CONSUMED) Status("Signal consumed; waiting for RSI0 > entry level");
      else if(volume>0)
      {
         datetime bar=iTime(_Symbol,_Period,0);
         if(bar>0 && bar!=attempted_bar) AttemptBuy(volume);
      }
      else Status("Armed; waiting for RSI0 and RSI1 confirmation");
   }
   Fibonacci(); Monitor();
}
void OnTimer()
{
   // Access keeps live state globals alive while the EA runs (terminal expiry is 4 weeks).
   if(key!="" && GlobalVariableCheck(key+".state")) { double keep_alive=GlobalVariableGet(key+".state"); }
   Fibonacci(); Monitor();
}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id==CHARTEVENT_CHART_CHANGE) Monitor();
}
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD && trans.deal>0 && HistoryDealSelect(trans.deal))
   {
      if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)==_Symbol && (ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)==Magic_Number &&
         HistoryDealGetInteger(trans.deal,DEAL_TYPE)==DEAL_TYPE_BUY && HistoryDealGetInteger(trans.deal,DEAL_ENTRY)==DEAL_ENTRY_IN)
      {
         Consume();
         Log(StringFormat("EXECUTED deal=%I64u order=%I64u price=%.*f volume=%.8f",trans.deal,trans.order,_Digits,
            HistoryDealGetDouble(trans.deal,DEAL_PRICE),HistoryDealGetDouble(trans.deal,DEAL_VOLUME)));
         CancelRemainder(trans.order);
      }
   }
   Reconcile(); Monitor();
}
void OnDeinit(const int reason)
{
   EventKillTimer();
   for(int i=0;i<4;i++) if(handles[i]!=INVALID_HANDLE) IndicatorRelease(handles[i]);
   if(prefix!="") ObjectsDeleteAll(0,prefix);
   if(owns_instance_lock)
   {
      if(!GlobalVariableSetOnCondition(key+".instance",0,(double)ChartID())) Log("Could not release instance guard");
   }
   // Do NOT erase live Global Variables: they are the restart-safety record.
}
