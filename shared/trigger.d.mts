export type TriggerConfig = { code: string; count: number; intervalMs: number; effect?: 'cross'; color?: string; speed?: number };
export type TriggerKey = { code: string; label: string; keyCode: number };
export const DEFAULT_TRIGGER: Readonly<TriggerConfig>;
export const TRIGGER_KEYS: readonly Readonly<TriggerKey>[];
export const TYPING_KEYS: readonly Readonly<TriggerKey>[];
export function validateTrigger(input?: unknown): TriggerConfig;
export function triggerPlaybackConfig(input?: unknown, animation?: {brightness?:number;colorOverride?:string;hueShift?:number}): TriggerConfig;
