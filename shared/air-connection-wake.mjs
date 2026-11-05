import {airLayout,getLayoutForModel} from './layout.mjs';
import {getCanvasCount} from './keyboard-models.mjs';

// The approved 2.2-second choreography plays at half speed.
export const AIR_CONNECTION_WAKE_DURATION_MS = 4400;
const PLAYBACK_SPEED = 0.5;
const ROW_STAGE_MS = 400;
const DIAGONAL_START_MS = 1200;
const FADE_START_MS = 1950;
const BASE_DURATION_MS = 2200;
const START_FADE_MS = 50;

const clamp = value => Math.max(0, Math.min(1, value));
const ease = value => {
  const t = clamp(value);
  return t * t * (3 - 2 * t);
};

function createRenderer(layout,count) {
// Capture geometry without sorting or rewriting the shared physical layout.
const keyCenters = layout.map(key => ({
  index: key.index,
  row: key.y,
  x: key.x + key.w / 2,
}));
const left = Math.min(...keyCenters.map(key => key.x));
const right = Math.max(...keyCenters.map(key => key.x));
const top = Math.min(...keyCenters.map(key => key.row));
const bottom = Math.max(...keyCenters.map(key => key.row));
const physicalRows = [...new Set(keyCenters.map(key=>key.row))].sort((a,b)=>a-b);
const rows = physicalRows.map(row => {
  const keys = keyCenters.filter(key => key.row === row);
  const rowLeft = Math.min(...keys.map(key => key.x));
  const rowRight = Math.max(...keys.map(key => key.x));
  return keys.map(key => ({
    ...key,
    rowPosition: (key.x - rowLeft) / (rowRight - rowLeft || 1),
  }));
});
const diagonalKeys = keyCenters.map(key => ({
  ...key,
  diagonalPosition: ((key.x - left) / (right - left)
    + (key.row - top) / (bottom - top)) / 2,
}));

function wavePower(gap, width, tailPower, tailLength) {
  const front = Math.exp(-0.5 * (gap / width) ** 2);
  const tail = gap > 0 ? tailPower * Math.exp(-gap / tailLength) : 0;
  return Math.min(1, front + tail);
}

function writeWhiteWave(colors, powers, envelope = 1) {
  // Keep a full-white head as it crosses unequal key widths and the space bar.
  // The rest of the wave retains the relative gray-white falloff.
  const peak = Math.max(...powers.map(key => key.power));
  if (peak <= 0) return;
  for (const { index, power } of powers) {
    const byte = Math.round(255 * clamp(power / peak * envelope))
      .toString(16).padStart(2, "0");
    colors[index] = `#${byte}${byte}${byte}`;
  }
}

/**
 * Render one Air75 V3 connection-wake frame as 84 RGB HEX slots.
 * Times are elapsed wall-clock milliseconds, including the half-speed playback.
 * Only the 83 mapped key LEDs participate; slot 83 is always black.
 */
return function render(elapsedMs) {
  const colors = Array(count).fill("#000000");
  if (!Number.isFinite(elapsedMs) || elapsedMs <= 0
    || elapsedMs >= AIR_CONNECTION_WAKE_DURATION_MS) return colors;

  const time = elapsedMs * PLAYBACK_SPEED;
  if (time < DIAGONAL_START_MS) {
    const stageMs=DIAGONAL_START_MS/Math.ceil(rows.length/2);
    const group = Math.floor(time / stageMs);
    const local = time - group * stageMs;
    const startDelay = group === 0 ? START_FADE_MS : 0;
    const progress = clamp((local - startDelay) / (stageMs - startDelay));
    const envelope = ease(time / START_FADE_MS);
    for (const row of new Set([group, rows.length - 1 - group])) {
      // Upper rows alternate right/left/right; lower rows mirror them.
      const reverse = (group === 1) !== (row >= Math.ceil(rows.length/2));
      const powers = rows[row].map(key => ({
        index: key.index,
        power: wavePower(progress - (reverse ? 1 - key.rowPosition : key.rowPosition),
          0.055, 0.24, 0.11),
      }));
      writeWhiteWave(colors, powers, envelope);
    }
  } else {
    const progress = clamp((time - DIAGONAL_START_MS) / (FADE_START_MS - DIAGONAL_START_MS));
    const envelope = 1 - ease((time - FADE_START_MS) / (BASE_DURATION_MS - FADE_START_MS));
    const powers = diagonalKeys.map(key => ({
      index: key.index,
      power: wavePower(progress - key.diagonalPosition, 0.065, 0.16, 0.12),
    }));
    writeWhiteWave(colors, powers, envelope);
  }
  return colors;
}

}
const renderers = new Map([['air75-v3',createRenderer(airLayout,84)]]);
export const renderAirConnectionWake = elapsedMs => renderers.get('air75-v3')(elapsedMs);
export function renderConnectionWake(modelId,elapsedMs) {
  if(!renderers.has(modelId))renderers.set(modelId,createRenderer(getLayoutForModel(modelId),getCanvasCount(modelId)));
  return renderers.get(modelId)(elapsedMs);
}
