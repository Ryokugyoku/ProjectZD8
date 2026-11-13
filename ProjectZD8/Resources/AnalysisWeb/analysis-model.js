// Browser-side session model built from the native dataset JSON. Pure: no DOM access.
import { accelerationFromSpeed, clusterGears, deriveFromExpression, fuelTrimSum, rpmSpeedRatio } from './analysis-derive.js';
import { detectEvents, segmentDrive } from './analysis-segment.js';

export const CH = {
  LOAD: '01-04', COOLANT: '01-05', STFT: '01-06', LTFT: '01-07', MAP: '01-0B', RPM: '01-0C', SPEED: '01-0D',
  IAT: '01-0F', MAF: '01-10', THROTTLE: '01-11',
};

export const SCHEMA_VERSION = 1;

function toTyped(array) {
  return Float64Array.from(array);
}

function rangeOf(values) {
  let min = Infinity, max = -Infinity;
  for (let i = 0; i < values.length; i++) {
    const v = values[i];
    if (v < min) min = v;
    if (v > max) max = v;
  }
  return min <= max ? { min, max } : { min: NaN, max: NaN };
}

/** Converts the native dataset into a session with typed arrays, maintenance offsets, segments and events. */
export function buildSession(dataset, index = 0) {
  if (dataset.schemaVersion !== SCHEMA_VERSION) {
    const error = new Error('schemaVersion');
    error.code = 'schemaVersion';
    throw error;
  }
  const startedAtMs = Date.parse(dataset.session.startedAt);
  const channels = new Map();
  const order = [];
  for (const c of dataset.channels) {
    const values = toTyped(c.values);
    const range = rangeOf(values);
    channels.set(c.id, {
      id: c.id, name: c.name, unit: c.unit, isFast: c.isFast, isDecodable: c.isDecodable,
      declaredMinimum: c.declaredMinimum ?? null, declaredMaximum: c.declaredMaximum ?? null,
      definitionRevision: c.definitionRevision, quality: c.quality,
      times: toTyped(c.times), values, min: range.min, max: range.max, derived: false,
    });
    order.push(c.id);
  }
  const session = {
    id: dataset.session.id, index, startedAtMs, durationSeconds: dataset.session.durationSeconds,
    info: dataset.session, vehicle: dataset.vehicle, gaps: dataset.gaps,
    maintenance: dataset.maintenance.map((m) => ({
      id: m.id, dateMs: Date.parse(m.date), t: (Date.parse(m.date) - startedAtMs) / 1000,
      title: m.title, kind: m.kind, odometerKilometers: m.odometerKilometers ?? null,
    })),
    channels, order, segments: [], events: [], derivedDefs: [], gearInfo: null,
  };
  analyzeSession(session);
  return session;
}

/** Returns the channel with data, or null. */
export function channelOf(session, id) {
  const c = session.channels.get(id);
  return c && c.times.length > 0 ? c : null;
}

/** Channels that have at least one decoded value, in dataset order. */
export function usableChannels(session) {
  return session.order.map((id) => session.channels.get(id)).filter((c) => c.times.length > 0);
}

/** Recomputes segments and events from the speed / rpm / coolant / trim channels. */
export function analyzeSession(session) {
  const speed = channelOf(session, CH.SPEED);
  const rpm = channelOf(session, CH.RPM);
  session.segments = speed ? segmentDrive(speed, rpm) : [];
  session.events = detectEvents({
    speed, rpm, coolant: channelOf(session, CH.COOLANT),
    stft: withId(channelOf(session, CH.STFT)), ltft: withId(channelOf(session, CH.LTFT)),
  });
}

function withId(channel) {
  return channel ? { id: channel.id, times: channel.times, values: channel.values } : null;
}

export const BUILTIN_DERIVED = [
  { key: 'accel', id: 'd-accel', unit: 'm/s²', requires: [CH.SPEED] },
  { key: 'ratio', id: 'd-ratio', unit: 'rpm/(km/h)', requires: [CH.RPM, CH.SPEED] },
  { key: 'gear', id: 'd-gear', unit: '', requires: [CH.RPM, CH.SPEED] },
  { key: 'trimsum', id: 'd-trimsum', unit: '%', requires: [CH.STFT, CH.LTFT] },
];

/** True when all channels a built-in needs have data. */
export function builtinAvailable(session, builtin) {
  return builtin.requires.every((id) => channelOf(session, id));
}

