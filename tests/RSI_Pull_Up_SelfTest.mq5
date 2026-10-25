// Test-only EA. Includes production functions, renames all production event handlers.
// Never calls production OnInit/OnTick or OrderSend. Run only in Strategy Tester.
#define OnInit ProductionOnInit
#define OnTick ProductionOnTick
#define OnTimer ProductionOnTimer
#define OnChartEvent ProductionOnChartEvent
#define OnTradeTransaction ProductionOnTradeTransaction
#define OnDeinit ProductionOnDeinit
#include "../RSI_Pull_Up.mq5"
#undef OnInit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
#undef OnDeinit
int passed=0,failed=0;
bool tested=false;
void Check(const bool condition,const string name)
{
   if(condition) { passed++; Print("PASS: ",name); }
   else { failed++; Print("FAIL: ",name); }
}
void RunTests()
{
   Check(RSILevel(0)==RSI_Entry_Level && RSILevel(1)==RSI1_Confirmation_Level &&
         RSILevel(2)==RSI2_Confirmation_Level && RSILevel(3)==RSI3_Confirmation_Level,"independent threshold mapping");
   ready=true;
   for(int mask=0;mask<16;mask++)
   {
      rsi[0]=RSI_Entry_Level+((mask & 1)!=0?-1:1);
      for(int i=1;i<4;i++) rsi[i]=RSILevel(i)+((mask & (1<<i))!=0?-1:1);
      double expected=0;
      if((mask & 3)==3) expected=(mask & 4)==0?Vol:((mask & 8)==0?Vol2:Vol3);
      Check(SelectedVolume()==expected,"confirmation combination "+IntegerToString(mask));
   }
   for(int i=0;i<4;i++) rsi[i]=0;
   rsi[0]=RSI_Entry_Level; Check(SelectedVolume()==0,"main equality forbids entry");
   rsi[0]=0; rsi[1]=RSI1_Confirmation_Level; Check(SelectedVolume()==0,"Conf1 equality forbids entry");
   rsi[1]=0; rsi[2]=RSI2_Confirmation_Level; Check(SelectedVolume()==Vol,"Conf2 equality selects Vol");
   rsi[2]=0; rsi[3]=RSI3_Confirmation_Level; Check(SelectedVolume()==Vol2,"Conf3 equality selects Vol2");
   ready=false; Check(SelectedVolume()==0,"unready RSI forbids entry");
   Check(RearmedState(CONSUMED,RSI_Entry_Level,RSI_Entry_Level)==CONSUMED,"equality cannot rearm");
   Check(RearmedState(CONSUMED,RSI_Entry_Level-1,RSI_Entry_Level)==CONSUMED,"oversold remains consumed");
   Check(RearmedState(CONSUMED,RSI_Entry_Level+1,RSI_Entry_Level)==ARMED,"strict rise rearms");
   Check(RearmedState(ARMED,RSI_Entry_Level-1,RSI_Entry_Level)==ARMED,"first-attachment armed state preserved");
   MqlRates bars[4]; ZeroMemory(bars);
   for(int i=0;i<4;i++) { bars[i].time=(datetime)(1000+i*60); bars[i].high=10; bars[i].low=5; }
   bars[0].low=1; bars[1].high=20; bars[2].low=1; bars[3].high=20;
   int high,low;
   Check(FindExtrema(bars,1000,1180,high,low) && low==0 && high==1,"earliest tied extrema");
   Check(FindExtrema(bars,1060,1180,high,low) && high==1 && low==2,"rolling window evicts old extreme");
   bars[2].high=30;
   Check(!FindExtrema(bars,1060,1180,high,low),"same-bar extrema ordering is ambiguous");
   Check(!FindExtrema(bars,2000,2100,high,low),"empty elapsed window");
   string reason;
   Check(!VolumeValid(-1,reason),"negative volume rejected");
   Check(!VolumeValid(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX)+SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),reason),"oversize volume rejected");
   MqlTick quote;
   bool quoted=SymbolInfoTick(_Symbol,quote) && quote.ask>0;
   Check(quoted,"symbol quote available for monetary integration tests");
   if(quoted)
   {
      double targets[2]; targets[0]=Take_Profit; targets[1]=-Stop_Loss;
      double lot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN), tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      for(int i=0;i<2;i++)
      {
         double price=0,profit=0;
         bool solved=MoneyPrice(lot,quote.ask,targets[i],price,profit);
         Check(solved,"monetary solve "+IntegerToString(i));
         if(!solved) continue;
         Check(MathAbs(price/tick-MathRound(price/tick))<1e-6,"price on tick grid");
         Check(i==0?price>quote.ask:price<quote.ask,"correct protective price direction");
         double below,above;
         bool b=Profit(lot,quote.ask,price-tick,below), a=Profit(lot,quote.ask,price+tick,above);
         double error=MathAbs(profit-targets[i]);
         Check((!b || error<=MathAbs(below-targets[i])+1e-7) && (!a || error<=MathAbs(above-targets[i])+1e-7),"chosen tick minimizes adjacent monetary error");
      }
   }
   PrintFormat("SELFTEST RESULT: passed=%d failed=%d",passed,failed);
}
int OnInit()
{
   if(!MQLInfoInteger(MQL_TESTER)) { Print("Run this test EA in Strategy Tester only."); return INIT_FAILED; }
   return INIT_SUCCEEDED;
}
void OnTick()
{
   if(tested) return;
   tested=true; RunTests(); ExpertRemove();
}
