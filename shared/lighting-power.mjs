export const MAX_LIGHT_TIME_MS = 86_400_000;
export const DEFAULT_LIGHT_TIME_MS = 3_600_000;
export function validLightTime(value, {allowOff = true, maximum = MAX_LIGHT_TIME_MS} = {}) {
  return Number.isInteger(value) && ((allowOff && value === 0) || (value >= 1000 && value <= maximum));
}
export function lightingTimerDeadline(power = {}, settings = {}) {
  const durationRemainingMs = settings.lightDurationMs > 0 && Number.isFinite(power.remainingMs)
    ? Math.max(0, power.remainingMs) : null;
  const idleRemainingMs = settings.lightIdleMs > 0 && Number.isFinite(power.idleMs)
    ? Math.max(0, settings.lightIdleMs - power.idleMs) : null;
  const idleFirst = idleRemainingMs !== null && (durationRemainingMs === null || idleRemainingMs < durationRemainingMs);
  return {durationRemainingMs, idleRemainingMs,
    nextSleepInMs:power.sleeping ? 0 : idleFirst ? idleRemainingMs : durationRemainingMs,
    nextSleepReason:power.sleeping ? power.reason ?? null : idleFirst ? 'idle' : durationRemainingMs !== null ? 'duration' : null};
}
export class LightingPower {
  constructor(now = () => performance.now()) {
    this.now = now; this.startedAt = now(); this.lastActivity = now();
    this.sleeping = false; this.reason = null; this.codexSignature = null;
  }
  wake() { this.startedAt = this.lastActivity = this.now(); this.sleeping = false; this.reason = null; }
  activity() {
    this.lastActivity = this.now();
    if (this.sleeping && this.reason === 'idle') { this.sleeping = false; this.reason = null; }
  }
  observeSystemIdle(ms) {
    if (Number.isFinite(ms) && ms >= 0) this.lastActivity = Math.max(this.lastActivity, this.now() - ms);
  }
  observeCodex(signature) {
    if (this.codexSignature !== null && signature !== this.codexSignature) this.activity();
    this.codexSignature = signature;
  }
  update(settings, eligible = true) {
    if (!eligible) { this.wake(); return this.snapshot(settings); }
    const now = this.now(), duration = settings.lightDurationMs ?? 0, idle = settings.lightIdleMs ?? 0;
    // Idle activity resumes this session; only an explicit wake starts another
    // duration. The fixed deadline also expires while the session is idle.
    if (duration > 0 && now - this.startedAt >= duration) { this.sleeping = true; this.reason = 'duration'; }
    else {
      if (this.sleeping && this.reason === 'idle' && (!idle || now - this.lastActivity < idle)) {
        this.sleeping = false; this.reason = null;
      }
      if (!this.sleeping && idle > 0 && now - this.lastActivity >= idle) { this.sleeping = true; this.reason = 'idle'; }
    }
    return this.snapshot(settings);
  }
  snapshot(settings = {}) {
    const now = this.now();
    const state = {sleeping:this.sleeping, reason:this.reason,
      remainingMs: settings.lightDurationMs ? Math.max(0,settings.lightDurationMs-(now-this.startedAt)) : null,
      idleMs: Math.max(0,now-this.lastActivity)};
    return {...state,...lightingTimerDeadline(state,settings)};
  }
}
