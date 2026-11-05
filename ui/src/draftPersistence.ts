import {getCanvasCount,isKeyboardModel} from '../../shared/keyboard-models.mjs';
import { DEFAULT_ANIMATION } from './types';
import type { Scene } from './types';
import { validateTrigger } from '../../shared/trigger.mjs';

const colorsValid = (value: unknown,count:number): value is string[] => Array.isArray(value) && value.length === count
  && value.every(color => typeof color === 'string' && /^#[0-9a-f]{6}$/i.test(color));

// A damaged or unreadable record must not be replaced by the fallback canvas.
// Drafts may have an empty name or an unfinished, empty frame sequence.
export function parseDraftRecord(raw: string,modelId:string="air75-v3"): Scene {
  const parsed = JSON.parse(raw);
  if(!isKeyboardModel(modelId)|| (parsed?.modelId !== undefined && parsed.modelId !== modelId))throw new Error("Invalid draft model");
  const count=getCanvasCount(modelId);
  if (!parsed || typeof parsed !== 'object' || typeof parsed.name !== 'string' || !colorsValid(parsed.colors,count)
    || !parsed.animation || typeof parsed.animation !== 'object' || Array.isArray(parsed.animation)) throw new Error('Invalid draft');
  const animation = {...DEFAULT_ANIMATION, ...parsed.animation};
  if (animation.effect === 'rainbow') animation.effect = 'static';
  if (!['static','move','pulse','wave','frames'].includes(animation.effect)
    || !['left','right','up','down'].includes(animation.direction)
    || !Number.isFinite(animation.speed) || animation.speed < 1 || animation.speed > 10 || typeof animation.loop !== 'boolean'
    || (animation.hueShift !== undefined && (!Number.isFinite(animation.hueShift) || animation.hueShift < -180 || animation.hueShift > 180))
    || (animation.colorOverride !== undefined && (typeof animation.colorOverride !== 'string' || !/^#[a-f0-9]{6}$/i.test(animation.colorOverride)))
    || (animation.brightness !== undefined && (!Number.isFinite(animation.brightness) || animation.brightness < 0 || animation.brightness > 100))
    || (animation.frames !== undefined && (!Array.isArray(animation.frames) || animation.frames.length > 120
      || animation.frames.some((frame: {colors?: unknown; duration?: number} | null) => !frame || !colorsValid(frame.colors,count)
        || !Number.isFinite(frame.duration) || frame.duration! < 80 || frame.duration! > 10000)))) throw new Error('Invalid draft animation');
  return {...parsed, animation, trigger: parsed.trigger === undefined ? undefined : validateTrigger(parsed.trigger)};
}
