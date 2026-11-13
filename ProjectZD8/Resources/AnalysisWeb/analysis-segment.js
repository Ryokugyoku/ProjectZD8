// Drive segmentation and event detection from speed (and optionally rpm). No DOM access.
import { alignNearest } from './analysis-join.js';
import { percentileSorted, sortedFinite } from './analysis-stats.js';

export const SEGMENT_TYPES = ['stop', 'idle', 'acceleration', 'cruise', 'deceleration'];

export const DEFAULT_SEGMENT_OPTIONS = {
  step: 1,                 // seconds between analysis grid points
  maxGap: 3,               // seconds without speed samples before the grid point is "unknown"
  accelThreshold: 0.5,     // m/s^2 beyond which a point counts as accelerating / decelerating
  stopSpeed: 1,            // km/h below which the vehicle is standing
  engineOnRpm: 300,        // rpm above which a standing vehicle is idling rather than stopped
  minDuration: 3,          // segments shorter than this (seconds) are absorbed by a neighbour
};

/**
 * Speed on a regular grid. Linear interpolation is used only between two real samples that are
 * at most `maxGap` seconds apart; elsewhere the grid value is NaN (unknown).
 */
export function speedGrid(times, speedKmh, step, maxGap) {
  const n = times.length;
  if (n === 0) return { t0: 0, step, values: new Float64Array(0) };
  const t0 = Math.ceil(times[0] / step) * step;
  const count = Math.max(0, Math.floor((times[n - 1] - t0) / step) + 1);
  const values = new Float64Array(count).fill(NaN);
  let j = 0;
  for (let k = 0; k < count; k++) {
    const t = t0 + k * step;
    while (j + 1 < n && times[j + 1] < t) j++;
    if (times[j] >= t) {
      if (times[j] === t) values[k] = speedKmh[j];
      continue;
    }
    if (j + 1 >= n) break;
    const ta = times[j], tb = times[j + 1];
    if (tb - ta > maxGap || !Number.isFinite(speedKmh[j]) || !Number.isFinite(speedKmh[j + 1])) continue;
    const w = (t - ta) / (tb - ta);
    values[k] = speedKmh[j] + (speedKmh[j + 1] - speedKmh[j]) * w;
  }
  return { t0, step, values };
}

/**
 * Splits a drive into stop / idle / acceleration / cruise / deceleration segments.
 * `speed` and optional `rpm` are { times, values } channels (km/h, rpm).
 * Returns ascending, non-overlapping segments [{ type, t0, t1 }]; unknown stretches are left out.
 */
export function segmentDrive(speed, rpm, options = {}) {
  const o = { ...DEFAULT_SEGMENT_OPTIONS, ...options };
  const grid = speedGrid(speed.times, speed.values, o.step, o.maxGap);
  const n = grid.values.length;
  if (n === 0) return [];
  const gridTimes = new Float64Array(n);
  for (let k = 0; k < n; k++) gridTimes[k] = grid.t0 + k * o.step;
  const rpmOnGrid = rpm ? alignNearest(gridTimes, rpm.times, rpm.values, o.maxGap) : null;

  const labels = new Array(n).fill(null);
  for (let k = 0; k < n; k++) {
    const v = grid.values[k];
    if (!Number.isFinite(v)) continue;
    const prev = k > 0 ? grid.values[k - 1] : NaN;
    const next = k + 1 < n ? grid.values[k + 1] : NaN;
    const a = centralAcceleration(prev, v, next, o.step);
    if (!Number.isFinite(a)) continue;
    if (v < o.stopSpeed) {
      const engineOn = rpmOnGrid && Number.isFinite(rpmOnGrid[k]) && rpmOnGrid[k] >= o.engineOnRpm;
      labels[k] = engineOn ? 'idle' : 'stop';
    } else if (a > o.accelThreshold) labels[k] = 'acceleration';
    else if (a < -o.accelThreshold) labels[k] = 'deceleration';
    else labels[k] = 'cruise';
  }

  let runs = [];
  for (let k = 0; k < n; k++) {
    if (labels[k] === null) continue;
    const last = runs[runs.length - 1];
    if (last && last.type === labels[k] && last.endIndex === k - 1) { last.endIndex = k; continue; }
    runs.push({ type: labels[k], startIndex: k, endIndex: k });
  }
  // Absorb runs shorter than minDuration into the previous (or next) adjacent run.
  const minPoints = Math.max(1, Math.round(o.minDuration / o.step));
  let changed = true;
  while (changed) {
    changed = false;
    for (let r = 0; r < runs.length; r++) {
      const run = runs[r];
      if (run.endIndex - run.startIndex + 1 >= minPoints) continue;
      const prev = runs[r - 1], next = runs[r + 1];
      const prevAdjacent = prev && prev.endIndex === run.startIndex - 1;
      const nextAdjacent = next && next.startIndex === run.endIndex + 1;
      if (prevAdjacent) { prev.endIndex = run.endIndex; runs.splice(r, 1); }
      else if (nextAdjacent) { next.startIndex = run.startIndex; runs.splice(r, 1); }
      else continue;
      changed = true;
      break;
    }
    const merged = [];
    for (const run of runs) {
      const last = merged[merged.length - 1];
      if (last && last.type === run.type && last.endIndex + 1 === run.startIndex) last.endIndex = run.endIndex;
      else merged.push(run);
    }
    if (merged.length !== runs.length) { runs = merged; changed = true; } else runs = merged;
  }
  return runs.map((run) => ({
    type: run.type,
    t0: grid.t0 + run.startIndex * o.step,
    t1: grid.t0 + (run.endIndex + 1) * o.step,
  }));
}

