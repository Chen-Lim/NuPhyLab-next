import heartKeys from "./heart-keys.json" with { type: "json" };
import {typingCrossThumbnail} from './typing-cross.mjs';

export const DEFAULT_COLOR = "#dc847b";
const BLACK = "#000000";
const blank = () => Array(84).fill(BLACK);
const animation = (effect = "static", frames = [], speed = 4) => ({
  effect,
  direction: "right",
  speed,
  loop: true,
  frames,
});
const center = (key) => [key.x + key.w / 2, key.y + (key.h ?? 1) / 2];

export function heartColors(keys, color = DEFAULT_COLOR) {
  const colors = blank();
  const hasRightMeta = keys.some((key) => key.code === "MetaRight");
  for (const key of keys)
    if (heartKeys.includes(key.code) || (!hasRightMeta && key.code === "AltRight"))
      colors[key.index] = color;
  return colors;
}

// Five rows of ordinary keycaps give each graphic a legible silhouette without
// stretching its bottom pixel across the six-unit Space key. Snap each point
// onto the actual row's key centers instead of treating this as a square grid.
function stencil(keys, rows, color) {
  const colors = blank();
  const physicalRows = [...new Set(keys.map((key) => key.y))].sort((a, b) => a - b);
  rows.forEach((row, y) => {
    const candidates = keys.filter((key) => key.y === physicalRows[y] && key.w <= 1.5);
    [...row].forEach((pixel, x) => {
      if (pixel !== "#") return;
      const targetX = 5.5 + x;
      const key = candidates.reduce((best, current) => {
        const distance = Math.abs(center(current)[0] - targetX);
        return !best || distance < best.distance
          ? { key: current, distance }
          : best;
      }, null);
      if (key && key.distance <= 0.6) colors[key.key.index] = color;
    });
  });
  return colors;
}

function tint(hex, amount) {
  if (amount < 0.045) return BLACK;
  const level = Math.min(1, Math.max(0, amount));
  return "#" + [1, 3, 5].map((start) =>
    Math.round(parseInt(hex.slice(start, start + 2), 16) * level)
      .toString(16).padStart(2, "0"),
  ).join("");
}

function framesFor(keys, count, duration, render) {
  return Array.from({ length: count }, (_, frame) => {
    const colors = blank();
    for (const key of keys) colors[key.index] = render(key, frame / count);
    return { colors, duration };
  });
}

function movingPreset(id, name, description, frames, previewFrame) {
  return {
    id,
    name,
    category: "motion",
    description,
    colors: frames[previewFrame].colors.slice(),
    animation: animation("frames", frames),
  };
}

export function createPresets(keys) {
  const graphic = (id, name, description, colors, render, count = 40, duration = 100) => ({
    id, name, category: "pattern", description, colors,
    animation: animation("frames", framesFor(keys, count, duration, render)),
  });
  const mix = (a, b, amount) => "#" + [1, 3, 5].map(start => {
    const left = parseInt(a.slice(start, start + 2), 16);
    const right = parseInt(b.slice(start, start + 2), 16);
    return Math.round(left + (right - left) * amount).toString(16).padStart(2, "0");
  }).join("");
  const cycle = phase => (1 - Math.cos(phase * Math.PI * 2)) / 2;
  const star = stencil(keys, [
    "...#...", "#######", ".#####.", "..#.#..", ".#...#.",
  ], "#efc366");
  const wings = stencil(keys, [
    "##...##", "###.###", ".#####.", ".##.##.", ".#...#.",
  ], "#d68bb5");
  const folded = stencil(keys, [
    "..#.#..", "..###..", "...#...", "..###..", "..#.#..",
  ], "#d68bb5");

  const points = keys.map(center);
  const minX = points.length ? Math.min(...points.map(([x]) => x)) : 0.5;
  const maxX = points.length ? Math.max(...points.map(([x]) => x)) : 15.5;
  const midX = (minX + maxX) / 2;

  const comet = framesFor(keys, 32, 100, (key, phase) => {
    const [x, y] = center(key);
    const headX = minX - 2 + phase * (maxX - minX + 9);
    const behind = headX - x;
    const offTrack = Math.abs(y - 2.5);
    const head = Math.max(0, 1 - Math.hypot(behind, offTrack) / 1.25);
    const tail = behind >= 0 && behind <= 4.5 && offTrack <= 0.7
      ? (1 - behind / 4.5) * 0.72 : 0;
    return tint("#92cddd", Math.max(head, tail));
  });


  const rainColumns = [1, 3.4, 5.8, 8.2, 10.6, 13, 15];
  const rain = framesFor(keys, 28, 120, (key, phase) => {
    const [x, y] = center(key);
    let glow = 0;
    rainColumns.forEach((column, index) => {
      const headY = -2 + ((phase + index * 0.267) % 1) * 10;
      const behind = headY - y;
      if (Math.abs(x - column) <= 0.66 && behind >= -0.55 && behind <= 2.2)
        glow = Math.max(glow, behind < 0 ? 1 + behind : 1 - behind / 2.5);
    });
    return tint("#dfb475", glow);
  });

  const scan = framesFor(keys, 32, 100, (key, phase) => {
    const [x] = center(key);
    const scanX = midX - Math.cos(phase * Math.PI * 2) * ((maxX - minX) / 2 + 1.5);
    const glow = Math.max(0, 1 - Math.abs(x - scanX) / 1.45);
    return tint("#8fc4b0", glow);
  });

  return [
    {
      id: "heart", name: "一颗小心意", category: "pattern",
      description: "熟悉的右侧爱心，缓缓亮起，再轻轻暗下。",
      colors: heartColors(keys), animation: animation("pulse", [], 2),
    },
    graphic("star", "星光闪闪", "金色星芒依次闪耀，轮廓始终清晰。", star, (key, phase) => {
      const [x, y] = center(key);
      return tint(star[key.index], 0.32 + 0.68 * cycle(phase + Math.atan2(y - 2.5, x - 8.5) / (Math.PI * 2)));
    }),
    graphic("butterfly", "蝴蝶振翅", "粉紫色的翅膀轻轻收拢，再慢慢展开。", wings, (key, phase) =>
      mix(wings[key.index], folded[key.index], cycle(phase)), 32, 100),
    movingPreset("comet", "流星划过", "冰蓝光点拖着尾巴，从左向右划过。", comet, 14),
    movingPreset("scan", "青绿扫描", "一束青绿色灯光在左右之间往返。", scan, 8),
    movingPreset("rain", "琥珀落雨", "琥珀色光滴带着短尾，自上而下落下。", rain, 10),
    {
      id:'typing-cross',name:'一石二鸟',category:'motion',
      description:'按任意键，从对应位置向横纵扩散，连续按键独立叠加。',
      colors:typingCrossThumbnail(keys),animation:animation(),
      trigger:{code:'Space',count:3,intervalMs:600,effect:'cross',color:'#ffffff',speed:4},
    },
  ];
}
