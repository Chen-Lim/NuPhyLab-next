import test from "node:test";
import assert from "node:assert/strict";
import {
  AIR_CONNECTION_WAKE_DURATION_MS,
  renderAirConnectionWake,
} from "../shared/air-connection-wake.mjs";
import { airLayout, getLayoutModel, setLayoutModel } from "../shared/layout.mjs";

const BLACK = "#000000";
const WHITE = "#ffffff";
const rows = Array.from({ length: 6 }, (_, y) => airLayout.filter(key => key.y === y));
const brightness = color => Number.parseInt(color.slice(1, 3), 16);
const isBlack = colors => colors.every(color => color === BLACK);
const peakKey = (colors, keys) => keys.reduce((best, key) =>
  brightness(colors[key.index]) > brightness(colors[best.index]) ? key : best);
const peakX = (colors, row) => {
  const key = peakKey(colors, rows[row]);
  return key.x + key.w / 2;
};

test("wake has a fixed 4.4-second duration and starts and ends completely black", () => {
  assert.equal(AIR_CONNECTION_WAKE_DURATION_MS, 4400);
  assert.equal(airLayout.length, 83);
  assert.deepEqual(rows.map(row => row.length), [15, 15, 15, 14, 14, 10]);
  for (const time of [-100, -1, 0, 4400, 4401, 100000, NaN, Infinity, -Infinity, undefined, null, "100"])
    assert.ok(isBlack(renderAirConnectionWake(time)), `off at ${String(time)}`);
  assert.ok(!isBlack(renderAirConnectionWake(50)));
  assert.ok(!isBlack(renderAirConnectionWake(4350)));
});

test("the two starting corners fade in together before beginning their inward travel", () => {
  const early = renderAirConnectionWake(50);
  const ready = renderAirConnectionWake(100);
  assert.equal(early[0], "#808080");
  assert.equal(early[82], "#808080");
  assert.equal(ready[0], WHITE);
  assert.equal(ready[82], WHITE);
  assert.equal(peakKey(ready, rows[0]).index, 0);
  assert.equal(peakKey(ready, rows[5]).index, 82);
  for (const row of rows.slice(1, 5))
    assert.ok(row.every(key => ready[key.index] === BLACK));
});

test("only the selected row pair lights during each of the three 800ms stages", () => {
  for (const [start, activeRows] of [[0, [0, 5]], [800, [1, 4]], [1600, [2, 3]]]) {
    for (const offset of [50, 400, 750]) {
      const frame = renderAirConnectionWake(start + offset);
      rows.forEach((keys, row) => {
        const lit = keys.some(key => frame[key.index] !== BLACK);
        assert.equal(lit, activeRows.includes(row), `row ${row + 1} at ${start + offset}`);
      });
    }
  }
  for (const [time, activeRows] of [[799, [0, 5]], [800, [1, 4]], [1599, [1, 4]], [1600, [2, 3]]]) {
    const frame = renderAirConnectionWake(time);
    assert.deepEqual(rows.flatMap((row, y) => row.some(key => frame[key.index] !== BLACK) ? [y] : []), activeRows);
  }
});

test("the six row sweeps follow the approved counterflow directions", () => {
  const stages = [
    { early: 100, late: 750, directions: [[0, 1], [5, -1]] },
    { early: 850, late: 1550, directions: [[1, -1], [4, 1]] },
    { early: 1650, late: 2350, directions: [[2, 1], [3, -1]] },
  ];
  for (const { early, late, directions } of stages) {
    const first = renderAirConnectionWake(early);
    const last = renderAirConnectionWake(late);
    for (const [row, direction] of directions) {
      assert.ok((peakX(last, row) - peakX(first, row)) * direction > 8,
        `row ${row + 1} moves ${direction > 0 ? "right" : "left"}`);
    }
  }
});

