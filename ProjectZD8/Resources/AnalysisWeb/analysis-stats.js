// Pure statistics helpers. No DOM access.

/** Index of the first element >= x in a sorted array (lower bound). */
export function lowerBound(arr, x) {
  let lo = 0, hi = arr.length;
  while (lo < hi) {
    const mid = (lo + hi) >>> 1;
    if (arr[mid] < x) lo = mid + 1; else hi = mid;
  }
  return lo;
}

/** Index of the first element > x in a sorted array (upper bound). */
export function upperBound(arr, x) {
  let lo = 0, hi = arr.length;
  while (lo < hi) {
    const mid = (lo + hi) >>> 1;
    if (arr[mid] <= x) lo = mid + 1; else hi = mid;
  }
  return lo;
}

/** Index of the sample nearest in time to t, or -1 for an empty array. */
export function nearestIndex(times, t) {
  const n = times.length;
  if (n === 0) return -1;
  const i = lowerBound(times, t);
  if (i === 0) return 0;
  if (i === n) return n - 1;
  return (t - times[i - 1]) <= (times[i] - t) ? i - 1 : i;
}

/** Percentile of an ascending array using linear interpolation (R-7). */
export function percentileSorted(sorted, fraction) {
  const n = sorted.length;
  if (n === 0) return NaN;
  if (n === 1) return sorted[0];
  const pos = Math.min(Math.max(fraction, 0), 1) * (n - 1);
  const lo = Math.floor(pos);
  const hi = Math.min(lo + 1, n - 1);
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}

/** Copy of the finite values as an ascending Float64Array. */
export function sortedFinite(values) {
  const out = new Float64Array(values.length);
  let k = 0;
  for (let i = 0; i < values.length; i++) if (Number.isFinite(values[i])) out[k++] = values[i];
  const trimmed = out.subarray(0, k);
  trimmed.sort();
  return trimmed;
}

/**
 * Summary of the samples with t0 <= time <= t1.
 * Returns n = 0 and NaN statistics for an empty window.
 */
export function summarize(times, values, t0 = -Infinity, t1 = Infinity) {
  const lo = lowerBound(times, t0);
  const hi = upperBound(times, t1);
  const picked = [];
  for (let i = lo; i < hi; i++) if (Number.isFinite(values[i])) picked.push(i);
  const n = picked.length;
  if (n === 0) {
    return { n: 0, min: NaN, max: NaN, mean: NaN, median: NaN, p05: NaN, p95: NaN, std: NaN, slope: NaN };
  }
  let mean = 0, m2 = 0, count = 0, min = Infinity, max = -Infinity;
  const vals = new Float64Array(n);
  for (let k = 0; k < n; k++) {
    const v = values[picked[k]];
    vals[k] = v;
    count++;
    const delta = v - mean;
    mean += delta / count;
    m2 += delta * (v - mean);
    if (v < min) min = v;
    if (v > max) max = v;
  }
  vals.sort();
  const std = n > 1 ? Math.sqrt(m2 / (n - 1)) : NaN;
  let slope = NaN;
  if (n > 1) {
    const xs = new Float64Array(n);
    const ys = new Float64Array(n);
    for (let k = 0; k < n; k++) { xs[k] = times[picked[k]]; ys[k] = values[picked[k]]; }
    slope = linearRegression(xs, ys).slope;
  }
  return {
    n, min, max, mean,
    median: percentileSorted(vals, 0.5),
    p05: percentileSorted(vals, 0.05),
    p95: percentileSorted(vals, 0.95),
    std, slope,
  };
}

/** Ordinary least squares y = slope * x + intercept with r squared. */
export function linearRegression(xs, ys) {
  let n = 0, mx = 0, my = 0;
  for (let i = 0; i < xs.length; i++) {
    if (!Number.isFinite(xs[i]) || !Number.isFinite(ys[i])) continue;
    n++;
    mx += xs[i];
    my += ys[i];
  }
  if (n < 2) return { n, slope: NaN, intercept: NaN, r2: NaN };
  mx /= n;
  my /= n;
  let sxx = 0, sxy = 0, syy = 0;
  for (let i = 0; i < xs.length; i++) {
    if (!Number.isFinite(xs[i]) || !Number.isFinite(ys[i])) continue;
    const dx = xs[i] - mx;
    const dy = ys[i] - my;
    sxx += dx * dx;
    sxy += dx * dy;
    syy += dy * dy;
  }
  if (sxx === 0) return { n, slope: NaN, intercept: NaN, r2: NaN };
  const slope = sxy / sxx;
  const r2 = syy === 0 ? 1 : (sxy * sxy) / (sxx * syy);
  return { n, slope, intercept: my - slope * mx, r2 };
}

