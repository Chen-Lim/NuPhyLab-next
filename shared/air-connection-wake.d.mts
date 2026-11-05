export const AIR_CONNECTION_WAKE_DURATION_MS: 4400;
/** Pure Air75 V3 wake renderer; returns 84 RGB HEX slots, with slot 83 black. */
export function renderAirConnectionWake(elapsedMs: number): string[];

export function renderConnectionWake(modelId:string,elapsedMs:number):string[];