/** Acceleration in m/s^2 from three consecutive km/h grid values (one-sided at the ends). */
function centralAcceleration(prev, now, next, step) {
  const kmhToMs = 1 / 3.6;
  if (Number.isFinite(prev) && Number.isFinite(next)) return ((next - prev) / (2 * step)) * kmhToMs;
  if (Number.isFinite(next)) return ((next - now) / step) * kmhToMs;
  if (Number.isFinite(prev)) return ((now - prev) / step) * kmhToMs;
  return NaN;
}

/** Segment type of a time, or null when no segment covers it. */
export function segmentTypeAt(segments, t) {
  let lo = 0, hi = segments.length - 1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (t < segments[mid].t0) hi = mid - 1;
    else if (t >= segments[mid].t1) lo = mid + 1;
    else return segments[mid].type;
  }
  return null;
}

/** Total seconds per segment type. */
export function segmentTotals(segments) {
  const totals = Object.fromEntries(SEGMENT_TYPES.map((t) => [t, 0]));
  for (const s of segments) totals[s.type] += s.t1 - s.t0;
  return totals;
}

export const DEFAULT_EVENT_OPTIONS = {
  hardAcceleration: 2.5,    // m/s^2
  hardBraking: -3.0,        // m/s^2
  highCoolant: 105,         // degrees C
  trimLimit: 20,            // percent, absolute
  trimMinDuration: 2,       // seconds
  rpmPeakMinSeparation: 10, // seconds
  rpmPeakMax: 5,
};

/**
 * Detects notable moments. Each event: { type, t, tEnd, value, channel, severity }.
 * Types: hardAcceleration, hardBraking, highCoolant, fuelTrimExcursion, rpmPeak.
 * `channels` maps names to { times, values } and may omit any channel.
 */
export function detectEvents({ speed, rpm, coolant, stft, ltft }, options = {}) {
  const o = { ...DEFAULT_EVENT_OPTIONS, ...options };
  const events = [];
  if (speed && speed.times.length > 1) {
    const grid = speedGrid(speed.times, speed.values, 1, 3);
    let active = null;
    const close = () => { if (active) { events.push(active); active = null; } };
    for (let k = 0; k < grid.values.length; k++) {
      const a = centralAcceleration(k > 0 ? grid.values[k - 1] : NaN, grid.values[k], k + 1 < grid.values.length ? grid.values[k + 1] : NaN, 1);
      const t = grid.t0 + k;
      const type = a >= o.hardAcceleration ? 'hardAcceleration' : a <= o.hardBraking ? 'hardBraking' : null;
      if (type && active && active.type === type && t - active.tEnd <= 1.5) {
        active.tEnd = t;
        if (Math.abs(a) > Math.abs(active.value)) { active.value = a; active.t = t; }
      } else {
        close();
        if (type) active = { type, t, tEnd: t, value: a, channel: 'speed', severity: 'warn' };
      }
    }
    close();
  }
  if (coolant) events.push(...thresholdRuns(coolant, (v) => v > o.highCoolant, 'highCoolant', 0, true));
  for (const trim of [stft, ltft]) {
    if (!trim) continue;
    events.push(...thresholdRuns(trim, (v) => Math.abs(v) > o.trimLimit, 'fuelTrimExcursion', o.trimMinDuration, true));
  }
  if (rpm && rpm.values.length > 20) {
    const sorted = sortedFinite(rpm.values);
    const threshold = percentileSorted(sorted, 0.995);
    const candidates = [];
    for (let i = 1; i + 1 < rpm.values.length; i++) {
      const v = rpm.values[i];
      if (v >= threshold && v >= rpm.values[i - 1] && v >= rpm.values[i + 1]) candidates.push(i);
    }
    candidates.sort((a, b) => rpm.values[b] - rpm.values[a]);
    const chosen = [];
    for (const i of candidates) {
      if (chosen.length >= o.rpmPeakMax) break;
      if (chosen.every((j) => Math.abs(rpm.times[j] - rpm.times[i]) >= o.rpmPeakMinSeparation)) chosen.push(i);
    }
    for (const i of chosen) events.push({ type: 'rpmPeak', t: rpm.times[i], tEnd: rpm.times[i], value: rpm.values[i], channel: 'rpm', severity: 'info' });
  }
  events.sort((a, b) => a.t - b.t);
  return events;
}

/** Contiguous runs where predicate holds; each run reports its peak (largest |value|). */
function thresholdRuns(channel, predicate, type, minDuration, warn) {
  const out = [];
  let run = null;
  const finish = () => {
    if (run && run.tEnd - run.start >= minDuration) {
      out.push({ type, t: run.t, tEnd: run.tEnd, value: run.value, channel: run.channel, severity: warn ? 'warn' : 'info' });
    }
    run = null;
  };
  for (let i = 0; i < channel.times.length; i++) {
    const v = channel.values[i];
    if (run && channel.times[i] - run.tEnd > 5) finish();
    if (Number.isFinite(v) && predicate(v)) {
      if (!run) run = { start: channel.times[i], t: channel.times[i], tEnd: channel.times[i], value: v, channel: channel.id || type };
      run.tEnd = channel.times[i];
      if (Math.abs(v) > Math.abs(run.value)) { run.value = v; run.t = channel.times[i]; }
    } else finish();
  }
  finish();
  return out;
}
