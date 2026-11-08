import {initialSession,emptySteps,type Session,type MusicEvent,type Instrument} from './model';
import {clipPresets as legacyClips} from './presets-v1';
export const genres=[['all','全部'],['boombap','Hip-hop / Boom bap'],['trap','Trap / 嘻哈'],['rock','摇滚'],['lofi','Lo-fi'],['funk','Funk'],['ambient','氛围']] as const;
export type Genre=Exclude<typeof genres[number][0],'all'>;
export type Preset={id:string;name:string;genre:Genre;bpm:number;root:number;variant:number;description:string;bars:number};
type Phrase=readonly [beat:number,pitch:number,duration:number,velocity?:number][];
type Chord=readonly [beat:number,duration:number,notes:readonly number[],velocity?:number][];
type DrumLane=readonly [voice:number,hits:readonly number[],velocity:number];
type Score={name:string;slug:string;genre:Genre;bpm:number;root:number;description:string;lead:Phrase;bass:Phrase;chords:Chord;drums:readonly DrumLane[];leadVoice:Instrument;chordVoice:Instrument;scale?:Session['scale'];reverb?:number;delay?:number;leadBase?:number;leadSpan?:number;bassSpan?:number;extras?:readonly [voice:number,beat:number,velocity:number][];muteDrums?:number[]};
// Each arrangement has its own written rhythm, bass contour, motif and harmonic pacing.
// IDs are versioned. Retired v1 clips remain resolvable below so saved music never changes sound.
const scores:Score[]=[
 {name:'街角唱片',slug:'dust',genre:'boombap',bpm:88,root:0,description:'后拍摇摆 · 短电钢和弦 · 一问一答',leadVoice:'pluck',chordVoice:'electric',
 drums:[[0,[0,1.5,2.75],.72],[1,[1,3],.63],[3,[0,.57,1,1.57,2,2.57,3,3.57],.31]],
 bass:[[0,0,.6],[1.75,7,.22],[2.5,10,.4],[3.5,7,.25],[4,0,.7],[5.5,3,.3],[6.75,-2,.3],[7.5,0,.3]],
 lead:[[.5,7,.25],[1.57,10,.3],[2.75,3,.5],[4.5,14,.4],[5.57,10,.23],[7,7,.65]],
 chords:[[0,.7,[0,3,7,10]],[4,.7,[5,8,12,15]],[8,.7,[3,7,10,14]],[12,.9,[7,10,14,17]]],extras:[[1,14.75,.2],[4,15.5,.35]]},
 {name:'碎拍速写',slug:'break',genre:'boombap',bpm:108,root:2,description:'断奏碎拍 · 交错低音 · 留白过门',leadVoice:'electric',chordVoice:'guitar',
 drums:[[0,[0,.75,2,2.5,3.75],.68],[1,[1,2.75,3.25],.59],[3,[.25,.5,1.5,1.75,2.25,3.5],.29],[4,[.75,2.75],.24]],
 bass:[[0,0,.22],[.75,12,.18],[1.5,7,.18],[2.5,3,.2],[3.25,5,.35],[4.5,0,.2],[5.25,10,.18],[6.5,7,.3],[7.25,-2,.2]],
 lead:[[0,12,.18],[.75,7,.18],[1.5,15,.18],[3,10,.3],[4.25,19,.18],[4.75,15,.2],[6.25,14,.3],[7.5,7,.18]],
 chords:[[0,.28,[0,7]],[2.5,.22,[3,10]],[5.25,.3,[5,12]],[8,.28,[0,7]],[10.75,.22,[10,17]],[13.5,.35,[7,14]]],muteDrums:[3],extras:[[0,12,.8],[1,14,.6],[6,15.25,.4],[5,15.5,.4]]},
 {name:'低空巡航',slug:'cruise',genre:'boombap',bpm:78,root:7,description:'半拍巡航 · 长线合成器 · 下行贝斯',leadVoice:'warm',chordVoice:'electric',reverb:.25,
 drums:[[0,[0,2.5],.7],[2,[2],.55],[3,[0,.5,1.5,2,3,3.5],.25],[7,[1.75],.16]],
 bass:[[0,0,1.5],[2.5,-2,.9],[4,-5,1.8],[6.5,-7,.6],[7.5,-2,.3]],
 lead:[[0,12,1.4],[2,10,.75],[3,7,.75],[4.5,5,1.25],[6,7,1.4]],
 chords:[[0,2.5,[0,4,7,11]],[4,2.5,[-5,-1,2,6]],[8,2.5,[-2,2,5,9]],[12,3,[0,4,7,9]]],scale:'major'},
 {name:'深潜 808',slug:'sub',genre:'trap',bpm:142,root:2,description:'稀疏重低音 · 单音钩子 · 半拍落点',leadVoice:'pluck',chordVoice:'warm',reverb:.11,
 drums:[[0,[0,1.75,3.25],.82],[1,[2],.72],[3,[0,.5,1,1.5,2,2.5,3,3.5,3.75],.3]],
 bass:[[0,-12,1.5],[1.75,-12,.2],[3.25,0,.5],[4,-12,1.75],[6.5,-5,.3],[7.25,-7,.5]],
 lead:[[.75,19,.2],[3.25,19,.2],[4.75,15,.2],[6.75,14,.6]],
 chords:[[0,6.5,[0,3,7],.16],[8,6.5,[-5,-2,2],.16]],extras:[[3,7.5,.3],[3,7.667,.23],[3,7.833,.2],[2,10,.25],[3,15.75,.22]]},
 {name:'玻璃阶梯',slug:'stair',genre:'trap',bpm:154,root:5,description:'三连音阶梯 · 钟音旋律 · 跳跃低音',leadVoice:'electric',chordVoice:'warm',reverb:.3,delay:.1,
 drums:[[0,[0,.667,2.333,3.5],.72],[2,[2],.63],[3,[0,.333,.667,1.333,1.667,2.333,2.667,3,3.333,3.667],.28]],
 bass:[[0,0,.5],[.667,12,.4],[2.333,7,.8],[4,3,.6],[5.333,10,.4],[6.667,0,.9]],
 lead:[[0,0,.24],[.333,3,.24],[.667,7,.24],[1.333,12,.48],[2.333,10,.24],[2.667,7,.24],[3.333,3,.48],[4,5,.24],[4.333,8,.24],[4.667,12,.24],[5.333,17,.48],[6.333,15,.24],[6.667,12,.24],[7.333,7,.48]],
 chords:[[0,3,[0,3,7],.18],[4,3,[5,8,12],.18],[8,3,[3,7,10],.18],[12,3,[7,10,14],.18]]},
 {name:'切面',slug:'facet',genre:'trap',bpm:136,root:1,description:'错位底鼓 · 暗色双音 · 空拍切口',leadVoice:'guitar',chordVoice:'warm',reverb:.08,
 drums:[[0,[.5,1.25,2.75,3.5],.78],[1,[1.5,3.75],.67],[3,[0,.25,.75,1,1.75,2.25,2.5,3.25],.27],[7,[2],.22]],
 bass:[[.5,-12,.5],[1.25,0,.25],[2.75,-7,.5],[3.5,-12,.2],[4.5,-12,.8],[6.25,-10,.3],[7,-5,.55]],
 lead:[[0,7,.18],[.75,8,.18],[2,7,.45],[4,3,.18],[4.75,2,.18],[6,0,.65]],
 chords:[[0,1.25,[0,1,7],.16],[6,1.3,[-5,-4,2],.16],[8,1.25,[0,1,7],.16],[14,1.3,[3,4,10],.16]],extras:[[0,15.5,.88],[3,15.667,.25]]},
 {name:'车库点火',slug:'ignite',genre:'rock',bpm:132,root:4,description:'直八冲劲 · 动力和弦 · 嗵鼓收尾',leadVoice:'guitar',chordVoice:'guitar',reverb:.07,
 drums:[[0,[0,1.5,2,2.5],.84],[1,[1,3],.8],[3,[0,.5,1,1.5,2,2.5,3],.44],[4,[3.5],.39]],
 bass:[[0,0,.35],[.5,0,.35],[1,0,.35],[1.5,7,.35],[2,0,.35],[2.5,0,.35],[3,10,.35],[3.5,7,.35]],bassSpan:4,
 lead:[[0,12,.35],[1.5,7,.35],[2,10,.55],[3.5,7,.25],[4,12,.35],[5,15,.35],[6,14,.35],[7,7,.6]],
 chords:[[0,.7,[0,7],.4],[1.5,.7,[0,7],.4],[4,.7,[3,10],.4],[5.5,.7,[3,10],.4],[8,.7,[5,12],.4],[9.5,.7,[5,12],.4],[12,.7,[7,14],.4],[13.5,.7,[7,14],.4]],extras:[[5,14.5,.6],[6,14.75,.6],[1,15.25,.6],[5,15.5,.7],[6,15.75,.7]]},
 {name:'折线行进',slug:'angular',genre:'rock',bpm:118,root:2,description:'3+3+2 重音 · 单线吉他 · 切分推进',leadVoice:'guitar',chordVoice:'guitar',reverb:.06,
 drums:[[0,[0,.75,1.5,2.25,3],.8],[1,[1.25,3.25],.72],[3,[0,.25,.75,1.5,1.75,2.25,3,3.5],.35]],
 bass:[[0,0,.2],[.75,0,.2],[1.5,3,.2],[2.25,0,.2],[3,7,.35],[4,0,.2],[4.75,0,.2],[5.5,-2,.2],[6.25,5,.2],[7,3,.5]],
 lead:[[0,0,.2],[.75,12,.2],[1.5,3,.2],[2.25,10,.2],[3,7,.4],[4,0,.2],[4.75,12,.2],[5.5,2,.2],[6.25,5,.2],[7,3,.5]],
 chords:[[3.5,.3,[0,7]],[7.5,.3,[5,12]],[11.5,.3,[3,10]],[15, .8,[7,14]]],extras:[[7,2.75,.22],[6,10.75,.45]]},
 {name:'慢燃落日',slug:'sunset',genre:'rock',bpm:84,root:7,description:'半拍慢摇 · 开放分解 · 长和弦呼吸',leadVoice:'guitar',chordVoice:'warm',scale:'major',reverb:.32,
 drums:[[0,[0,2.75],.69],[1,[2],.66],[3,[0,1,2,3],.27],[4,[3.5],.3]],
 bass:[[0,0,2.2],[3,7,.6],[4,-5,2.1],[7,-2,.65]],
 lead:[[0,0,.65],[.75,7,.65],[1.5,12,1],[3,11,.7],[4,4,.65],[4.75,7,.65],[5.5,14,1],[7,12,.7]],
 chords:[[0,3.6,[0,4,7,11],.21],[4,3.6,[-5,-1,2,6],.21],[8,3.6,[-3,0,4,7],.21],[12,3.6,[-2,2,5,9],.21]],extras:[[6,15,.35],[5,15.5,.4]]},
 {name:'雨窗小调',slug:'rain',genre:'lofi',bpm:74,root:0,description:'松散摇摆 · 九和弦 · 下行钢琴',leadVoice:'piano',chordVoice:'electric',reverb:.31,
 drums:[[0,[0,2.65],.55],[1,[1.05,3.05],.45],[3,[0,.64,1,1.64,2,2.64,3,3.64],.2]],
 bass:[[0,0,1.3],[2.65,7,.5],[4,5,1.3],[6.65,3,.5]],
 lead:[[.64,14,.6],[1.64,10,.6],[2.64,7,.9],[4.64,15,.6],[5.64,12,.6],[6.64,10,.9]],
 chords:[[0,2.2,[0,3,7,14]],[4,2.2,[5,8,12,19]],[8,2.2,[3,7,10,17]],[12,2.4,[7,10,14,21]]]},
 {name:'纸月散步',slug:'bossa',genre:'lofi',bpm:98,root:5,description:'轻波萨切分 · 拨弦问答 · 拉丁叮音',leadVoice:'pluck',chordVoice:'electric',scale:'major',reverb:.19,
 drums:[[0,[0,1.5,2,3.5],.48],[2,[1,2.5],.26],[7,[0,.75,1.5,2.5,3.25],.18],[3,[.5,1.5,2.5,3.5],.19]],
 bass:[[0,0,.45],[1.5,7,.25],[2,0,.45],[3.5,7,.25],[4,2,.45],[5.5,9,.25],[6,2,.45],[7.5,11,.25]],
 lead:[[.5,4,.35],[1.5,7,.35],[2.5,9,.65],[4,12,.4],[5.25,11,.3],[6,9,.45],[7,7,.45]],
 chords:[[0,.3,[0,4,7,11]],[1.5,.3,[0,4,7,11]],[3,.3,[0,4,7,11]],[4,.3,[2,5,9,12]],[5.5,.3,[2,5,9,12]],[7,.3,[7,11,14,17]],[8,.3,[0,4,7,11]],[9.5,.3,[4,7,11,14]],[11,.3,[4,7,11,14]],[12,.3,[2,5,9,12]],[13.5,.3,[7,11,14,17]],[15,.3,[7,11,14,17]]]},
 {name:'空白页',slug:'page',genre:'lofi',bpm:66,root:9,description:'独奏钢琴感 · 大段留白 · 轻落点',leadVoice:'piano',chordVoice:'piano',reverb:.38,
 drums:[[0,[0],.24],[7,[3.25],.12]],muteDrums:[0,2],
 bass:[[0,0,2.6],[6,-5,1.5]],
 lead:[[0,0,1.25],[1.75,7,.75],[3.25,3,1.25],[5,10,1],[7,7,.7]],
 chords:[[0,3,[0,3,7],.24],[6,1.7,[-5,-2,2],.24],[8,2.8,[3,7,10],.24],[13,2.5,[-2,2,5],.24]]},
 {name:'弹簧步伐',slug:'spring',genre:'funk',bpm:110,root:2,description:'八度跳跃 · 短促和弦 · 鬼音军鼓',leadVoice:'electric',chordVoice:'guitar',reverb:.09,
 drums:[[0,[0,1.75,2.5],.73],[1,[1,3],.66],[1,[.75,2.75,3.75],.16],[3,[0,.25,.5,1,1.25,1.5,2,2.25,2.5,3,3.25,3.5],.26]],
 bass:[[0,0,.16],[.75,12,.16],[1.5,0,.16],[1.75,7,.16],[2.5,12,.16],[3.25,10,.16],[3.75,7,.16],[4,0,.16],[4.75,12,.16],[5.5,3,.16],[6.25,5,.16],[6.75,7,.16],[7.5,12,.25]],
 lead:[[.5,12,.18],[2.25,15,.18],[3.5,19,.25],[4.5,22,.18],[6,19,.18],[7.25,15,.25]],
 chords:[[.5,.17,[0,3,7,10]],[2.25,.17,[0,3,7,10]],[4.5,.17,[5,8,12,15]],[6.25,.17,[5,8,12,15]],[8.5,.17,[3,7,10,14]],[10.25,.17,[3,7,10,14]],[12.5,.17,[7,10,14,17]],[14.25,.17,[7,10,14,17]]]},
 {name:'四拍舞池',slug:'disco',genre:'funk',bpm:122,root:0,description:'四拍底鼓 · 反拍开镲 · 明亮和声',leadVoice:'guitar',chordVoice:'electric',scale:'major',reverb:.16,
 drums:[[0,[0,1,2,3],.69],[2,[1,3],.55],[4,[.5,1.5,2.5,3.5],.34],[3,[.25,.75,1.25,1.75,2.25,2.75,3.25,3.75],.14]],
 bass:[[0,0,.3],[.5,12,.22],[1,7,.3],[1.5,12,.22],[2,4,.3],[2.5,12,.22],[3,7,.3],[3.5,11,.22]],bassSpan:4,
 lead:[[.5,7,.23],[1.5,9,.23],[2.5,12,.23],[3.5,16,.23],[4.5,14,.23],[5.5,12,.23],[6.5,9,.23],[7.5,7,.23]],
 chords:[[.5,.23,[0,4,7,11]],[1.5,.23,[0,4,7,11]],[2.5,.23,[0,4,7,11]],[3.5,.23,[0,4,7,11]],[4.5,.23,[5,9,12,16]],[6.5,.23,[5,9,12,16]],[8.5,.23,[9,12,16,19]],[10.5,.23,[9,12,16,19]],[12.5,.23,[7,11,14,17]],[14.5,.23,[7,11,14,17]]]},
 {name:'切分谜题',slug:'clav',genre:'funk',bpm:102,root:4,description:'十六分拨弦 · 叮音对位 · 断续贝斯',leadVoice:'pluck',chordVoice:'electric',reverb:.05,
 drums:[[0,[.25,1.5,2.25,3.5],.65],[1,[1,3],.63],[7,[0,.75,1.75,2.5,3.25],.25],[3,[.5,1.25,2,2.75,3.75],.23]],
 bass:[[.25,0,.2],[1.5,7,.2],[2.25,10,.2],[3.5,12,.2],[4.25,0,.2],[5.5,-2,.2],[6.25,3,.2],[7.5,7,.2]],
 lead:[[0,0,.11],[.25,12,.11],[.75,7,.11],[1.25,10,.11],[1.75,3,.11],[2.5,7,.11],[2.75,12,.11],[3.25,10,.2],[4.25,5,.11],[4.75,12,.11],[5.25,8,.11],[5.75,15,.11],[6.5,10,.11],[7.25,7,.25]],
 chords:[[0,.18,[0,3,7]],[3.75,.18,[5,8,12]],[7.75,.18,[3,7,10]],[8,.18,[0,3,7]],[11.75,.18,[5,8,12]],[15.5,.3,[7,10,14]]]},
 {name:'缓慢潮汐',slug:'tide',genre:'ambient',bpm:60,root:0,description:'长音潮汐 · 两次和声转移 · 低频脉冲',leadVoice:'warm',chordVoice:'warm',reverb:.5,delay:.11,
 drums:[[0,[0],.16]],muteDrums:[1,3],
 bass:[[0,0,7.5]],lead:[[0,19,3.5],[5,14,2.8]],
 chords:[[0,7.8,[0,7,14,21],.18],[8,7.8,[5,12,19,23],.18]]},
 {name:'星轨',slug:'orbit',genre:'ambient',bpm:92,root:2,description:'五音循环 · 交错脉冲 · 点状回声',leadVoice:'pluck',chordVoice:'warm',reverb:.42,delay:.18,
 drums:[[7,[.5,2.5],.15],[3,[0,1.25,2.5,3.75],.14]],
 bass:[[0,0,3.1],[4,-5,3.1]],
 lead:[[0,0,.4],[.625,7,.4],[1.25,14,.4],[1.875,19,.4],[2.5,12,.4],[3.125,0,.4],[3.75,7,.4],[4.375,14,.4],[5,19,.4],[5.625,12,.4],[6.25,0,.4],[6.875,7,.4],[7.5,14,.4]],
 chords:[[0,7.5,[0,7,14],.15],[8,7.5,[-5,2,9],.15]]},
 {name:'悬浮电台',slug:'radio',genre:'ambient',bpm:72,root:5,description:'电钢双声部 · 空间停顿 · 稀疏叮音',leadVoice:'electric',chordVoice:'piano',reverb:.45,delay:.08,
 drums:[[7,[1.5],.13],[4,[3.5],.1]],muteDrums:[1,2],
 bass:[[1,0,1.6],[5,-2,1.6]],
 lead:[[.5,7,1],[2,14,1.5],[5,10,.8],[6.5,5,1.2]],
 chords:[[0,2.6,[0,3,10],.19],[5,2.6,[-2,2,9],.19],[9,2.6,[3,7,14],.19],[13.5,2.3,[5,8,15],.19]]}
];
export const songPresets:Preset[]=scores.map((s,i)=>({id:s.genre+'-'+s.slug+'-v2',name:s.name,genre:s.genre,bpm:s.bpm,root:s.root,variant:i%3,description:s.description,bars:4}));
export const genreName=(g:string)=>genres.find(x=>x[0]===g)?.[1]??g;
export function presetSession(p:Preset):Session {
 const score=scores[songPresets.findIndex(s=>s.id===p.id)];if(!score)throw Error('预设作品不存在');
 const s=initialSession();Object.assign(s,{name:p.name,bpm:p.bpm,bars:p.bars,root:p.root,scale:score.scale??'minor',sourcePreset:p.id,instrument:score.leadVoice,reverb:score.reverb??.18,delay:score.delay??0,master:.6,tone:score.genre==='lofi'?.46:.68,drumGain:.76,drumEnabled:false,steps:emptySteps(),events:[]});
 let id=0;const add=(kind:MusicEvent['kind'],value:number,beat:number,duration:number,velocity:number,instrument:Instrument)=>s.events.push({id:p.id+'-'+id++,kind,value,beat,duration:Math.min(duration,16),velocity,instrument});
 for(let bar=0;bar<4;bar++)if(!score.muteDrums?.includes(bar))for(const [voice,hits,velocity] of score.drums)for(const b of hits)add('drum',voice,bar*4+b,.14,velocity*(bar===3?.93:1),'piano');
 for(const [voice,beat,velocity] of score.extras??[])add('drum',voice,beat,.14,velocity,'piano');
 const phrase=(values:Phrase,span:number,base:number,instrument:Instrument,velocity:number)=>{for(let offset=0;offset<16;offset+=span)for(const [beat,pitch,duration,v] of values){if(offset+beat<16)add('note',base+p.root+pitch,offset+beat,duration,v??velocity,instrument);}};
 phrase(score.bass,score.bassSpan??8,36,'bass',.56);phrase(score.lead,score.leadSpan??8,score.leadBase??60,score.leadVoice,.38);
 for(const [beat,duration,notes,velocity] of score.chords)for(const n of notes)add('note',48+p.root+n,beat,duration,velocity??.29,score.chordVoice);
 s.events.sort((a,b)=>a.beat-b.beat);return s;
}
export type ClipPreset={id:string;name:string;genre:Genre|'original';bpm:number;beats:number;kind?:'rhythm'|'theme';events:Omit<MusicEvent,'id'>[]};
export const clipPresets:ClipPreset[]=songPresets.flatMap(p=>{
 const song=presetSession(p);return (['rhythm','theme'] as const).map(kind=>({id:p.id+'-'+kind,name:p.name+' · '+(kind==='rhythm'?'节奏':'主题'),genre:p.genre,bpm:p.bpm,beats:8,kind,events:song.events.filter(e=>e.beat<8&&(kind==='rhythm'?e.kind==='drum'||e.instrument==='bass':e.kind==='note'&&e.instrument!=='bass')).map(e=>({...e,duration:Math.min(e.duration,8-e.beat)}))}));
});
export const getClipPreset=(id:string|undefined,slot:number):ClipPreset=>clipPresets.find(p=>p.id===id)??legacyClips.find(p=>p.id===(id??'original-'+slot))??legacyClips[slot%8];
export function replaceClipSource(s:Session,slot:number,id:string):Session {if(!Number.isInteger(slot)||slot<0||slot>7)throw Error('请选择 1–8 号槽位');const p=clipPresets.find(p=>p.id===id);if(!p)throw Error('片段不存在');return {...s,clips:s.clips.map((c,i)=>i===slot?{name:p.name,gain:.8,rate:1,loop:c.loop,start:0,end:1,preset:p.id}:c)};}