test("a broad bottom-row gap uses physical key centers rather than key ordinals", () => {
  // At 58% of the first sweep, the right-to-left head is over Space's center.
  // Treating the ten keys as equally spaced would put it near MetaRight instead.
  const frame = renderAirConnectionWake(506);
  assert.equal(peakKey(frame, rows[5]).code, "Space");
  assert.equal(frame[76], WHITE);
  assert.ok(brightness(frame[78]) < 128);
});

test("the final wave crosses the whole keyboard from top-left to bottom-right", () => {
  const start = renderAirConnectionWake(2400);
  const middle = renderAirConnectionWake(3150);
  const finish = renderAirConnectionWake(3900);
  assert.equal(start[0], WHITE);
  assert.equal(start[82], BLACK);
  assert.equal(finish[82], WHITE);
  assert.equal(finish[0], BLACK);
  assert.ok(rows.every(row => row.some(key => middle[key.index] !== BLACK)));
  const middlePeak = peakKey(middle, airLayout);
  assert.ok(middlePeak.y >= 1 && middlePeak.y <= 4);
  assert.ok(middlePeak.x + middlePeak.w / 2 > 2);
  assert.ok(middlePeak.x + middlePeak.w / 2 < 14);
  // The shared diagonal moves to the right within each individual row.
  for (const row of [1, 2, 3, 4])
    assert.ok(peakX(renderAirConnectionWake(3450), row) > peakX(renderAirConnectionWake(2850), row));
});

test("the last 500ms fade the settled diagonal smoothly without a reset", () => {
  const start = renderAirConnectionWake(3900);
  const middle = renderAirConnectionWake(4150);
  const last = renderAirConnectionWake(4350);
  assert.equal(start[82], WHITE);
  assert.equal(middle[82], "#808080");
  assert.ok(brightness(last[82]) > 0 && brightness(last[82]) < 10);
  for (let index = 0; index < 84; index++) {
    assert.ok(brightness(start[index]) >= brightness(middle[index]));
    assert.ok(brightness(middle[index]) >= brightness(last[index]));
  }
  const before = renderAirConnectionWake(3899);
  assert.ok(Math.abs(brightness(before[82]) - brightness(start[82])) <= 1);
});

test("20Hz frames reach maximum white and contain only gray-white tails and mapped key LEDs", () => {
  let sawTail = false;
  const litIndices = new Set();
  for (let time = 0; time <= 4400; time += 50) {
    const frame = renderAirConnectionWake(time);
    assert.equal(frame.length, 84);
    assert.equal(frame[83], BLACK);
    if (time >= 100 && time <= 3900)
      assert.ok(frame.includes(WHITE), `full-white head at ${time}ms`);
    frame.forEach((color, index) => {
      assert.match(color, /^#[0-9a-f]{6}$/);
      assert.equal(color.slice(1, 3), color.slice(3, 5));
      assert.equal(color.slice(3, 5), color.slice(5, 7));
      if (color !== BLACK) litIndices.add(index);
      if (color !== BLACK && color !== WHITE) sawTail = true;
    });
  }
  assert.ok(sawTail);
  assert.deepEqual([...litIndices].sort((a, b) => a - b), airLayout.map(key => key.index).sort((a, b) => a - b));
  // F1–F3 take part in the moving wave, with no persistent status lights.
  const laterPair = renderAirConnectionWake(1200);
  for (const index of [1, 2, 3]) assert.equal(laterPair[index], BLACK);
});

test("rendering is deterministic, returns fresh frames, and never mutates the layout", () => {
  const layoutBefore = structuredClone(airLayout);
  const first = renderAirConnectionWake(1200);
  const expected = first.slice();
  assert.deepEqual(renderAirConnectionWake(1200), expected);
  assert.notEqual(renderAirConnectionWake(1200), first);
  first.fill("#ff0000");
  assert.deepEqual(renderAirConnectionWake(1200), expected);
  assert.deepEqual(airLayout, layoutBefore);
  const oldModel = getLayoutModel();
  try {
    setLayoutModel("kick75");
    assert.deepEqual(renderAirConnectionWake(1200), expected);
    assert.deepEqual(airLayout, layoutBefore);
  } finally {
    setLayoutModel(oldModel);
  }
});
