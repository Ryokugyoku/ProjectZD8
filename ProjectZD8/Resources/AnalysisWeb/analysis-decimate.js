// Min/max decimation so very long series stay cheap to draw. No DOM access.
import { lowerBound, upperBound } from './analysis-stats.js';

/**
 * Reduces the samples visible in [t0, t1] to at most ~4 points per bucket.
 * Each bucket keeps its first, minimum, maximum and last sample (in time order),
 * so peaks and the connecting line both survive. Short windows are returned as-is.
 * One extra sample on each side keeps the line entering and leaving the window.
 */
export function minMaxDecimate(times, values, t0, t1, buckets) {
  const n = times.length;
  let lo = Math.max(lowerBound(times, t0) - 1, 0);
  let hi = Math.min(upperBound(times, t1) + 1, n);
  const visible = hi - lo;
  if (visible <= 0) return { x: new Float64Array(0), y: new Float64Array(0), idx: new Int32Array(0), count: 0, decimated: false, source: 0 };
  if (visible <= buckets * 2 || !(t1 > t0)) {
    const x = new Float64Array(visible);
    const y = new Float64Array(visible);
    const idx = new Int32Array(visible);
    for (let i = 0; i < visible; i++) { x[i] = times[lo + i]; y[i] = values[lo + i]; idx[i] = lo + i; }
    return { x, y, idx, count: visible, decimated: false, source: visible };
  }
  const scale = buckets / (t1 - t0);
  const out = [];
  let current = -1;
  let first = -1, last = -1, minI = -1, maxI = -1;
  const flush = () => {
    if (current < 0) return;
    const picked = new Set([first, minI, maxI, last]);
    const ordered = Array.from(picked).sort((a, b) => a - b);
    for (const i of ordered) out.push(i);
  };
  for (let i = lo; i < hi; i++) {
    const v = values[i];
    if (!Number.isFinite(v)) continue;
    let b = Math.floor((times[i] - t0) * scale);
    if (b < 0) b = -1;
    if (b >= buckets) b = buckets;
    if (b !== current) {
      flush();
      current = b;
      first = minI = maxI = last = i;
      continue;
    }
    last = i;
    if (v < values[minI]) minI = i;
    if (v > values[maxI]) maxI = i;
  }
  flush();
  const count = out.length;
  const x = new Float64Array(count);
  const y = new Float64Array(count);
  const idx = new Int32Array(count);
  for (let k = 0; k < count; k++) { x[k] = times[out[k]]; y[k] = values[out[k]]; idx[k] = out[k]; }
  return { x, y, idx, count, decimated: true, source: visible };
}

/** Value range of the samples inside [t0, t1], ignoring non-finite values. */
export function visibleRange(times, values, t0, t1) {
  const lo = lowerBound(times, t0);
  const hi = upperBound(times, t1);
  let min = Infinity, max = -Infinity;
  for (let i = lo; i < hi; i++) {
    const v = values[i];
    if (!Number.isFinite(v)) continue;
    if (v < min) min = v;
    if (v > max) max = v;
  }
  return min <= max ? { min, max } : null;
}

/** Indices i where times[i + 1] - times[i] exceeds `gapSeconds` (a break in the line). */
export function findGaps(times, gapSeconds) {
  const out = [];
  for (let i = 0; i + 1 < times.length; i++) if (times[i + 1] - times[i] > gapSeconds) out.push(i);
  return Int32Array.from(out);
}

/** True when a gap index lies in [from, to): the line between those source samples must be broken. */
export function hasGapBetween(gapIndices, from, to) {
  const k = lowerBound(gapIndices, from);
  return k < gapIndices.length && gapIndices[k] < to;
}
