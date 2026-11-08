import {initialSession,emptySteps,clipNames,clipScore, type Session,type MusicEvent,type Instrument} from './model';
export const genres=[['all','全部'],['boombap','Hip-hop / Boom bap'],['trap','Trap / 嘻哈'],['rock','摇滚'],['lofi','Lo-fi'],['funk','Funk'],['ambient','氛围']] as const;
export type Genre=Exclude<typeof genres[number][0],'all'>;
export type Preset={id:string;name:string;genre:Genre;bpm:number;root:number;variant:number;description:string};
const banks:[Genre,string[],number[],number[],string][]=[
 ['boombap',['街角唱片','地下电台','午夜涂鸦','人行道律动'],[88,92,84,96],[0,2,5,7],'松弛鼓点 · 电钢和弦 · 切分低音'],
 ['trap',['霓虹低频','深夜车道','暗面节拍','悬浮街区'],[140,148,132,156],[2,5,7,9],'半拍军鼓 · 密集踩镲 · 深沉贝斯'],
 ['rock',['车库回声','公路日落','失真轮廓','慢燃现场'],[128,116,144,92],[4,7,9,2],'动力和弦 · 八分低音 · 鼓组过门'],
 ['lofi',['雨天窗口','暖灯书桌','旧磁带','周末午后'],[76,82,70,88],[0,5,2,7],'柔软电钢 · 摇摆鼓点 · 爵士色彩'],
 ['funk',['口袋节拍','橡胶步伐','周五舞步','切分时刻'],[106,112,100,118],[2,7,4,9],'切分贝斯 · 短和弦 · 鬼音军鼓'],
 ['ambient',['远岸','月面漫游','呼吸之间','星际花园'],[64,72,80,68],[0,2,5,9],'长音铺底 · 稀疏钢琴 · 轻打击']
];
export const songPresets:Preset[]=banks.flatMap(([genre,names,bpms,roots,description])=>names.map((name,variant)=>({id:genre+'-'+(variant+1),name,genre,bpm:bpms[variant],root:roots[variant],variant,description})));
export const genreName=(genre:string)=>genres.find(g=>g[0]===genre)?.[1]??genre;
export function presetSession(p:Preset):Session {
 const s=initialSession();Object.assign(s,{name:p.name,bpm:p.bpm,bars:4,root:p.root,scale:'minor',sourcePreset:p.id,instrument:p.genre==='rock'?'guitar':p.genre==='ambient'?'warm':'electric',reverb:p.genre==='ambient'?.48:p.genre==='rock'?.09:.21,delay:p.genre==='ambient'?.12:0,master:.62,tone:p.genre==='lofi'?.38:.7,drumGain:.76,drumEnabled:false,steps:emptySteps(),events:[]});
 let id=0;const add=(kind:MusicEvent['kind'],value:number,beat:number,duration:number,velocity:number,instrument:Instrument='electric')=>{if(beat<16)s.events.push({id:p.id+'-'+id++,kind,value,beat,duration,velocity,instrument});};
 const note=(n:number,b:number,d:number,v=.55,i:Instrument='electric')=>add('note',n,b,d,v,i);
 const drum=(d:number,b:number,v=.65)=>add('drum',d,b,.14,v,'piano');
 const progressions=[[0,8,3,10],[0,5,8,7],[0,10,8,5],[0,3,5,7]];const progression=progressions[p.variant];
 for(let bar=0;bar<4;bar++){
  const t=bar*4,root=48+p.root+progression[bar],bass=root-12;
  if(p.genre==='rock'){
   [0,1.5,2,2.75].forEach(b=>drum(0,t+b,.8));[1,3].forEach(b=>drum(1,t+b,.8));for(let k=0;k<8;k++)drum(k===7?4:3,t+k*.5,k%2?.45:.58);
   [0,.5,1,1.5,2,2.5,3,3.5].forEach((b,j)=>note(bass,t+b,.38,j%2?.57:.69,'bass'));
   [0,1.5,2,3].forEach((b,j)=>[0,7,12].forEach(n=>note(root+n,t+b,j===1?.35:.62,.39,'guitar')));
   if(bar===3)[[5,2.5],[6,2.75],[1,3.25],[1,3.5],[6,3.75]].forEach(([d,b])=>drum(d,t+b,.55));
  } else if(p.genre==='trap'){
   [0,.75,2.5,3.25].forEach(b=>drum(0,t+b,.83));drum(1,t+2,.78);drum(2,t+2,.35);
   for(let k=0;k<16;k++)if(k%2===0||k>11)drum(3,t+k*.25,k%2?.25:.42);if(bar%2)drum(4,t+3.5,.3);
   [0,.75,2.5,3.25].forEach((b,j)=>note(bass-12+(j===3?12:0),t+b,j===1?1.4:.65,.77,'bass'));
   [0,7,3,10,7,12].forEach((n,j)=>note(root+12+n,t+[0,.75,1.5,2.5,3,3.5][j],.28,.32,'pluck'));
   if(bar%2===0)[0,3,7].forEach(n=>note(root+n,t,3.2,.22,'warm'));
  } else if(p.genre==='funk'){
   [0,1.75,2.5].forEach(b=>drum(0,t+b,.78));[1,3].forEach(b=>drum(1,t+b,.7));[.75,2.75,3.75].forEach(b=>drum(1,t+b,.2));for(let k=0;k<16;k++)if(k%4!==3)drum(3,t+k*.25,k%2?.22:.38);
   [0,.75,1.5,1.75,2.5,3.25,3.75].forEach((b,j)=>note(bass+[0,12,0,7,0,10,12][j],t+b,.2,.62,'bass'));
   [.5,1.75,2.5,3.5].forEach(b=>[0,3,7,10].forEach(n=>note(root+12+n,t+b,.18,.31,'electric')));
  } else if(p.genre==='ambient'){
   [0,3,7,14].forEach(n=>note(root+n,t,3.85,.23,'warm'));
   [0,2.5].forEach((b,j)=>note(root+24+[7,14][(bar+j)%2],t+b,1.35,.4,'piano'));
   drum(0,t,.3);drum(7,t+2.75,.13);if(bar%2)drum(4,t+3.5,.14);note(bass,t,3.7,.3,'bass');
  } else {
   const swing=p.genre==='lofi'?.09:.045;
   [0,1.5,2.75].forEach((b,j)=>drum(0,t+b+(bar%2&&j===1?.25:0),.67));[1,3].forEach(b=>drum(1,t+b,.62));if(bar%2)drum(1,t+2.75,.18);
   for(let k=0;k<8;k++)drum(3,t+k*.5+(k%2?swing:0),k%2?.23:.36);if(bar===3)drum(4,t+3.5,.28);
   [0,1.75,2.5,3.5].forEach((b,j)=>note(bass+[0,7,0,10][j],t+b,.45,.51,'bass'));
   [0,2.25].forEach(b=>[0,3,7,p.genre==='lofi'?14:10].forEach(n=>note(root+12+n,t+b,p.genre==='lofi'?1.25:.65,.34,'electric')));
   [.5,1.5,2.75,3.25].forEach((b,j)=>note(root+24+[7,3,10,7][(j+p.variant+bar)%4],t+b,.32,.34,p.genre==='lofi'?'piano':'pluck'));
  }
 }
 return s;
}
export type ClipPreset={id:string;name:string;genre:Genre|'original';bpm:number;beats:number;events:Omit<MusicEvent,'id'>[]};
export const clipPresets:ClipPreset[]=[...clipNames.map((name,i)=>({id:'original-'+i,name,genre:'original' as const,bpm:96,...clipScore(i)})),...songPresets.map(p=>{
 const song=presetSession(p);const kind=p.variant%4;const events=song.events.filter(e=>e.beat<4&&(kind===0?e.kind==='drum':kind===1?e.kind==='note'&&e.instrument==='bass':kind===2?e.kind==='note'&&e.instrument!=='bass':true));
 return {id:p.id,name:p.name+' · '+['鼓组','低音','旋律','合奏'][kind],genre:p.genre,bpm:p.bpm,beats:4,events};
})];
export const getClipPreset=(id:string|undefined,slot:number)=>clipPresets.find(p=>p.id===(id??'original-'+slot))??clipPresets[slot%8];
