#!/usr/bin/env python3
"""Run production pure MQL5 bodies via a minimal C++ compatibility adapter.
This checks calculations, NOT MetaEditor compilation or broker behavior.
"""
import pathlib, re, subprocess, tempfile, json, hashlib
ROOT = pathlib.Path(__file__).resolve().parents[2]
def adapt(text):
    text = re.sub(r'const (double|int|KTRRecord|KTRPositionView) &(\w+)\[\]', r'const std::vector<\1> &\2', text)
    text = re.sub(r'(double|int|KTRFeature|KTRSwing|KTRRecord|KTRPositionView|string) &(\w+)\[\]', r'std::vector<\1> &\2', text)
    text = re.sub(r'\b(double|int|KTRFeature|KTRSwing|KTRRecord|KTRPositionView|string) (\w+)\[\](\s*=\s*\{[^;]*\})?;',
                  lambda m: 'std::vector<'+m[1]+'> '+m[2]+(m[3] or '')+';', text)
    # Multiple uninitialized arrays in a single declaration.
    text = re.sub(r'\b(double|int|KTRFeature|KTRSwing|KTRRecord|KTRPositionView|string) ((?:\w+\[\],)+\w+\[\]);',
                  lambda m: 'std::vector<'+m[1]+'> '+m[2].replace('[]','')+';', text)
    return text
shim = r'''
#include <vector>
#include <string>
#include <cmath>
#include <iostream>
#include <cstdio>
using string=std::string;
using datetime=long;
int StringLen(const string& s) { return (int)s.size(); }
string StringSubstr(const string& s,int from,int count) { return s.substr(from,count); }
int StringFind(const string& s,const string& q) { auto p=s.find(q); return p==string::npos?-1:(int)p; }
int StringSplit(const string& s,char sep,std::vector<string>& out) {
 out.clear(); size_t from=0,at;
 while((at=s.find(sep,from))!=string::npos) { out.push_back(s.substr(from,at-from)); from=at+1; }
 out.push_back(s.substr(from)); return (int)out.size();
}
template<class T> int ArraySize(const std::vector<T>& x) { return (int)x.size(); }
template<class T> void ArrayResize(std::vector<T>& x,int n) { x.resize(n); }
template<class A,class B> double MathMax(A a,B b) { return std::fmax(a,b); }
template<class A,class B> double MathMin(A a,B b) { return std::fmin(a,b); }
double MathAbs(double x) { return std::fabs(x); }
double MathSqrt(double x) { return std::sqrt(x); }
double MathPow(double x,double y) { return std::pow(x,y); }
double MathFloor(double x) { return std::floor(x); }
double MathCeil(double x) { return std::ceil(x); }
void Print(const string& a,const string& b) { std::cout<<a<<b<<"\n"; }
void PrintFormat(const char* f,int a,int b) { std::printf(f,a,b); std::printf("\n"); }
'''
core=(ROOT/'Include/KTR/Core.mqh').read_text()+(ROOT/'Include/KTR/Recovery.mqh').read_text()
cases=(ROOT/'tests/ktr/CoreCases.mqh').read_text()+(ROOT/'tests/ktr/RecoveryCases.mqh').read_text()
with tempfile.TemporaryDirectory(prefix='ktr-test-') as tmp:
    cpp=pathlib.Path(tmp)/'core.cpp'; exe=pathlib.Path(tmp)/'core'
    cpp.write_text(shim+adapt(core)+adapt(cases)+'\nint main(){ KTRRunCoreCases(); KTRRunRecoveryCases(); return ktr_fail?1:0; }\n')
    subprocess.run(['g++','-std=c++17','-Wall','-Wextra','-Werror',str(cpp),'-o',str(exe)],check=True)
    result=subprocess.run([str(exe)],text=True,capture_output=True)
    print(result.stdout,end='')
    if result.returncode: raise SystemExit(result.returncode)
# Static checks are deliberately labeled; they cannot prove broker safety.
files=[ROOT/'Kumo_Trend_Rider.mq5',*sorted((ROOT/'Include/KTR').glob('*.mqh'))]
for f in files:
    source=f.read_text()
    assert not re.search(r'\b(GlobalVariable\w*|FileOpen|DatabaseOpen)\s*\(',source),f
    # Remove literals/comments for brace-balance sanity.
    code=re.sub(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"','',source,flags=re.S)
    assert code.count('{')==code.count('}'),f
print('PASS static: no KTR persistence APIs; balanced source braces')
original=['RSI_Pull_Up.mq5','README.md','TEST_PLAN.md','Include/FiboCore.mqh','Include/FiboChart.mqh','Include/FiboRuntime.mqh']
for path in original:
    expected=subprocess.check_output(['git','show','2e69947155a343f0b3a5f207b56873ca0f18fda9:'+path],cwd=ROOT)
    assert (ROOT/path).read_bytes()==expected, path
print('PASS preservation: all six existing tracked EA/docs/modules byte-for-byte unchanged')
