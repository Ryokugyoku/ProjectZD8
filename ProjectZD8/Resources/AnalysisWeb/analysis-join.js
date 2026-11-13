// Nearest-time joins between channels sampled at different instants. No DOM access.

/**
 * For every base time, the value of the channel (t, v) nearest in time within `tolerance` seconds.
 * Base times without a close-enough sample get NaN: missing values are never invented.
 */
export function alignNearest(baseTimes, t, v, tolerance) {
  const out = new Float64Array(baseTimes.length).fill(NaN);
  const n = t.length;
  if (n === 0) return out;
  let j = 0;
  for (let i = 0; i < baseTimes.length; i++) {
    const bt = baseTimes[i];
    while (j + 1 < n && t[j + 1] <= bt) j++;
    let best = j;
    if (j + 1 < n && Math.abs(t[j + 1] - bt) < Math.abs(t[j] - bt)) best = j + 1;
    if (Math.abs(t[best] - bt) <= tolerance && Number.isFinite(v[best])) out[i] = v[best];
  }
  return out;
}

/**
 * Pairs every sample of A with the nearest sample of B within the tolerance.
 * Pairs without a partner are dropped. Returns parallel typed arrays.
 */
export function nearestJoin(tA, vA, tB, vB, tolerance) {
  const aligned = alignNearest(tA, tB, vB, tolerance);
  let k = 0;
  for (let i = 0; i < tA.length; i++) if (Number.isFinite(aligned[i]) && Number.isFinite(vA[i])) k++;
  const t = new Float64Array(k), a = new Float64Array(k), b = new Float64Array(k);
  k = 0;
  for (let i = 0; i < tA.length; i++) {
    if (!Number.isFinite(aligned[i]) || !Number.isFinite(vA[i])) continue;
    t[k] = tA[i]; a[k] = vA[i]; b[k] = aligned[i];
    k++;
  }
  return { t, a, b, n: k };
}

/**
 * Joins X with Y (required) and an optional third channel Z.
 * Rows lacking X or Y are dropped; a missing Z stays NaN so colouring can skip it.
 */
export function joinXYZ(x, y, z, tolerance, t0 = -Infinity, t1 = Infinity) {
  const rows = [];
  for (let i = 0; i < x.times.length; i++) if (x.times[i] >= t0 && x.times[i] <= t1) rows.push(i);
  const bt = new Float64Array(rows.length);
  const bx = new Float64Array(rows.length);
  rows.forEach((r, k) => { bt[k] = x.times[r]; bx[k] = x.values[r]; });
  const ay = alignNearest(bt, y.times, y.values, tolerance);
  const az = z ? alignNearest(bt, z.times, z.values, tolerance) : null;
  let count = 0;
  for (let k = 0; k < rows.length; k++) if (Number.isFinite(bx[k]) && Number.isFinite(ay[k])) count++;
  const out = { t: new Float64Array(count), x: new Float64Array(count), y: new Float64Array(count), z: new Float64Array(count).fill(NaN), n: count };
  let w = 0;
  for (let k = 0; k < rows.length; k++) {
    if (!Number.isFinite(bx[k]) || !Number.isFinite(ay[k])) continue;
    out.t[w] = bt[k]; out.x[w] = bx[k]; out.y[w] = ay[k];
    if (az) out.z[w] = az[k];
    w++;
  }
  return out;
}

/** Seconds each sample "covers": the gap to the next sample, capped at twice the median gap. */
export function sampleWeights(times) {
  const n = times.length;
  const w = new Float64Array(n);
  if (n === 0) return w;
  const diffs = [];
  for (let i = 1; i < n; i++) if (times[i] > times[i - 1]) diffs.push(times[i] - times[i - 1]);
  diffs.sort((a, b) => a - b);
  const median = diffs.length ? diffs[diffs.length >> 1] : 1;
  const cap = median * 2;
  for (let i = 0; i < n; i++) {
    const gap = i + 1 < n ? times[i + 1] - times[i] : median;
    w[i] = Math.min(Math.max(gap, 0), cap);
  }
  return w;
}