/** Histogram over [min, max] with equal-width bins; the max value falls in the last bin. */
export function histogram(values, { bins = 30, min, max } = {}) {
  let lo = min, hi = max;
  if (lo === undefined || hi === undefined) {
    lo = Infinity; hi = -Infinity;
    for (let i = 0; i < values.length; i++) {
      const v = values[i];
      if (!Number.isFinite(v)) continue;
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
  }
  const counts = new Float64Array(bins);
  if (!Number.isFinite(lo) || !Number.isFinite(hi)) return { edges: new Float64Array(bins + 1), counts, min: NaN, max: NaN, binWidth: NaN, total: 0 };
  if (hi === lo) { hi = lo + 1; }
  const width = (hi - lo) / bins;
  let total = 0;
  for (let i = 0; i < values.length; i++) {
    const v = values[i];
    if (!Number.isFinite(v) || v < lo || v > hi) continue;
    let b = Math.floor((v - lo) / width);
    if (b >= bins) b = bins - 1;
    counts[b]++;
    total++;
  }
  const edges = new Float64Array(bins + 1);
  for (let b = 0; b <= bins; b++) edges[b] = lo + b * width;
  return { edges, counts, min: lo, max: hi, binWidth: width, total };
}

/** Tukey box plot statistics (whiskers at 1.5 IQR, clamped to data). */
export function boxStats(values) {
  const sorted = sortedFinite(values);
  const n = sorted.length;
  if (n === 0) return { n: 0, min: NaN, q1: NaN, median: NaN, q3: NaN, max: NaN, lowWhisker: NaN, highWhisker: NaN, outliers: 0 };
  const q1 = percentileSorted(sorted, 0.25);
  const median = percentileSorted(sorted, 0.5);
  const q3 = percentileSorted(sorted, 0.75);
  const iqr = q3 - q1;
  const loFence = q1 - 1.5 * iqr;
  const hiFence = q3 + 1.5 * iqr;
  let lowWhisker = sorted[0], highWhisker = sorted[n - 1], outliers = 0;
  for (let i = 0; i < n; i++) if (sorted[i] >= loFence) { lowWhisker = sorted[i]; break; }
  for (let i = n - 1; i >= 0; i--) if (sorted[i] <= hiFence) { highWhisker = sorted[i]; break; }
  for (let i = 0; i < n; i++) if (sorted[i] < loFence || sorted[i] > hiFence) outliers++;
  return { n, min: sorted[0], q1, median, q3, max: sorted[n - 1], lowWhisker, highWhisker, outliers };
}

/** "Nice" axis ticks covering [min, max] with roughly `count` intervals. */
export function niceTicks(min, max, count = 5) {
  if (!Number.isFinite(min) || !Number.isFinite(max)) return [];
  if (min === max) return [min];
  const span = max - min;
  const rough = span / Math.max(count, 1);
  const magnitude = Math.pow(10, Math.floor(Math.log10(rough)));
  const residual = rough / magnitude;
  const step = (residual >= 7.5 ? 10 : residual >= 3.5 ? 5 : residual >= 1.5 ? 2 : 1) * magnitude;
  const ticks = [];
  const start = Math.ceil(min / step - 1e-9) * step;
  for (let v = start; v <= max + step * 1e-9; v += step) ticks.push(Math.abs(v) < step * 1e-9 ? 0 : v);
  return ticks;
}

/** Time ticks (seconds) with steps that fall on minutes/hours when the span is long. */
export function niceTimeTicks(min, max, count = 6) {
  const span = max - min;
  if (!(span > 0)) return [];
  const steps = [0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200, 14400, 21600, 43200, 86400];
  const rough = span / count;
  let step = steps[steps.length - 1];
  for (const s of steps) if (s >= rough) { step = s; break; }
  const ticks = [];
  for (let v = Math.ceil(min / step) * step; v <= max + 1e-9; v += step) ticks.push(v);
  return ticks;
}

/** Median of the positive consecutive differences of an ascending array. */
export function medianInterval(times) {
  const diffs = [];
  for (let i = 1; i < times.length; i++) {
    const d = times[i] - times[i - 1];
    if (d > 0) diffs.push(d);
  }
  if (diffs.length === 0) return NaN;
  diffs.sort((a, b) => a - b);
  return percentileSorted(diffs, 0.5);
}
