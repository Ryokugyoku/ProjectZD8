// CSV serialisation of channels. No DOM access.
import { lowerBound, upperBound } from './analysis-stats.js';

function csvCell(text) {
  const s = String(text);
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function formatNumber(v) {
  return Number.isFinite(v) ? String(Math.round(v * 1e6) / 1e6) : '';
}

/**
 * Wide CSV: one row per distinct timestamp in [t0, t1], one column per channel.
 * A channel without a sample at that timestamp leaves its cell empty (never 0, never interpolated).
 * `channels` are { name, unit, times, values }.
 */
export function buildCsv(channels, t0 = -Infinity, t1 = Infinity) {
  const header = ['time_s', ...channels.map((c) => (c.unit ? `${c.name} [${c.unit}]` : c.name))].map(csvCell).join(',');
  const ranges = channels.map((c) => ({ lo: lowerBound(c.times, t0), hi: upperBound(c.times, t1) }));
  const cursors = ranges.map((r) => r.lo);
  const lines = [header];
  for (;;) {
    let next = Infinity;
    for (let k = 0; k < channels.length; k++) {
      if (cursors[k] < ranges[k].hi) next = Math.min(next, channels[k].times[cursors[k]]);
    }
    if (next === Infinity) break;
    const cells = [formatNumber(next)];
    for (let k = 0; k < channels.length; k++) {
      if (cursors[k] < ranges[k].hi && channels[k].times[cursors[k]] === next) {
        cells.push(formatNumber(channels[k].values[cursors[k]]));
        cursors[k]++;
      } else cells.push('');
    }
    lines.push(cells.join(','));
  }
  return lines.join('\n') + '\n';
}

/** Base64 of a UTF-8 string (for the native export bridge). */
export function utf8ToBase64(text) {
  const bytes = new TextEncoder().encode(text);
  let binary = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
  return btoa(binary);
}
