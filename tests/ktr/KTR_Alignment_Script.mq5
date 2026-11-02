#property strict
#property script_show_inputs
#include "../../Include/KTR/Core.mqh"
#include "../../Include/KTR/Inputs.mqh"
#include "../../Include/KTR/Market.mqh"
// Nontrading terminal test: no OrderSend or production event handlers.
void OnStart()
{
   KTRMarket market;
   if(!market.Init(_Period)) { Print("FAIL: indicator handle"); return; }
   bool passed=false;
   for(int i=0;i<50 && !IsStopped();i++)
   {
      if(market.Load(300)) { passed=true; break; }
      Sleep(100);
   }
   Print(passed?"PASS: shifted CopyBuffer SSA/SSB and Tenkan/Kijun match independent OHLC on last 8 closed candles":"FAIL/UNREADY: buffer alignment or unavailable history");
   market.Release();
}
