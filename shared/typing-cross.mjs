// Approved typing prototype, expressed in physical key-pitch coordinates.
// A wave belongs to one press. Later presses never restart or erase its tail.
export const TYPING_CROSS_DURATION_MS = 800;
export const MAX_TYPING_CROSS_WAVES = 48;
const clamp = value => Math.max(0, Math.min(1, value));
const ease = value => { const x=clamp(value); return x*x*(3-2*x); };
const blank = () => Array(84).fill('#000000');
const center = key => [key.x+key.w/2,key.y+(key.h??1)/2];
function beam(age,distance) {
  const at=age-distance*29;
  if(at<0)return 0;
  const rise=ease(at/17);
  const head=.72*Math.exp(-(((at-24)/30)**2));
  const tail=.61*Math.exp(-Math.max(0,at-30)/155);
  return Math.min(1,rise*(head+tail));
}
function powerFor(key,source,age,pitch) {
  if(age<0||age>=745)return 0;
  const [x,y]=center(key),[sx,sy]=center(source),dx=x-sx,dy=(y-sy)/pitch;
  const horizontal=key.y===source.y?beam(age,Math.max(0,Math.abs(dx)-source.w/2)):0;
  const bandDistance=Math.max(0,Math.abs(dx)-key.w*.24);
  const columnBand=Math.exp(-((bandDistance/(23/57.408))**2)/2);
  return Math.min(1,Math.max(horizontal,columnBand*beam(age,Math.abs(dy)))*(1-ease((age-535)/210)));
}

export class TypingCross {
  constructor(keys) {
    this.keys=keys.map(key=>({...key}));
    this.byCode=new Map(this.keys.map(key=>[key.code,key]));
    if(this.byCode.has('PrintScreen'))this.byCode.set('F13',this.byCode.get('PrintScreen'));
    const rows=[...new Set(this.keys.map(key=>key.y))].sort((a,b)=>a-b);
    const gaps=rows.slice(1).map((y,i)=>y-rows[i]).filter(x=>x>0).sort((a,b)=>a-b);
    this.pitch=gaps[Math.floor(gaps.length/2)]??1;
    this.waves=[];
  }
  fire(code,now) {
    if(!Number.isFinite(now))throw new Error('触发时钟无效');
    const key=this.byCode.get(code);
    if(!key)return false;
    this.waves.push({key,at:now});
    if(this.waves.length>MAX_TYPING_CROSS_WAVES)this.waves.splice(0,this.waves.length-MAX_TYPING_CROSS_WAVES);
    return true;
  }
  render(now,{color='#ffffff',speed=4}={}) {
    if(!Number.isFinite(now))throw new Error('触发时钟无效');
    if(typeof color!=='string'||!/^#[0-9a-f]{6}$/i.test(color))throw new Error('触发颜色必须是有效的 RGB 颜色');
    if(!Number.isFinite(speed)||speed<1||speed>10)throw new Error('触发速度应在 1–10 之间');
    const rate=speed/4;
    this.waves=this.waves.filter(wave=>(now-wave.at)*rate<TYPING_CROSS_DURATION_MS);
    const out=blank(),rgb=[1,3,5].map(at=>parseInt(color.slice(at,at+2),16));
    for(const key of this.keys) {
      let unlit=1;
      for(const wave of this.waves)unlit*=1-powerFor(key,wave.key,(now-wave.at)*rate,this.pitch);
      const power=clamp(1-unlit);
      out[key.index]='#'+rgb.map(byte=>Math.round(byte*power).toString(16).padStart(2,'0')).join('');
    }
    return out;
  }
  clear() {this.waves=[];}
  get activeWaves(){return this.waves.length;}
}

export function typingCrossThumbnail(keys,color='#ffffff') {
  const cross=new TypingCross(keys);
  const code=cross.byCode.has('Space')?'Space':keys[0]?.code;
  if(code)cross.fire(code,0);
  return cross.render(175,{color,speed:4});
}
