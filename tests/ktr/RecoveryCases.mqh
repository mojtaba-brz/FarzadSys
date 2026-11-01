#ifndef KTR_RECOVERY_CASES_MQH
#define KTR_RECOVERY_CASES_MQH
void KTRRunRecoveryCases()
{
   KTRMeta meta;
   meta.episode=1793530000; meta.event=1793529000; meta.first=true; meta.method=7; meta.tf=3600;
   string text=KTRComment(meta); KTRMeta restored;
   KTRAssert(StringLen(text)<=31,"broker metadata length fits");
   KTRAssert(KTRParse(text,restored) && restored.episode==meta.episode && restored.event==meta.event && restored.first && restored.method==7 && restored.tf==3600,"compact metadata roundtrip");
   KTRAssert(!KTRParse("K1|truncated",restored),"truncated metadata rejected");
   KTRAssert(!KTRParse("K1|1|X|1|1|1",restored),"invalid role rejected");
   KTRAssert(!KTRParse("K1|!|F|1|1|1",restored),"invalid episode rejected");
   KTRAssert(!KTRParse("K1|1|F|1|1|0",restored),"zero timeframe rejected");
   KTRAssert(KTRUnbase36("zzzzzzzzzzzzzzzzzz")==-1,"overflowing metadata rejected");
   KTRRecord records[]; ArrayResize(records,3);
   for(int i=0;i<3;i++)
   {
      records[i].pid=100+i; records[i].order=200+i; records[i].dir=i==2?-1:1;
      records[i].opened=1000+i*100; records[i].executed=1000+i*100;
      records[i].meta=meta; records[i].meta.episode=i==2?11:10;
      records[i].meta.first=i!=1; records[i].known=true;
   }
   KTRPositionView positions[]; ArrayResize(positions,3);
   for(int i=0;i<3;i++) { positions[i].pid=100+i; positions[i].dir=i==2?-1:1; positions[i].volume=.1; }
   KTREpisode buy,sell;
   KTRRecoverEpisode(1,records,positions,true,false,buy);
   KTRRecoverEpisode(-1,records,positions,true,false,sell);
   KTRAssert(buy.state==ACTIVE && sell.state==ACTIVE && !buy.blocked && !sell.blocked,"independent BUY and SELL episodes coexist");
   KTRAssert(buy.first_pid==100 && buy.id==10 && buy.entries==2,"broker first identifier and addition count reconstructed");
   positions[0].volume=.03;
   KTRRecoverEpisode(1,records,positions,true,false,buy);
   KTRAssert(buy.state==ACTIVE,"partial original position close stays active");
   positions[0].volume=0;
   KTRRecoverEpisode(1,records,positions,true,false,buy);
   KTRAssert(buy.state==SUSPENDED && buy.first_pid==100 && buy.entries==2,"SL/manual first close with remaining addition suspends");
   KTRAssert(buy.last_add==1100 && buy.opened==1000,"cooldown and original execution recovered");
   positions[1].volume=0;
   KTRRecoverEpisode(1,records,positions,true,false,buy);
   KTRAssert(buy.state==IDLE && buy.id==0,"final addition closure yields idle");
   positions[1].volume=.1; records[1].known=false;
   KTRRecoverEpisode(1,records,positions,true,false,buy);
   KTRAssert(buy.blocked && buy.state!=IDLE,"unrecoverable live ownership cannot invent idle");
   records[1].known=true; records[0].known=false;
   KTRRecoverEpisode(1,records,positions,true,false,buy);
   KTRAssert(buy.blocked && buy.first_pid==0,"missing original opening history blocks episode");
   records[0].known=true; positions[0].volume=.1; records[1].meta.episode=12;
   KTRRecoverEpisode(1,records,positions,true,false,buy);
   KTRAssert(buy.blocked,"two BUY episode identities cannot overlap");
   records[0].dir=-1; records[1].dir=-1; positions[0].dir=-1; positions[1].dir=-1;
   KTRRecoverEpisode(-1,records,positions,true,false,sell);
   KTRAssert(sell.blocked,"two SELL episode identities cannot overlap");
   records[0].dir=1; records[1].dir=1; positions[0].dir=1; positions[1].dir=1;
   records[1].meta.episode=10;
   KTRRecoverEpisode(1,records,positions,false,false,buy);
   KTRAssert(buy.blocked,"unavailable broker history prevents new orders");
   KTRRecoverEpisode(1,records,positions,true,true,buy);
   KTRAssert(buy.state==CLOSING,"reversal forces closing state before further entries");
   PrintFormat("KTR combined: %d passed, %d failed",ktr_pass,ktr_fail);
}
#endif
