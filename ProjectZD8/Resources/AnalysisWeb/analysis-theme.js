// Theme tokens for canvas drawing, read from the CSS custom properties so that
// prefers-color-scheme drives both the DOM and the charts.

let cache = null;

function cssVar(style, name, fallback) {
  const v = style.getPropertyValue(name).trim();
  return v || fallback;
}

/** Current palette. Cheap: cached until the colour scheme changes. */
export function theme() {
  if (cache) return cache;
  const style = getComputedStyle(document.documentElement);
  cache = {
    bg: cssVar(style, '--bg', '#0b0f14'),
    panel: cssVar(style, '--panel', '#121922'),
    fg: cssVar(style, '--fg', '#e6edf3'),
    muted: cssVar(style, '--muted', '#8b9bab'),
    grid: cssVar(style, '--grid', 'rgba(255,255,255,0.08)'),
    accent: cssVar(style, '--accent', '#05C7E6'),
    warn: cssVar(style, '--warn', '#ff9f43'),
    band: cssVar(style, '--band', 'rgba(5,199,230,0.16)'),
    gap: cssVar(style, '--gap', 'rgba(255,159,67,0.10)'),
    brush: cssVar(style, '--brush', 'rgba(5,199,230,0.18)'),
    series: [
      cssVar(style, '--s1', '#05C7E6'), cssVar(style, '--s2', '#9d8cff'), cssVar(style, '--s3', '#3ccf91'),
      cssVar(style, '--s4', '#ff6fa8'), cssVar(style, '--s5', '#4a90ff'), cssVar(style, '--s6', '#e0c341'),
    ],
    segment: {
      stop: cssVar(style, '--seg-stop', '#6b7a89'),
      idle: cssVar(style, '--seg-idle', '#4a90ff'),
      acceleration: cssVar(style, '--seg-accel', '#05C7E6'),
      cruise: cssVar(style, '--seg-cruise', '#3ccf91'),
      deceleration: cssVar(style, '--seg-decel', '#9d8cff'),
    },
    font: cssVar(style, '--font', '-apple-system, system-ui, "Segoe UI", sans-serif'),
    mono: cssVar(style, '--mono', 'ui-monospace, Menlo, monospace'),
    dark: window.matchMedia('(prefers-color-scheme: dark)').matches,
  };
  return cache;
}

/** Colour for a series index (cycles through the palette). */
export function seriesColor(index) {
  const s = theme().series;
  return s[index % s.length];
}

/** Sequential map colour (0..1): dark/light base to accent to orange peak. */
export function heatColor(f) {
  const t = theme();
  const x = Math.min(Math.max(f, 0), 1);
  const low = t.dark ? [18, 38, 52] : [226, 244, 250];
  const mid = t.dark ? [5, 199, 230] : [0, 125, 166];
  const high = [255, 159, 67];
  const a = x < 0.7 ? low : mid;
  const b = x < 0.7 ? mid : high;
  const w = x < 0.7 ? x / 0.7 : (x - 0.7) / 0.3;
  const c = a.map((v, i) => Math.round(v + (b[i] - v) * w));
  return `rgb(${c[0]},${c[1]},${c[2]})`;
}

/** Called when the OS colour scheme changes; listeners redraw. */
export function watchTheme(callback) {
  const query = window.matchMedia('(prefers-color-scheme: dark)');
  const handler = () => { cache = null; callback(); };
  query.addEventListener('change', handler);
  return () => query.removeEventListener('change', handler);
}

/** Forces the next theme() call to re-read the CSS variables. */
export function invalidateTheme() {
  cache = null;
}

/** "#rrggbb" or "rgb(...)" colour with an alpha channel, for translucent fills. */
export function withAlpha(color, alpha) {
  if (color.startsWith('#') && color.length === 7) {
    const r = parseInt(color.slice(1, 3), 16), g = parseInt(color.slice(3, 5), 16), b = parseInt(color.slice(5, 7), 16);
    return `rgba(${r},${g},${b},${alpha})`;
  }
  return color;
}
