import {getClipPreset} from './presets';
import {clamp,clipScore,encodeWav,swingBeat,wrap,type Instrument,type Session,type MusicEvent} from './model';
type Ctx=AudioContext|OfflineAudioContext;
type Voice={stop:(time?:number)=>void;start:number;key?:string};
const sampleNames=['A0',...Array.from({length:7},(_,i)=>['C','Ds','Fs','A'].map(n=>n+(i+1))).flat(),'C8'];
const midi=(name:string)=>12*(Number(name.at(-1))+1)+({C:0,Ds:3,Fs:6,A:9}[name.slice(0,-1)]??0);
function random(seed:number){return()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296*2-1;};}
export function makeDrum(ctx:Ctx,index:number):AudioBuffer {
 const lengths=[.65,.34,.28,.13,.72,.5,.32,.85];const len=lengths[index],sr=ctx.sampleRate,b=ctx.createBuffer(1,Math.ceil(sr*len),sr),x=b.getChannelData(0),rnd=random(71+index);
 let phase=0,last=0,low=0;
 for(let i=0;i<x.length;i++){const t=i/sr,n=rnd();low+=.17*(n-low);const hi=n-low;let a=0;
 if(index===0){const f=46+105*Math.exp(-t*42);phase+=2*Math.PI*f/sr;a=.92*Math.sin(phase)*Math.exp(-t*8)+hi*.15*Math.exp(-t*150);}
 if(index===1)a=(hi*.75*Math.exp(-t*20)+(Math.sin(t*2*Math.PI*185)+.4*Math.sin(t*2*Math.PI*330))*.35*Math.exp(-t*30));
 if(index===2){const env=[0,.012,.026].reduce((v,start)=>v+(t>=start?Math.exp(-(t-start)*70):0),0)+.3*Math.exp(-t*20);a=hi*env*.4;}
 if(index===3||index===4){const metal=[4073,5621,7993].reduce((s,f)=>s+Math.sin(2*Math.PI*f*t),0)/3;a=(hi*.7+metal*.13)*Math.exp(-t*(index===3?55:8));}
 if(index===5||index===6){const f=(index===5?93:155)+80*Math.exp(-t*35);phase+=2*Math.PI*f/sr;a=Math.sin(phase)*Math.exp(-t*(index===5?12:20))*.8+hi*.12*Math.exp(-t*70);}
 if(index===7)a=(Math.sin(t*2*Math.PI*1320)+.42*Math.sin(t*2*Math.PI*2073)+.2*Math.sin(t*2*Math.PI*3701))*.35*Math.exp(-t*7);
 const attack=Math.min(1,t/.0015),fade=Math.min(1,(len-t)/.02);x[i]=Math.tanh(a)*attack*fade;last=x[i];
 }return b;
}
export class SoundGraph {
 ctx:Ctx;bus:GainNode;master:GainNode;filter:BiquadFilterNode;reverb:GainNode;echo:GainNode;delay:DelayNode;feedback:GainNode;analyser:AnalyserNode;voices=new Set<Voice>();piano=new Map<number,AudioBuffer>();drumBuffers:AudioBuffer[];clips=new Map<number,AudioBuffer>();hat:Voice|null=null;
 constructor(ctx:Ctx){this.ctx=ctx;this.bus=ctx.createGain();this.master=ctx.createGain();this.filter=ctx.createBiquadFilter();this.filter.type='lowpass';this.filter.Q.value=.5;
 const comp=ctx.createDynamicsCompressor();comp.threshold.value=-14;comp.knee.value=10;comp.ratio.value=5;comp.attack.value=.003;comp.release.value=.18;
 this.analyser=ctx.createAnalyser();this.analyser.fftSize=256;this.bus.connect(this.filter);this.filter.connect(comp);comp.connect(this.master);this.master.connect(this.analyser);this.analyser.connect(ctx.destination);
 const con=ctx.createConvolver(),ir=ctx.createBuffer(2,Math.ceil(ctx.sampleRate*1.8),ctx.sampleRate);for(let c=0;c<2;c++){const a=ir.getChannelData(c),rnd=random(100+c);for(let i=0;i<a.length;i++)a[i]=rnd()*Math.pow(1-i/a.length,2.7)*.55;}
 con.buffer=ir;this.reverb=ctx.createGain();this.filter.connect(con);con.connect(this.reverb);this.reverb.connect(comp);
 this.delay=ctx.createDelay(2);this.feedback=ctx.createGain();this.feedback.gain.value=.27;this.echo=ctx.createGain();this.filter.connect(this.delay);this.delay.connect(this.feedback);this.feedback.connect(this.delay);this.delay.connect(this.echo);this.echo.connect(comp);
 this.drumBuffers=Array.from({length:8},(_,i)=>makeDrum(ctx,i));
 }
 settings(s:Session){const t=this.ctx.currentTime;this.master.gain.setTargetAtTime(s.master*.75,t,.025);this.reverb.gain.setTargetAtTime(s.reverb*.75,t,.025);this.echo.gain.setTargetAtTime(s.delay*.55,t,.025);this.delay.delayTime.setTargetAtTime(60/s.bpm*.75,t,.04);this.filter.frequency.setTargetAtTime(1200+Math.pow(s.tone,1.6)*16800,t,.025);}
 voice(nodes:AudioScheduledSourceNode[],gain:GainNode,start:number,release=.15,extra:AudioNode[]=[]):Voice {
 let stopAt=Infinity;const v:Voice={start,stop:(at=this.ctx.currentTime)=>{if(at<=this.ctx.currentTime)this.voices.delete(v);if(at>=stopAt)return;stopAt=at;const t=Math.max(at,this.ctx.currentTime);if(t<start){gain.gain.cancelScheduledValues(t);gain.gain.setValueAtTime(0,t);nodes.forEach(n=>{try{n.stop(t+.001);}catch{}});return;}gain.gain.cancelAndHoldAtTime(t);gain.gain.setTargetAtTime(.00001,t,release/4);nodes.forEach(n=>{try{n.stop(t+release);}catch{}});}};
 this.voices.add(v);let remaining=nodes.length;nodes.forEach(n=>n.onended=()=>{if(--remaining===0){this.voices.delete(v);nodes.forEach(x=>x.disconnect());gain.disconnect();extra.forEach(x=>x.disconnect());}});
 while(this.ctx instanceof AudioContext&&this.voices.size>96){const oldest=this.voices.values().next().value;oldest?.stop();}return v;
 }
 note(note:number,velocity:number,instrument:Instrument,time=this.ctx.currentTime,duration?:number):Voice {
 const c=this.ctx,t=Math.max(time,c.currentTime),g=c.createGain(),p=c.createStereoPanner();p.pan.value=clamp((note-60)/72,-.28,.28);g.connect(p);p.connect(this.bus);
 const nodes:AudioScheduledSourceNode[]=[],extra:AudioNode[]=[p],freq=440*Math.pow(2,(note-69)/12);let amp=velocity*.3;
 if(instrument==='piano'&&this.piano.size){const closest=[...this.piano.keys()].reduce((best,k)=>Math.abs(k-note)<Math.abs(best-note)?k:best);const src=c.createBufferSource();src.buffer=this.piano.get(closest)!;src.playbackRate.value=Math.pow(2,(note-closest)/12);src.connect(g);nodes.push(src);amp=velocity*.7;}
 else if(instrument==='bass'||instrument==='guitar'){
 const filter=c.createBiquadFilter();filter.type='lowpass';filter.frequency.value=instrument==='bass'?650+velocity*1200:3100;filter.Q.value=.7;extra.push(filter);filter.connect(g);
 if(instrument==='guitar'){const shaper=c.createWaveShaper(),curve=new Float32Array(4096);for(let k=0;k<curve.length;k++){const x=k*2/(curve.length-1)-1;curve[k]=Math.tanh(x*3.8)*.65;}shaper.curve=curve;shaper.oversample='2x';shaper.connect(filter);extra.push(shaper);for(const d of [-3,3]){const o=c.createOscillator();o.type='sawtooth';o.frequency.value=freq;o.detune.value=d;o.connect(shaper);nodes.push(o);}amp=velocity*.16;}
 else {for(const [type,ratio] of [['triangle',1],['sine',.5]] as const){const o=c.createOscillator();o.type=type;o.frequency.value=freq*ratio;o.connect(filter);nodes.push(o);}amp=velocity*.19;}
 }else if(instrument==='electric'||instrument==='pluck'){
 const carrier=c.createOscillator(),mod=c.createOscillator(),mg=c.createGain();carrier.type='sine';carrier.frequency.value=freq;mod.frequency.value=freq*(instrument==='electric'?2:3);mg.gain.setValueAtTime(freq*(instrument==='electric'?2.5:1.1)*velocity,t);mg.gain.exponentialRampToValueAtTime(freq*.015,t+.65);mod.connect(mg);mg.connect(carrier.frequency);carrier.connect(g);nodes.push(carrier,mod);extra.push(mg);amp=velocity*.23;
 }else {const f=c.createBiquadFilter();f.type='lowpass';f.frequency.value=instrument==='piano'?3200:1800+velocity*2200;extra.push(f);f.connect(g);for(const detune of [-5,5]){const o=c.createOscillator();o.type=instrument==='piano'?'triangle':'sawtooth';o.frequency.value=freq;o.detune.value=detune;o.connect(f);nodes.push(o);}amp=velocity*.11;}
 g.gain.setValueAtTime(0,t);g.gain.linearRampToValueAtTime(amp,t+(instrument==='warm'?.025:.004));
 if(instrument==='bass'||instrument==='guitar'){g.gain.exponentialRampToValueAtTime(Math.max(.001,amp*.68),t+.17);}else if(instrument!=='piano'&&instrument!=='warm'){g.gain.exponentialRampToValueAtTime(Math.max(.001,amp*.32),t+.35);g.gain.exponentialRampToValueAtTime(.0001,t+(instrument==='pluck'?2.5:7));}
 nodes.forEach(n=>n.start(t));const v=this.voice(nodes,g,t,instrument==='warm'?.35:.18,extra);if(duration!==undefined)v.stop(t+Math.max(.03,duration));else nodes.forEach(n=>{try{n.stop(t+20);}catch{}});return v;
 }
 drum(index:number,velocity:number,time=this.ctx.currentTime):Voice {const c=this.ctx,t=Math.max(time,c.currentTime);if(index===3)this.hat?.stop(t);const src=c.createBufferSource(),g=c.createGain();src.buffer=this.drumBuffers[index];g.gain.value=velocity*.6;src.connect(g);g.connect(this.bus);src.start(t);const v=this.voice([src],g,t,.025);if(index===4)this.hat=v;return v;}
 clip(index:number,s:Session,time=this.ctx.currentTime,maxDuration?:number):Voice|null {const c=this.ctx,b=this.clips.get(index);if(!b)return null;const clip=s.clips[index],t=Math.max(time,c.currentTime),src=c.createBufferSource(),g=c.createGain();src.buffer=b;src.playbackRate.value=clip.rate;const offset=clip.start*b.duration,length=Math.max(.01,(clip.end-clip.start)*b.duration),duration=Math.min(length/clip.rate,maxDuration??Infinity);g.gain.setValueAtTime(0,t);g.gain.linearRampToValueAtTime(clip.gain*.7,t+.005);g.gain.setValueAtTime(clip.gain*.7,Math.max(t+.005,t+duration-.012));g.gain.linearRampToValueAtTime(0,t+duration);src.connect(g);g.connect(this.bus);src.start(t,offset,length);const v=this.voice([src],g,t,.015);src.stop(t+duration+.02);return v;}
 click(accent:boolean,time:number){const o=this.ctx.createOscillator(),g=this.ctx.createGain();o.frequency.value=accent?1200:850;g.gain.setValueAtTime(.075,time);g.gain.exponentialRampToValueAtTime(.00001,time+.035);o.connect(g);g.connect(this.bus);o.start(time);o.stop(time+.04);this.voice([o],g,time,.01);}
 event(e:MusicEvent,s:Session,time:number){if(e.kind==='note')return this.note(e.value,e.velocity,e.instrument,time,e.duration*60/s.bpm);if(e.kind==='drum')return this.drum(e.value,e.velocity*s.drumGain,time);return this.clip(e.value,s,time,e.duration*60/s.bpm);}
 panic(){for(const v of this.voices)v.stop();this.hat=null;this.master.gain.cancelScheduledValues(this.ctx.currentTime);this.master.gain.setTargetAtTime(0,this.ctx.currentTime,.005);}
}
export class MusicEngine {
 context:AudioContext|null=null;graph:SoundGraph|null=null;session:Session;playing=false;recording=false;startTime=0;scheduledBeat=0;timer:ReturnType<typeof setInterval>|null=null;held=new Map<string,Voice[]>();sustain=false;deferred:Voice[]=[];clipLoops=new Map<number,{next:number;voices:Voice[]}>();clipTimers=new Map<number,ReturnType<typeof setTimeout>>();loading:Promise<void>|null=null;clipSignatures=new Map<number,string>();onClip:(slot:number,active:boolean)=>void=()=>{};onError:(s:string)=>void=()=>{};
 constructor(s:Session){this.session=s;}
 async init(){if(this.loading)return this.loading;this.loading=(async()=>{if(!this.context){this.context=new AudioContext({latencyHint:'interactive'});this.graph=new SoundGraph(this.context);}await this.context.resume();const c=this.context,g=this.graph!;
 await Promise.all(sampleNames.map(async name=>{const res=await fetch('/music/piano/'+name+'.mp3');if(!res.ok)throw Error('钢琴音源读取失败');g.piano.set(midi(name),await c.decodeAudioData(await res.arrayBuffer()));}));
 await this.loadClips();g.settings(this.session);})();try{await this.loading;}catch(e){this.loading=null;throw e;}}
 async loadClip(slot:number){if(!this.graph||!this.context)return;const clip=this.session.clips[slot],signature=clip.audio??clip.preset??'original-'+slot;if(this.clipSignatures.get(slot)===signature&&this.graph.clips.has(slot))return;
 let b:AudioBuffer;if(clip.audio){const bytes=Uint8Array.from(atob(clip.audio.split(',')[1]),c=>c.charCodeAt(0));b=await this.context.decodeAudioData(bytes.buffer);if(b.duration>30.1)throw Error('片段最长 30 秒');}
 else {const score=getClipPreset(clip.preset,slot),duration=score.beats*60/score.bpm;const off=new OfflineAudioContext(2,Math.ceil((duration+1)*44100),44100),g=new SoundGraph(off);g.piano=this.graph.piano;const renderSession={...this.session,bpm:score.bpm,master:1,reverb:.12,delay:0,tone:.8};g.settings(renderSession);score.events.forEach(e=>g.event({...e,id:'preset'},renderSession,e.beat*60/score.bpm));b=await off.startRendering();const trimmed=this.context.createBuffer(2,Math.ceil(duration*b.sampleRate),b.sampleRate);for(let c=0;c<2;c++){const a=trimmed.getChannelData(c);a.set(b.getChannelData(c).subarray(0,a.length));for(let i=0;i<Math.min(600,a.length);i++)a[a.length-1-i]*=i/600;}b=trimmed;}
 this.graph.clips.set(slot,b);this.clipSignatures.set(slot,signature);
 }
 async loadClips(){for(let slot=0;slot<8;slot++)await this.loadClip(slot);}
 update(s:Session){const tempo=s.bpm!==this.session.bpm||s.bars!==this.session.bars;const playing=this.playing;if(tempo&&playing)this.stop();this.session=s;this.graph?.settings(s);if(tempo&&playing)this.play();}
 nowBeat(){return this.context?Math.max(0,(this.context.currentTime-this.startTime)*this.session.bpm/60):0;}
 noteOn(key:string,notes:number[],instrument=this.session.instrument){if(!this.graph||!this.context||this.context.state!=='running'||this.held.has(key))return;this.graph.settings(this.session);this.held.set(key,notes.map(n=>this.graph!.note(n,this.session.velocity,instrument)));}
 noteOff(key:string){const voices=this.held.get(key);if(!voices)return;this.held.delete(key);if(this.sustain)this.deferred.push(...voices);else voices.forEach(v=>v.stop());}
 pedal(value:boolean){this.sustain=value;if(!value){this.deferred.forEach(v=>v.stop());this.deferred=[];}}
 releaseKeys(){for(const v of this.held.values())v.forEach(n=>n.stop());this.held.clear();this.pedal(false);}
 hit(index:number){this.graph?.settings(this.session);this.graph?.drum(index,this.session.velocity*this.session.drumGain);}
 async importClip(slot:number,file:File){if(!this.context)throw Error('请先开启演奏');if(file.size>8*1024*1024)throw Error('每个声音片段最大 8 MB');const b=await file.arrayBuffer();let decoded:AudioBuffer;try{decoded=await this.context.decodeAudioData(b.slice(0));}catch{throw Error('无法读取这个音频，请使用 WAV、MP3 或 M4A');}if(decoded.duration>30||decoded.duration<.03)throw Error('片段长度应在 0.03–30 秒之间');const data=await new Promise<string>((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(String(r.result).replace(/^data:[^;]*;/,'data:audio/octet-stream;'));r.onerror=()=>reject(Error('音频读取失败'));r.readAsDataURL(file);});this.stopClip(slot);this.graph!.clips.set(slot,decoded);return data;}
 clipDuration(slot:number){const c=this.session.clips[slot],b=this.graph?.clips.get(slot);return b?b.duration*(c.end-c.start)/c.rate:0;}
 triggerClip(slot:number){if(!this.graph||!this.context)return;const c=this.session.clips[slot];if(this.clipLoops.has(slot)||this.clipTimers.has(slot)){this.stopClip(slot);return;}this.graph.settings(this.session);this.onClip(slot,true);const t=this.context.currentTime+.005;
 if(c.loop){const v=this.graph.clip(slot,this.session,t);this.clipLoops.set(slot,{next:t+this.clipDuration(slot),voices:v?[v]:[]});this.ensureTimer();}
 else {const v=this.graph.clip(slot,this.session,t);this.clipLoops.set(slot,{next:Infinity,voices:v?[v]:[]});this.clipTimers.set(slot,setTimeout(()=>this.stopClip(slot),this.clipDuration(slot)*1000+40));}}
 stopClip(slot:number){const timer=this.clipTimers.get(slot);if(timer)clearTimeout(timer);this.clipTimers.delete(slot);this.clipLoops.get(slot)?.voices.forEach(v=>v.stop());this.clipLoops.delete(slot);this.onClip(slot,false);if(!this.playing&&!this.clipLoops.size)this.clearTimer();}
 play(){if(!this.context||this.playing)return;this.graph?.settings(this.session);this.playing=true;this.startTime=this.context.currentTime+.035;this.scheduledBeat=0;this.ensureTimer();this.tick();}
 ensureTimer(){if(!this.timer)this.timer=setInterval(()=>{try{this.tick();}catch(e){this.onError(String(e));this.stop();}},25);}
 clearTimer(){if(this.timer)clearInterval(this.timer);this.timer=null;}
 scheduleRange(from:number,to:number){const s=this.session,beats=s.bars*4,seconds=60/s.bpm,g=this.graph!;
 for(let cycle=Math.floor(from/beats);cycle<=Math.floor(to/beats);cycle++)for(const e of s.events){const beat=cycle*beats+e.beat;if(beat>=from&&beat<to)g.event(e,s,this.startTime+beat*seconds);}
 for(let bar=Math.floor(from/4);bar<=Math.floor(to/4);bar++)for(let step=0;step<16;step++){const beat=bar*4+swingBeat(step,s.swing);if(beat<from||beat>=to)continue;const t=this.startTime+beat*seconds;if(s.drumEnabled)s.steps.forEach((row,d)=>{if(row[step])g.drum(d,row[step]*s.drumGain,t);});if(s.metronome&&step%4===0)g.click(step===0,t);}}
 tick(){if(!this.context||!this.graph)return;const now=this.context.currentTime;
 if(this.playing){const target=Math.max(0,(now+.10-this.startTime)*this.session.bpm/60);/* Skip stale backlog after suspension; never burst queued beats. */const current=Math.max(0,(now-this.startTime)*this.session.bpm/60);if(this.scheduledBeat<current-.5)this.scheduledBeat=current;this.scheduleRange(this.scheduledBeat,target);this.scheduledBeat=target;}
 for(const [slot,item] of this.clipLoops){if(item.next===Infinity)continue;const duration=this.clipDuration(slot);if(duration<=.01){this.stopClip(slot);continue;}if(item.next<now-.1)item.next=now+.005;while(item.next<now+.1){const v=this.graph.clip(slot,this.session,item.next);if(v)item.voices.push(v);item.voices=item.voices.filter(v=>this.graph!.voices.has(v));item.next+=duration;}}
 }
 stop(){this.playing=false;this.recording=false;this.clearTimer();for(const slot of [...this.clipLoops.keys()])this.stopClip(slot);this.releaseKeys();this.graph?.panic();}
 async close(){this.stop();await this.context?.close();this.context=null;this.graph=null;this.loading=null;this.clipSignatures.clear();}
 async exportWav(cycles:number,activeClips:number[]=[]){if(!this.graph)throw Error('请先开启演奏');const s=this.session,seconds=60/s.bpm,total=s.bars*4*cycles*seconds;const ctx=new OfflineAudioContext(2,Math.ceil((total+2)*44100),44100),g=new SoundGraph(ctx);g.piano=this.graph.piano;g.clips=this.graph.clips;g.settings(s);
 for(let cycle=0;cycle<cycles;cycle++)for(const e of s.events)g.event(e,s,(cycle*s.bars*4+e.beat)*seconds);
 if(s.drumEnabled)for(let bar=0;bar<s.bars*cycles;bar++)s.steps.forEach((row,d)=>row.forEach((v,step)=>{if(v)g.drum(d,v*s.drumGain,(bar*4+swingBeat(step,s.swing))*seconds);}));
 for(const slot of activeClips){const dur=this.clipDuration(slot);if(dur>.01)for(let t=0;t<total;t+=dur)g.clip(slot,s,t,Math.min(dur,total-t));}
 const b=await ctx.startRendering();return encodeWav([b.getChannelData(0),b.getChannelData(1)],b.sampleRate);}
}
