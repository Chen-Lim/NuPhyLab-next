import messages from './messages.json';
import {language} from '../i18n';
import {getClipPreset} from './presets';
import type {Clip} from './model';
const catalog=messages as Record<string,string>;
const reverse=Object.fromEntries(Object.entries(catalog).map(([a,b])=>[b,a]));
export function mt(value:string|undefined):string{
 if(!value)return value??'';
 if(language()!=='en')return reverse[value]??value;
 if(Object.hasOwn(catalog,value))return catalog[value];
 if(value.includes(' · ')){const pieces=value.split(' · ');if(pieces.every(p=>Object.hasOwn(catalog,p)))return pieces.map(p=>catalog[p]).join(' · ');}
 const count=value.match(/^(\d+) 首原创作品，从喜欢的节奏开始改编。$/);
 if(count)return catalog['{0} 首原创作品，从喜欢的节奏开始改编。'].replace('{0}',count[1]);
 for(const [key,target] of Object.entries(catalog))if(key.endsWith('：')&&value.startsWith(key))return target+value.slice(key.length);
 return value;
}
// User names never go through a text translator. Only untouched built-in clip labels do.
export function clipLabel(clip:Clip,slot:number){const preset=getClipPreset(clip.preset,slot);return !clip.audio&&clip.name===preset.name?mt(clip.name):clip.name;}
export function musicError(value:string){const translated=mt(value);return language()==='en'&&/[\u3400-\u9fff]/.test(translated)?'The operation could not finish. Your original work is kept. Please try again.':translated;}
