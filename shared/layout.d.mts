import type { AnimationDefinition } from "./render-animation.mjs";
import type { Preset } from "./presets.mjs";

export type KeyboardModel = "air75-v3" | "kick75" | "node75-lp" | "node75-hp" | "node100-lp" | "node100-hp" | "air65-v3" | "air100-v3";
export type KeyboardKey = {
  index: number; code: string; label: string;
  x: number; y: number; w: number; h: number;
};
export const LED_COUNT: 84;
export const airLayout: KeyboardKey[];
export const kickLayout: KeyboardKey[];
export let layout: KeyboardKey[];
export function getLayoutModel(): KeyboardModel;
export function setLayoutModel(modelId: KeyboardModel | "air75v3" | "air75-v3-ansi"): KeyboardKey[];
export function getLayoutForModel(modelId?:string): KeyboardKey[];
export function blank(modelId?:string): string[];
export function hsv(h: number, s?: number, v?: number): string;
export function heart(color?: string): string[];
export const defaultAnimation: AnimationDefinition;
export function presets(): Preset[];
