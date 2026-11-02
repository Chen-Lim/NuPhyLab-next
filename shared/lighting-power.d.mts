export const MAX_LIGHT_TIME_MS: number;
export const DEFAULT_LIGHT_TIME_MS: number;
export interface LightTimeSettings { lightDurationMs?: number; lightIdleMs?: number }
export interface LightTimerDeadline {
  durationRemainingMs: number | null;
  idleRemainingMs: number | null;
  nextSleepInMs: number | null;
  nextSleepReason: "duration" | "idle" | null;
}
export interface LightPowerState extends LightTimerDeadline {
  sleeping: boolean;
  reason: "duration" | "idle" | null;
  remainingMs: number | null;
  idleMs: number;
}
export function validLightTime(value: unknown, options?: {allowOff?: boolean; maximum?: number}): boolean;
export function lightingTimerDeadline(power?: {remainingMs?:number|null;idleMs?:number;sleeping?:boolean;reason?:"duration"|"idle"|null}, settings?: LightTimeSettings): LightTimerDeadline;
export class LightingPower {
  constructor(now?: () => number);
  sleeping: boolean;
  reason: "duration" | "idle" | null;
  wake(): void;
  activity(): void;
  observeSystemIdle(ms: number): void;
  observeCodex(signature: string): void;
  update(settings: LightTimeSettings, eligible?: boolean): LightPowerState;
  snapshot(settings?: LightTimeSettings): LightPowerState;
}
