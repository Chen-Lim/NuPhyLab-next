import type {PresetKey} from './presets.mjs';
export const TYPING_CROSS_DURATION_MS:number;
export const MAX_TYPING_CROSS_WAVES:number;
export class TypingCross {
  constructor(keys:readonly PresetKey[]);
  fire(code:string,now:number):boolean;
  render(now:number,config?:{color?:string;speed?:number}):string[];
  clear():void;
  readonly activeWaves:number;
}
export function typingCrossThumbnail(keys:readonly PresetKey[],color?:string):string[];
