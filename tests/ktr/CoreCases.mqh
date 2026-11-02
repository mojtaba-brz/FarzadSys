#ifndef KTR_CORE_CASES_MQH
#define KTR_CORE_CASES_MQH
int ktr_pass=0,ktr_fail=0;
void KTRAssert(const bool condition,const string name)
{
   if(condition) { ktr_pass++; Print("PASS ",name); }
   else { ktr_fail++; Print("FAIL ",name); }
}
bool KTRNear(const double x,const double y) { return MathAbs(x-y)<1e-8; }
void KTRRunCoreCases()
{
   int last=0;
   KTRAssert(KTRTrendStep(1,last)==0 && last==1,"first known trend is not a reversal");
   KTRAssert(KTRTrendStep(0,last)==0 && last==1,"neutral preserves prior direction");
   KTRAssert(KTRTrendStep(-1,last)==-1,"opposite nonneutral reverses");
   KTRAssert(KTRTrendStep(-1,last)==0,"same direction not repeated");
   KTRAssert(KTRTrendStep(0,last)==0 && KTRTrendStep(1,last)==1,"neutral bridge reversal");
   KTRAssert(KTRSign(10,10)==0,"equal cloud neutral");
   KTRAssert(KTREpisodeState(0,false,false)==IDLE,"empty episode idle");
   KTRAssert(KTREpisodeState(3,true,false)==ACTIVE,"positive first remains active");
   KTRAssert(KTREpisodeState(2,false,false)==SUSPENDED,"first fully closed suspends additions");
   KTRAssert(KTREpisodeState(0,false,true)==CLOSING,"unresolved closing retains lock");
   KTRAssert(KTREpisodeState(1,true,false)==ACTIVE,"partial first closure remains active");
   double valley[]={5,4,3,2,1,2,3,4,5};
   double shifted[]={10,8,6,4,2,4,6,8,10};
   double peak[]={1,2,3,4,5,4,3,2,1};
   double flat[]={2,2,2,2,2,2,2,2,2};
   KTRAssert(KTRNear(KTRCosine(valley,shifted,0,0,9),1),"normalized scale invariant shape");
   KTRAssert(KTRNear(KTRCosine(valley,peak,0,0,9),-1),"opposite shape rejected");
   KTRAssert(KTRCosine(flat,flat,0,0,9)==-2,"degenerate vector rejected");
   KTRAssert(KTRCosine(valley,shifted,-1,0,3)==-2,"window bounds protected");
   KTRAssert(KTRNear(KTRAmplitude(valley,0,9),4),"amplitude range");
   KTRFeature a[],b[],p[];
   KTRFeatures(valley,2,2,0,a); KTRFeatures(shifted,2,2,0,b); KTRFeatures(peak,2,2,0,p);
   KTRAssert(ArraySize(a)==1 && a[0].kind==1,"valley feature");
   KTRAssert(ArraySize(p)==1 && p[0].kind==-1,"peak feature");
   KTRAssert(a[0].pivot==4 && a[0].confirmation==6,"right-candle causal confirmation");
   KTRAssert(KTRShapeMatch(valley,shifted,a[0],b[0],7,2,.9,.1),"matching confirmed valleys");
   KTRAssert(!KTRShapeMatch(valley,peak,a[0],p[0],7,2,.9,.1),"extremum types must match");
   KTRAssert(!KTRShapeMatch(valley,shifted,a[0],b[0],7,2,.9,10),"ATR movement floor rejects small shape");
   KTRAssert(KTRShapeMatch(peak,peak,p[0],p[0],7,2,.9,.1),"matching peaks pass");
   double delayed[]={99,10,8,6,4,2,4,6,8,10}; KTRFeature delayed_features[];
   KTRFeatures(delayed,2,2,0,delayed_features);
   KTRAssert(KTRShapeMatch(valley,delayed,a[0],delayed_features[0],7,2,.9,.1),"allowed one-bar lag aligns local differences");
   double sharp[]={5,5,5,5,1,5,5,5,5}; KTRFeature sharp_features[];
   KTRFeatures(sharp,2,2,0,sharp_features);
   KTRAssert(!KTRShapeMatch(valley,sharp,a[0],sharp_features[0],7,2,.9,.1),"same extremum with low shape similarity rejected");
   KTRFeature lag=b[0]; lag.pivot+=3;
   KTRAssert(!KTRShapeMatch(valley,shifted,a[0],lag,7,2,.9,.1),"excessive lag rejected");
   double plateau[]={5,4,3,2,2,2,3,4,5}; KTRFeature plateaus[];
   KTRFeatures(plateau,2,2,0,plateaus);
   KTRAssert(ArraySize(plateaus)==1,"one event per plateau");
   KTRAssert(plateaus[0].pivot==5 && plateaus[0].confirmation==7,"plateau last-bar canonical identity");
   double prefix[]={5,4,3,2,2,2,3}; KTRFeatures(prefix,2,2,0,p);
   KTRAssert(ArraySize(p)==0,"insufficient completed right bars produce no feature");
   double almost[]={5,4,3,2,2.001,2,3,4,5}; KTRFeatures(almost,2,2,.01,p);
   KTRAssert(ArraySize(p)==1,"approximate plateau tolerance");
   KTRAssert(KTRPullback(1,12,9.9,11,10,.1),"buy Kijun pullback");
   KTRAssert(KTRPullback(-1,10.1,8,9,10,.1),"sell Kijun pullback");
   KTRAssert(!KTRPullback(1,12,11,11.5,10,.1),"no invented touch");
   KTRAssert(!KTRPullback(1,12,9,10,10,.1),"close equal to level rejected");
   KTRAssert(KTRRejection(1,10.1,11,9,10.5,10,.2,1.5,.01),"bullish rejection wick");
   KTRAssert(KTRRejection(-1,9.9,11,9,9.5,10,.2,1.5,.01),"bearish rejection wick");
   KTRAssert(!KTRRejection(1,10,11,9,10,10,.2,1.5,.01),"doji rejection safe");
   KTRAssert(!KTRRejection(1,10,11.1,9.9,11,10,.2,1.5,.01),"pullback is not automatically rejection");
   KTRAssert(KTRCross(1,9,10,11,10),"bullish crossover");
   KTRAssert(KTRCross(-1,11,10,9,10),"bearish crossover");
   KTRAssert(KTRCross(1,10,10,11,10),"previous equality crosses");
   KTRAssert(!KTRCross(1,9,10,10,10),"current equality no crossover");
   KTRAssert(KTRNear(KTRReducedRisk(2,20,1),2),"base index one");
   KTRAssert(KTRNear(KTRReducedRisk(2,20,2),1.6),"first addition fixed reduction");
   KTRAssert(KTRNear(KTRReducedRisk(2,20,3),1.28),"geometric reduction");
   KTRAssert(KTRNear(KTRReducedRisk(2,100,2),0),"full reduction disables additions");
   int durations[]={3,5,7,10,20}; int eligible=0;
   KTRAssert(KTRNear(KTREndProbability(durations,5,5,eligible),2.0/3) && eligible==3,"conditional trend-end probability");
   KTRAssert(KTREndProbability(durations,30,5,eligible)==0 && eligible==0,"empty hazard sample fallback");
   KTRAssert(KTRNear(KTRFloorVolume(100,250,.01,.01,100),.4),"budget-based volume");
   KTRAssert(KTRNear(KTRFloorVolume(99,250,.01,.01,100),.39),"volume rounds down");
   KTRAssert(KTRFloorVolume(1,250,.01,.01,100)==0,"minimum volume never rounded up");
   KTRAssert(KTRNear(KTRFloorVolume(1000,100,.25,.25,1),1),"volume maximum respected");
   KTRAssert(KTRFloorVolume(100,250,0,.01,100)==0,"invalid volume step rejected");
   KTRAssert(KTRRiskFits(10000,10000,200,200,5),"four percent projected exposure allowed");
   KTRAssert(!KTRRiskFits(10000,9800,200,200,5),"existing equity deficit included");
   KTRAssert(KTRRiskFits(10000,10000,300,200,5),"exact daily cap allowed");
   KTRAssert(!KTRRiskFits(10000,10000,300,200.01,5),"cap breach rejected");
   KTRAssert(!KTRRiskFits(0,10000,0,0,5),"unknown baseline blocks entries");
   KTRAssert(KTRNear(KTRRoundStop(99.93,.1,1),99.9),"buy tick stop rounds outward");
   KTRAssert(KTRNear(KTRRoundStop(100.03,.1,-1),100.1),"sell tick stop rounds outward");
   double hi[]={3,4,6,5,4,3,2,3,4,5,6,7,6,5};
   double lo[]={2,3,5,4,3,2,1,2,3,4,5,6,5,4}; KTRSwing swings[];
   KTRZigZag(hi,lo,3,2,1,swings);
   KTRAssert(ArraySize(swings)>=2,"causal ZigZag major swings found");
   if(ArraySize(swings)>=2)
   {
      KTRAssert(swings[0].kind==-1 && swings[0].pivot==2 && swings[0].confirmation==4,"top confirmation delayed by Backstep");
      KTRAssert(swings[1].kind==1 && swings[1].pivot==6 && swings[1].confirmation==8,"valley confirmation delayed");
   }
   // Every chronological prefix must preserve each already confirmed historical swing.
   bool stable=true;
   for(int n=3;n<=ArraySize(hi);n++)
   {
      double h[],l[]; ArrayResize(h,n); ArrayResize(l,n);
      for(int i=0;i<n;i++) { h[i]=hi[i]; l[i]=lo[i]; }
      KTRSwing current[]; KTRZigZag(h,l,3,2,1,current);
      for(int i=0;i<ArraySize(current);i++)
         if(current[i].pivot!=swings[i].pivot || current[i].confirmation!=swings[i].confirmation || current[i].price!=swings[i].price) stable=false;
   }
   KTRAssert(stable,"confirmed ZigZag prefix invariance / no future mutation");
   // Mutating only data beyond an earlier feature confirmation must not alter that feature.
   double changed[]={5,4,3,2,1,2,3,999,1000}; KTRFeatures(changed,2,2,0,p);
   KTRAssert(ArraySize(p)>0 && p[0].pivot==4 && p[0].confirmation==6,"shape prefix invariant under future changes");
   KTRAssert(KTRAdditionCapAllows(1,3),"first position leaves three addition slots");
   KTRAssert(KTRAdditionCapAllows(3,3),"two executed additions allow the third");
   KTRAssert(!KTRAdditionCapAllows(4,3),"three filled additions reach lifetime cap");
   KTRAssert(!KTRAdditionCapAllows(10,3),"closed earlier additions do not replenish cap");
   KTRAssert(KTRAdditionCapAllows(100,0),"zero cap explicitly restores unlimited behavior");
   int previous=0;
   KTRAssert(KTRFreshAdditionalMask(16,previous,true)==16,"first pullback condition is fresh");
   KTRAssert(KTRFreshAdditionalMask(16,previous,true)==0,"continuing pullback cannot add each bar");
   KTRAssert(KTRFreshAdditionalMask(80,previous,true)==64,"new flat-SSB method independent of persistent pullback");
   KTRAssert(KTRFreshAdditionalMask(0,previous,true)==0 && KTRFreshAdditionalMask(16,previous,true)==16,"false condition rearms pullback");
   KTRAssert(KTRFreshAdditionalMask(16,previous,false)==16,"fresh-only input OFF restores condition behavior");
   KTRAssert(!KTRAdditionCooldownAllows(1,false,1),"09:29 fill cannot add at 09:30 M5 boundary");
   KTRAssert(KTRAdditionCooldownAllows(2,false,1),"09:29 fill may add after complete 09:30-09:35 candle");
   KTRAssert(KTRAdditionCooldownAllows(1,true,1),"fill at 09:25 opening completes one full candle at 09:30");
   KTRAssert(!KTRAdditionCooldownAllows(3,false,3) && KTRAdditionCooldownAllows(4,false,3),"multi-bar cooldown excludes partial fill candle");
   KTRAssert(KTRAdditionCooldownAllows(0,false,0),"zero cooldown disables delay");
   KTRAssert(!KTRAdditionCooldownAllows(-1,false,1),"missing fill-bar history blocks cooldown");
   KTRAssert(!KTRSessionContains(3660,3720,86340,false),"01:01 is before a 01:02 trading session");
   KTRAssert(KTRSessionContains(3720,3720,86340,false),"session beginning inclusive");
   KTRAssert(!KTRSessionContains(86340,3720,86340,false),"session end exclusive");
   KTRAssert(KTRSessionContains(23*3600,22*3600,2*3600,false),"overnight session same-day late segment");
   KTRAssert(KTRSessionContains(3600,22*3600,2*3600,true),"overnight session previous-day carry");
   KTRAssert(!KTRSessionContains(3600,22*3600,2*3600,false),"today's evening session cannot open this morning");
   KTRAssert(!KTRSessionContains(3*3600,22*3600,2*3600,true),"previous overnight session expired");
   KTRAssert(KTRSessionContains(100,0,0,false) && !KTRSessionContains(100,0,0,true),"full-day session belongs to current day only");
   KTRAssert(KTRNear(KTRDailyBalance(1000,1000,1000),1000),"verified tester initial deposit provides first-day starting baseline");
   KTRAssert(KTRNear(KTRDailyBalance(1220,1220,1000),1000),"later same-day deposit and trading result do not change initial tester baseline");
   KTRAssert(KTRNear(KTRDailyBalance(980,-20,0),1000),"subsequent server day reconstructs normal opening balance");
   KTRAssert(KTRDailyBalance(1000,1000,0)==0,"no verified initial tester funding cannot invent positive baseline");
   KTRAssert(KTRNear(KTRWorstEntry(4000,1,10,.01),4000.1),"BUY deviation reserves higher entry");
   KTRAssert(KTRNear(KTRWorstEntry(4000,-1,10,.01),3999.9),"SELL unsigned deviation reserves lower entry");
   PrintFormat("KTR core: %d passed, %d failed",ktr_pass,ktr_fail);
}
#endif
