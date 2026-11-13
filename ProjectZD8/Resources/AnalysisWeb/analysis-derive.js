// Derived channels: acceleration, rpm/speed ratio with gear clustering, fuel-trim sum, expressions.
// Pure functions over { times, values } channels. No DOM access.
import { alignNearest } from './analysis-join.js';
import { evaluateExpression, parseExpression, refKey, STANDARD_ALIASES } from './analysis-expr.js';

/**
 * Acceleration in m/s^2 from a km/h speed channel. For each sample the slope is taken between the
 * nearest samples at least `minSpan` seconds apart on either side (but within `maxSpan`);
 * samples without such neighbours are left out.
 */
export function accelerationFromSpeed(times, speedKmh, minSpan = 1, maxSpan = 3) {
  const n = times.length;
  const outT = [], outV = [];
  for (let i = 0; i < n; i++) {
    let lo = i, hi = i;
    while (lo > 0 && times[i] - times[lo] < minSpan / 2) lo--;
    while (hi + 1 < n && times[hi] - times[i] < minSpan / 2) hi++;
    const span = times[hi] - times[lo];
    if (hi === lo || span < minSpan * 0.5 || span > maxSpan) continue;
    if (!Number.isFinite(speedKmh[hi]) || !Number.isFinite(speedKmh[lo])) continue;
    outT.push(times[i]);
    outV.push(((speedKmh[hi] - speedKmh[lo]) / span) / 3.6);
  }
  return { times: Float64Array.from(outT), values: Float64Array.from(outV) };
}

/**
 * rpm per km/h at moments where the vehicle is moving (speed >= minSpeed) and the engine turns.
 * Speed is matched to each rpm sample within `tolerance` seconds.
 */
export function rpmSpeedRatio(rpm, speed, tolerance = 1, minSpeed = 5) {
  const aligned = alignNearest(rpm.times, speed.times, speed.values, tolerance);
  const t = [], v = [];
  for (let i = 0; i < rpm.times.length; i++) {
    const s = aligned[i];
    if (Number.isFinite(s) && s >= minSpeed && rpm.values[i] > 300) { t.push(rpm.times[i]); v.push(rpm.values[i] / s); }
  }
  return { times: Float64Array.from(t), values: Float64Array.from(v) };
}

/**
 * Clusters ratio samples into gears by finding peaks of the log-ratio histogram.
 * Gear 1 is the highest ratio. Returns { gears: [{ gear, ratio, count }], assignment: Int8Array }
 * where assignment holds the gear number per sample, or 0 when no cluster is close enough.
 */
export function clusterGears(ratios, { maxGears = 8, binWidth = 0.01, minShare = 0.03, minSeparation = 0.08, assignTolerance = 0.05 } = {}) {
  const logs = [];
  for (let i = 0; i < ratios.length; i++) if (ratios[i] > 0 && Number.isFinite(ratios[i])) logs.push(Math.log(ratios[i]));
  const assignment = new Int8Array(ratios.length);
  if (logs.length < 10) return { gears: [], assignment };
  let lo = Infinity, hi = -Infinity;
  for (const l of logs) { if (l < lo) lo = l; if (l > hi) hi = l; }
  const bins = Math.max(3, Math.ceil((hi - lo) / binWidth) + 1);
  const counts = new Float64Array(bins);
  for (const l of logs) counts[Math.min(bins - 1, Math.floor((l - lo) / binWidth))]++;
  const smooth = new Float64Array(bins);
  for (let b = 0; b < bins; b++) {
    smooth[b] = (counts[Math.max(0, b - 2)] + 2 * counts[Math.max(0, b - 1)] + 3 * counts[b] + 2 * counts[Math.min(bins - 1, b + 1)] + counts[Math.min(bins - 1, b + 2)]) / 9;
  }
  const peaks = [];
  for (let b = 0; b < bins; b++) {
    const left = b > 0 ? smooth[b - 1] : -1;
    const right = b + 1 < bins ? smooth[b + 1] : -1;
    if (smooth[b] > 0 && smooth[b] >= left && smooth[b] > right) peaks.push(b);
  }
  peaks.sort((a, b) => smooth[b] - smooth[a]);
  const chosen = [];
  for (const b of peaks) {
    if (chosen.length >= maxGears) break;
    const logRatio = lo + (b + 0.5) * binWidth;
    if (chosen.every((c) => Math.abs(c - logRatio) >= minSeparation)) chosen.push(logRatio);
  }
  // Refine each centre as the mean of its nearby samples, then drop thin clusters.
  const centres = chosen.map((c) => {
    let sum = 0, count = 0;
    for (const l of logs) if (Math.abs(l - c) <= assignTolerance) { sum += l; count++; }
    return { centre: count ? sum / count : c, count };
  }).filter((c) => c.count >= minShare * logs.length).sort((a, b) => b.centre - a.centre);
  const gears = centres.map((c, i) => ({ gear: i + 1, ratio: Math.exp(c.centre), count: c.count }));
  for (let i = 0; i < ratios.length; i++) {
    if (!(ratios[i] > 0)) continue;
    const l = Math.log(ratios[i]);
    let best = 0, bestDistance = assignTolerance;
    for (const g of gears) {
      const d = Math.abs(l - Math.log(g.ratio));
      if (d <= bestDistance) { best = g.gear; bestDistance = d; }
    }
    assignment[i] = best;
  }
  return { gears, assignment };
}

