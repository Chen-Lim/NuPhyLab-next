import raw from './keyboard-geometry.json';
import type { Key } from './types';

export type KeyboardModelId = keyof typeof raw;
export type KeyRect = { x: number; y: number; w: number; h: number };
export type KeyboardControl = KeyRect & {
  id: string;
  kind: 'touch-strip' | 'air-module' | 'dial' | 'side-led';
  sourceIndices: readonly number[];
};
export type KeyboardGeometry = {
  modelId: string;
  title: string;
  family: 'air' | 'kick' | 'node';
  width: number;
  height: number;
  keys: Readonly<Record<string, KeyRect>>;
  keyCodes: Readonly<Record<string, string>>;
  controls: readonly KeyboardControl[];
  topSurface?: {
    width: number; height: number;
    dots: readonly { cx: number; cy: number; r: number }[];
    indicators?: readonly { cx: number; cy: number; r: number }[];
  };
};
/** index belongs to the app's scene model; the renderer never renumbers it. */
export type KeyboardLayoutKey = Key & { sourceIndex?: number };
export const keyboardGeometry = raw as Record<KeyboardModelId, KeyboardGeometry>;

/** Shared with surrounding panels/thumbnails; no key-count inference. */
export function keyboardAspectRatio(modelId: KeyboardModelId, geometry = keyboardGeometry[modelId]): string {
  return `${geometry.width}/${geometry.height}`;
}
/** A viewport wrapper can scroll at compact widths instead of shrinking legends below ~9px. */
export function keyboardInteractiveMinWidth(modelId: KeyboardModelId, geometry = keyboardGeometry[modelId]): number {
  return geometry.width * .58;
}

/** Prevent a stale board/layout pair from creating wrong interactive hit targets. */
export function layoutMatchesGeometry(modelId: string, layout: readonly KeyboardLayoutKey[], geometry: KeyboardGeometry): boolean {
  if (geometry.modelId !== modelId || !Number.isFinite(geometry.width) || !Number.isFinite(geometry.height)
      || geometry.width <= 0 || geometry.height <= 0 || layout.length !== Object.keys(geometry.keys).length) return false;
  const indices = new Set<number>();
  for (const key of layout) {
    const rect = geometry.keys[key.index];
    if (!rect || geometry.keyCodes[key.index] !== key.code || indices.has(key.index) || !Number.isSafeInteger(key.index) || key.index < 0) return false;
    if (![rect.x, rect.y, rect.w, rect.h].every(Number.isFinite) || rect.w <= 0 || rect.h <= 0
        || rect.x < 0 || rect.y < 0 || rect.x + rect.w > geometry.width || rect.y + rect.h > geometry.height) return false;
    indices.add(key.index);
  }
  return true;
}
