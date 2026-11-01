#ifndef KTR_RECOVERY_MQH
#define KTR_RECOVERY_MQH
struct KTRMeta { long episode; datetime event; bool first; int method; int tf; };
string KTRBase36(long x)
{
   string chars="0123456789abcdefghijklmnopqrstuvwxyz",s="";
   do { int k=(int)(x%36); s=StringSubstr(chars,k,1)+s; x/=36; } while(x>0);
   return s;
}
long KTRUnbase36(const string s)
{
   string chars="0123456789abcdefghijklmnopqrstuvwxyz"; long x=0;
   if(StringLen(s)==0 || StringLen(s)>10) return -1;
   for(int i=0;i<StringLen(s);i++) { int k=StringFind(chars,StringSubstr(s,i,1)); if(k<0) return -1; x=x*36+k; }
   return x;
}
string KTRComment(const KTRMeta &m)
{ return "K1|"+KTRBase36(m.episode)+"|"+(m.first?"F":"A")+"|"+KTRBase36(m.method)+"|"+KTRBase36((long)m.event)+"|"+KTRBase36(m.tf); }
bool KTRParse(const string text,KTRMeta &m)
{
   string fields[]; if(StringSplit(text,'|',fields)!=6 || fields[0]!="K1" || (fields[2]!="F" && fields[2]!="A")) return false;
   m.episode=KTRUnbase36(fields[1]); m.first=fields[2]=="F";
   long method=KTRUnbase36(fields[3]),tf=KTRUnbase36(fields[5]);
   if(method<1 || method>255 || tf<1 || tf>2592000) return false;
   m.method=(int)method; m.event=(datetime)KTRUnbase36(fields[4]); m.tf=(int)tf;
   return m.episode>0 && (long)m.event>0 && m.method>0 && m.tf>0;
}
struct KTRRecord { ulong pid; ulong order; int dir; datetime opened; datetime executed; double fill_volume; double fill_price; KTRMeta meta; bool known; };
struct KTREpisode
{
   KTR_STATE state; long id; ulong first_pid; int count; int entries;
   datetime opened; datetime last_add; datetime last_fill; bool blocked;
};
struct KTRPositionView { ulong pid; int dir; double volume; };
void KTRRecoverEpisode(const int dir,const KTRRecord &records[],const KTRPositionView &positions[],
                       const bool history_ok,const bool closing,KTREpisode &episode)
{
   episode.state=closing?CLOSING:IDLE; episode.id=0; episode.first_pid=0;
   episode.count=0; episode.entries=0; episode.opened=0; episode.last_add=0;
   episode.last_fill=0; episode.blocked=!history_ok;
   for(int p=0;p<ArraySize(positions);p++)
   {
      if(positions[p].dir!=dir || positions[p].volume<=0) continue;
      episode.count++; int r=-1;
      for(int k=0;k<ArraySize(records);k++) if(records[k].pid==positions[p].pid) { r=k; break; }
      if(r<0 || !records[r].known) { episode.blocked=true; continue; }
      if(episode.id!=0 && episode.id!=records[r].meta.episode) episode.blocked=true;
      episode.id=records[r].meta.episode;
   }
   for(int r=0;r<ArraySize(records);r++)
   {
      if(!records[r].known || records[r].meta.episode!=episode.id || records[r].dir!=dir) continue;
      episode.entries++; episode.last_fill=MathMax(episode.last_fill,records[r].executed);
      if(records[r].meta.first)
      {
         if(episode.first_pid!=0 && episode.first_pid!=records[r].pid) episode.blocked=true;
         episode.first_pid=records[r].pid; episode.opened=records[r].opened;
      }
      else episode.last_add=MathMax(episode.last_add,records[r].executed);
   }
   bool first_open=false;
   for(int p=0;p<ArraySize(positions);p++)
      if(positions[p].pid==episode.first_pid && positions[p].volume>0 && positions[p].dir==dir) first_open=true;
   if(episode.count>0 && episode.first_pid==0) episode.blocked=true;
   episode.state=KTREpisodeState(episode.count,first_open,closing);
}
#endif