function makeDerived(session, id, name, unit, result) {
  const range = rangeOf(result.values);
  return { id, name, unit, isFast: false, isDecodable: true, declaredMinimum: null, declaredMaximum: null, definitionRevision: 0,
    quality: null, times: result.times, values: result.values, min: range.min, max: range.max, derived: true };
}

/**
 * Re-creates all derived channels from session.derivedDefs. Definitions:
 * { kind: 'builtin', key } or { kind: 'expression', id, name, unit, source, tolerance }.
 * Returns errors by definition id so the editor can show them.
 */
export function rebuildDerived(session, names) {
  for (const id of [...session.channels.keys()]) if (session.channels.get(id).derived) { session.channels.delete(id); }
  session.order = session.order.filter((id) => session.channels.has(id));
  session.gearInfo = null;
  const errors = {};
  for (const def of session.derivedDefs) {
    try {
      if (def.kind === 'builtin') addBuiltin(session, def.key, names);
      else {
        const usable = usableChannels(session).map((c) => ({ id: c.id, name: c.name, times: c.times, values: c.values }));
        const result = deriveFromExpression(def.source, usable, def.tolerance ?? 1);
        if (result.times.length === 0) { const e = new Error('emptyResult'); e.code = 'emptyResult'; throw e; }
        const channel = makeDerived(session, def.id, def.name, def.unit, result);
        session.channels.set(channel.id, channel); session.order.push(channel.id);
      }
    } catch (error) {
      errors[def.kind === 'builtin' ? def.key : def.id] = { code: error.code || 'error', position: error.position, detail: error.detail };
    }
  }
  return errors;
}

function addBuiltin(session, key, names) {
  const speed = channelOf(session, CH.SPEED), rpm = channelOf(session, CH.RPM);
  const add = (id, name, unit, result) => { const c = makeDerived(session, id, name, unit, result); session.channels.set(id, c); session.order.push(id); };
  if (key === 'accel') {
    if (!speed) throw codeError('missingChannel');
    add('d-accel', names('derived.accel.name'), 'm/s²', accelerationFromSpeed(speed.times, speed.values));
  } else if (key === 'ratio' || key === 'gear') {
    if (!speed || !rpm) throw codeError('missingChannel');
    const ratio = rpmSpeedRatio(rpm, speed);
    if (key === 'ratio') { add('d-ratio', names('derived.ratio.name'), 'rpm/(km/h)', ratio); return; }
    const clusters = clusterGears(ratio.values);
    session.gearInfo = clusters;
    const t = [], v = [];
    for (let i = 0; i < ratio.times.length; i++) if (clusters.assignment[i] > 0) { t.push(ratio.times[i]); v.push(clusters.assignment[i]); }
    add('d-gear', names('derived.gear.name'), '', { times: Float64Array.from(t), values: Float64Array.from(v) });
  } else if (key === 'trimsum') {
    const stft = channelOf(session, CH.STFT), ltft = channelOf(session, CH.LTFT);
    if (!stft || !ltft) throw codeError('missingChannel');
    add('d-trimsum', names('derived.trimsum.name'), '%', fuelTrimSum(stft, ltft));
  }
}

function codeError(code) { const e = new Error(code); e.code = code; return e; }

/** Time window of the whole session in seconds. */
export function sessionExtent(session) {
  let max = session.durationSeconds || 0;
  for (const c of session.channels.values()) if (c.times.length) max = Math.max(max, c.times[c.times.length - 1]);
  return [0, Math.max(max, 1)];
}

/** Samples of a channel inside [t0, t1] as a { times, values } view (copies). */
export function sliceChannel(channel, t0, t1) {
  let lo = 0, hi = channel.times.length;
  while (lo < hi) { const m = (lo + hi) >>> 1; if (channel.times[m] < t0) lo = m + 1; else hi = m; }
  const start = lo;
  hi = channel.times.length;
  while (lo < hi) { const m = (lo + hi) >>> 1; if (channel.times[m] <= t1) lo = m + 1; else hi = m; }
  return { times: channel.times.subarray(start, lo), values: channel.values.subarray(start, lo) };
}

/** Values of a channel restricted to the listed segment types (empty list = all). */
export function valuesInSegments(channel, segments, types) {
  if (!types || types.length === 0) return channel.values;
  const out = [];
  for (const s of segments) {
    if (!types.includes(s.type)) continue;
    const part = sliceChannel(channel, s.t0, s.t1);
    for (let i = 0; i < part.values.length; i++) out.push(part.values[i]);
  }
  return Float64Array.from(out);
}