/** Short-term plus long-term fuel trim (percent), joined on nearest time. */
export function fuelTrimSum(stft, ltft, tolerance = 1) {
  const aligned = alignNearest(stft.times, ltft.times, ltft.values, tolerance);
  const t = [], v = [];
  for (let i = 0; i < stft.times.length; i++) {
    if (Number.isFinite(aligned[i]) && Number.isFinite(stft.values[i])) { t.push(stft.times[i]); v.push(stft.values[i] + aligned[i]); }
  }
  return { times: Float64Array.from(t), values: Float64Array.from(v) };
}

/** Finds the channel a reference points at, or null. `channels` is an array of { id, name, ... }. */
export function resolveReference(ref, channels) {
  if (ref.kind === 'alias') {
    const standard = STANDARD_ALIASES[ref.value];
    if (standard) return channels.find((c) => c.id === standard) || null;
    return channels.find((c) => c.id.toLowerCase() === ref.value || (c.alias && c.alias === ref.value)) || null;
  }
  if (ref.kind === 'pid') {
    const wanted = ref.value.includes('-') ? ref.value : `01-${ref.value}`;
    return channels.find((c) => c.id.toUpperCase() === wanted) || null;
  }
  return channels.find((c) => c.name.toLowerCase() === ref.value.toLowerCase()) || null;
}

/**
 * Evaluates an expression over channels. The first referenced channel provides the time base;
 * the others are matched to it by nearest time within `tolerance`.
 * Returns { times, values, refs } or throws ExpressionError. An unresolved reference throws with code unknownReference.
 */
export function deriveFromExpression(source, channels, tolerance = 1) {
  const parsed = parseExpression(source);
  if (parsed.refs.length === 0) {
    const err = new Error('noReference');
    err.code = 'noReference';
    throw err;
  }
  const resolved = parsed.refs.map((ref) => {
    const channel = resolveReference(ref, channels);
    if (!channel) {
      const err = new Error('unknownReference');
      err.code = 'unknownReference';
      err.detail = ref.value;
      throw err;
    }
    return { ref, channel };
  });
  const base = resolved[0].channel;
  const columns = {};
  for (const { ref, channel } of resolved) {
    columns[refKey(ref)] = channel === base ? Float64Array.from(channel.values) : alignNearest(base.times, channel.times, channel.values, tolerance);
  }
  const values = evaluateExpression(parsed.ast, columns, base.times.length);
  const t = [], v = [];
  for (let i = 0; i < values.length; i++) if (Number.isFinite(values[i])) { t.push(base.times[i]); v.push(values[i]); }
  return { times: Float64Array.from(t), values: Float64Array.from(v), refs: resolved.map((r) => r.channel.id) };
}
