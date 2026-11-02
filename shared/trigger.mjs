import keys from "./trigger-keys.json" with { type: "json" };
import {applyArtworkAppearance} from './render-animation.mjs';

export const DEFAULT_TRIGGER = Object.freeze({
  code: "Space",
  count: 3,
  intervalMs: 600,
});
export const TRIGGER_KEYS = Object.freeze(keys.map((key) => Object.freeze({ ...key })));
export const TYPING_KEYS = Object.freeze([...TRIGGER_KEYS,
  {code:'CapsLock',label:'Caps',keyCode:57},
  {code:'ShiftLeft',label:'Shift',keyCode:56},{code:'ShiftRight',label:'Shift',keyCode:60},
  {code:'ControlLeft',label:'Ctrl',keyCode:59},{code:'ControlRight',label:'Ctrl',keyCode:62},
  {code:'AltLeft',label:'Opt',keyCode:58},{code:'AltRight',label:'Opt',keyCode:61},
  {code:'MetaLeft',label:'Cmd',keyCode:55},{code:'MetaRight',label:'Cmd',keyCode:54},
  {code:'Fn',label:'Fn',keyCode:63},{code:'PrintScreen',label:'Print',keyCode:105},
].map(key=>Object.freeze({...key})));
const codes = new Set(TRIGGER_KEYS.map((key) => key.code));

export function validateTrigger(input = {}) {
  if (!input || typeof input !== "object" || Array.isArray(input))
    throw new Error("按键触发设置格式无效");
  for (const key of Object.keys(input))
    if (!["code", "count", "intervalMs", "effect", "color", "speed"].includes(key))
      throw new Error("不支持的按键触发设置项：" + key);
  const config = { ...DEFAULT_TRIGGER, ...input };
  if (config.effect !== undefined && config.effect !== 'cross') throw new Error('不支持的按键触发灯效');
  if (config.effect === 'cross') {
    config.color ??= '#ffffff';
    config.speed ??= 4;
    if (typeof config.color !== 'string' || !/^#[0-9a-f]{6}$/i.test(config.color))
      throw new Error('触发颜色必须是有效的 RGB 颜色');
    if (!Number.isFinite(config.speed) || config.speed < 1 || config.speed > 10)
      throw new Error('触发速度应在 1–10 之间');
    config.color = config.color.toLowerCase();
  } else if (config.color !== undefined || config.speed !== undefined) {
    throw new Error('此触发效果不支持颜色或速度设置');
  }
  if (!codes.has(config.code)) throw new Error("请选择支持的触发按键");
  if (!Number.isInteger(config.count) || config.count < 1 || config.count > 20)
    throw new Error("闪烁次数应为 1–20 次");
  if (!Number.isInteger(config.intervalMs) || config.intervalMs < 200 || config.intervalMs > 2000)
    throw new Error("每次闪烁时长应为 200–2000 毫秒");
  return config;
}

// Shared by Library, Studio and previews: saved raw settings keep their colour,
// while the submitted cross receives the same artwork appearance as its canvas.
export function triggerPlaybackConfig(input, animation = {}) {
  const config = validateTrigger(input);
  return config.effect === 'cross'
    ? {...config, color:applyArtworkAppearance([config.color], animation)[0]}
    : config;
}
