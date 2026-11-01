#!/usr/bin/env python3
"""Exercise the production submission function with explicit broker API stubs.
No MT5 execution or financial API calculation is simulated as evidence of native safety.
Runs the existing pure suite first, then checks candidate/rejection control flow.
"""
import pathlib, runpy, subprocess, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[2]
base=runpy.run_path(str(ROOT/'tests/ktr/run_portable.py'))
source=(ROOT/'Include/KTR/Execution.mqh').read_text()
submission=source[source.index('void KTRSubmitCandidates('):source.rindex('#endif')]
shim=base['shim']
# Capture real production log formats, including actual diagnostic amounts.
shim=shim.replace('void Print(const string& a,const string& b) { std::cout<<a<<b<<"\\n"; }',r'''
std::vector<string> logs;
void Print(const string& a) { logs.push_back(a); }
void Print(const string& a,const string& b) { logs.push_back(a+b); }
const char* FormatArg(const string& x) { return x.c_str(); }
template<class T> T FormatArg(T x) { return x; }
template<class... A> void PrintFormat(const char* fmt,A... args) {
 char output[8192]; std::snprintf(output,sizeof(output),fmt,FormatArg(args)...); logs.push_back(output);
}
''')
stubs=r'''
struct KTRMarket {};
struct MqlTradeRequest { double volume=0; string comment; };
struct KTRPlan { MqlTradeRequest request; double loss=0; double margin=0; double budget=0; int dir=0; };
struct KTRIntent { bool busy=false; };
KTRIntent ktr_intent[2]; KTREpisode ktr_episode[2];
KTR_DIRECTION Trade_Direction=TRADE_BOTH;
bool ktr_daily_lock=false,ktr_liquidating=false,ktr_baseline_estimated=false;
double ktr_day_balance=10000,Max_Daily_Risk_Percent=5;
ulong Magic_Number=471001;
enum { ACCOUNT_EQUITY,ACCOUNT_MARGIN_FREE,ACCOUNT_CURRENCY,POSITION_COMMENT,POSITION_MAGIC };
double equity=10000,free_margin=10000,open_loss_value=100;
bool exposure_known=true,confirm[2]={true,true},prepare[2]={true,true};
double plan_loss[2]={200,200},plan_margin[2]={100,100};
int account_reads=0,prepare_calls=0,exposure_calls=0,sends=0;
int KTRIndex(int dir) { return dir>0?0:1; }
double AccountInfoDouble(int prop) { account_reads++; return prop==ACCOUNT_EQUITY?equity:free_margin; }
string AccountInfoString(int) { return "USD"; }
bool KTRConfirm(KTRMarket&,KTRMarket&,int dir,bool) { return confirm[KTRIndex(dir)]; }
bool KTRPrepare(KTRMarket&,int dir,bool,datetime,int,int,KTRPlan& plan) {
 prepare_calls++; int i=KTRIndex(dir); if(!prepare[i]) return false;
 plan.dir=dir; plan.loss=plan_loss[i]; plan.margin=plan_margin[i]; plan.request.volume=.1;
 plan.request.comment=dir>0?"buy":"sell"; return true;
}
bool KTROpenLoss(double& loss) { exposure_calls++; loss=open_loss_value; return exposure_known; }
bool KTRSend(KTRPlan& plan) { sends++; ktr_intent[KTRIndex(plan.dir)].busy=true; return true; }
int PositionsTotal() { return 0; }
ulong PositionGetTicket(int) { return 0; }
string PositionGetString(int) { return ""; }
long PositionGetInteger(int) { return 0; }
bool KTRRefreshRecords() { return true; }
void KTRReconcileIntents() {}
void KTRReconcileEpisodes(bool) {}
void Reset() {
 logs.clear(); account_reads=0;prepare_calls=0;exposure_calls=0;sends=0;
 equity=10000;free_margin=10000;open_loss_value=100;exposure_known=true;
 ktr_day_balance=10000;ktr_daily_lock=false;ktr_liquidating=false;ktr_baseline_estimated=false;
 for(int i=0;i<2;i++) { ktr_intent[i].busy=false;ktr_episode[i].state=IDLE;
 confirm[i]=true;prepare[i]=true;plan_loss[i]=200;plan_margin[i]=100; }
}
int pass=0,fail=0;
void Check(bool ok,const string& name) { std::cout<<(ok?"PASS ":"FAIL ")<<name<<"\n"; if(ok)pass++;else fail++; }
bool LogHas(const string& text) { for(auto& line:logs) if(line.find(text)!=string::npos)return true;return false; }
'''
cases=r'''
void Submit(bool b,bool s) { KTRMarket m,h;KTRSubmitCandidates(m,h,b,s,true,123,123,1,1,3600); }
int main() {
 Reset();ktr_day_balance=0;Submit(false,false);
 Check(logs.empty()&&account_reads==0&&exposure_calls==0&&sends==0,"no signal + zero baseline: no invented capacity rejection");
 Reset();prepare[0]=false;ktr_day_balance=0;Submit(true,false);
 Check(logs.empty()&&exposure_calls==0&&account_reads==0&&sends==0,"failed preparation: no capacity assessment");
 Reset();confirm[0]=false;Submit(true,false);
 Check(logs.empty()&&prepare_calls==0&&exposure_calls==0&&sends==0,"failed confirmation: no capacity assessment");
 Reset();ktr_day_balance=0;ktr_baseline_estimated=true;Submit(true,false);
 Check(sends==0&&LogHas("nonpositive daily opening balance")&&LogHas("B_day=0.00")&&LogHas("baseline_estimated=true"),"genuine candidate + zero baseline: explicit baseline diagnostic");
 Reset();equity=9700;Submit(true,false);
 Check(sends==0&&LogHas("Daily-risk rejection")&&LogHas("projected_worst_equity=9400.00")&&LogHas("required_equity=9500.00")&&LogHas("projected_risk=6.0000%"),"daily risk rejection: current deficit and stop loss printed accurately");
 Reset();free_margin=50;Submit(true,false);
 Check(sends==0&&LogHas("Margin rejection")&&LogHas("required_margin=100.00")&&LogHas("free_margin=50.00")&&!LogHas("Daily-risk rejection"),"margin failure is distinguished from daily risk");
 Reset();open_loss_value=200;Submit(true,true);
 Check(sends==0&&LogHas("proposed_loss=400.00")&&LogHas("Daily-risk rejection"),"combined first-entry risk fails: neither direction sent");
 Reset();Submit(true,false);
 Check(sends==1&&!LogHas("rejection"),"eligible single candidate still submitted");
 Reset();Submit(true,true);
 Check(sends==2&&!LogHas("rejection"),"joint candidates at daily boundary retain unresolved-first reservation");
 Reset();exposure_known=false;Submit(true,false);
 Check(sends==0&&LogHas("existing account exposure cannot be assessed"),"unassessable exposure has an explicit blocker");
 Reset();ktr_episode[0].state=ACTIVE;ktr_day_balance=0;Submit(true,false);
 Check(logs.empty()&&exposure_calls==0&&account_reads==0&&sends==0,"active episode's ignored first signal does not create capacity warning");
 std::cout<<"KTR stubbed submission: "<<pass<<" passed, "<<fail<<" failed\n";
 return fail?1:0;
}
'''
with tempfile.TemporaryDirectory(prefix='ktr-submission-') as tmp:
    cpp=pathlib.Path(tmp)/'submission.cpp';exe=pathlib.Path(tmp)/'submission'
    cpp.write_text(shim+base['adapt']((ROOT/'Include/KTR/Core.mqh').read_text()+(ROOT/'Include/KTR/Recovery.mqh').read_text())+stubs+submission+cases)
    subprocess.run(['g++','-std=c++17','-Wall','-Wextra','-Werror',str(cpp),'-o',str(exe)],check=True)
    subprocess.run([str(exe)],check=True)
