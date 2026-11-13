// Tiny DOM and formatting helpers shared by the views.

/** Creates an element. Attributes: class, text, style (object), on* handlers, dataset, anything else as attribute. */
export function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs || {})) {
    if (value === undefined || value === null || value === false) continue;
    if (key === 'class') el.className = value;
    else if (key === 'text') el.textContent = value;
    else if (key === 'style' && typeof value === 'object') Object.assign(el.style, value);
    else if (key === 'dataset') Object.assign(el.dataset, value);
    else if (key.startsWith('on') && typeof value === 'function') el.addEventListener(key.slice(2).toLowerCase(), value);
    else if (value === true) el.setAttribute(key, '');
    else el.setAttribute(key, value);
  }
  for (const child of children.flat()) {
    if (child === null || child === undefined || child === false) continue;
    el.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return el;
}

/** Removes all children. */
export function clear(el) {
  while (el.firstChild) el.removeChild(el.firstChild);
  return el;
}

/** Number with sensible digits for its magnitude; NaN shows an em dash. */
export function fmt(v, digits) {
  if (!Number.isFinite(v)) return '—';
  if (digits !== undefined) return v.toFixed(digits);
  const a = Math.abs(v);
  if (a === 0) return '0';
  if (a >= 1000) return v.toFixed(0);
  if (a >= 100) return v.toFixed(1);
  if (a >= 10) return v.toFixed(2);
  if (a >= 1) return v.toFixed(2);
  if (a >= 0.01) return v.toFixed(3);
  return v.toExponential(2);
}

/** Tick label using the tick step to pick decimals. */
export function fmtTick(v, step) {
  if (!Number.isFinite(v)) return '';
  if (step >= 1 || step === undefined) return Math.abs(v) >= 10000 ? v.toExponential(1) : String(Math.round(v * 100) / 100);
  const decimals = Math.min(6, Math.max(0, Math.ceil(-Math.log10(step)) + 0));
  return v.toFixed(decimals);
}

/** m:ss or h:mm:ss for a time in seconds, with tenths for very short spans. */
export function formatClock(seconds, precise = false) {
  if (!Number.isFinite(seconds)) return '—';
  const sign = seconds < 0 ? '-' : '';
  const s = Math.abs(seconds);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  const secText = precise ? sec.toFixed(1).padStart(4, '0') : String(Math.floor(sec)).padStart(2, '0');
  return h > 0 ? `${sign}${h}:${String(m).padStart(2, '0')}:${secText}` : `${sign}${m}:${secText}`;
}

/** Human duration like "12 min 05 s". Language-neutral abbreviations. */
export function formatDuration(seconds) {
  if (!Number.isFinite(seconds)) return '—';
  const s = Math.round(seconds);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
  return `${m}:${String(s % 60).padStart(2, '0')}`;
}

/** Locale date/time. */
export function formatDateTime(ms, lang) {
  return new Date(ms).toLocaleString(lang, { dateStyle: 'medium', timeStyle: 'short' });
}

/** Locale date only. */
export function formatDate(ms, lang) {
  return new Date(ms).toLocaleDateString(lang, { dateStyle: 'medium' });
}

/** Coalesces calls into one per animation frame. */
export function frameThrottle(fn) {
  let pending = false;
  return (...args) => {
    if (pending) return;
    pending = true;
    requestAnimationFrame(() => { pending = false; fn(...args); });
  };
}

/** Standard trailing debounce. */
export function debounce(fn, wait) {
  let timer = null;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), wait);
  };
}

/** Runs the callback with the element's content size whenever it changes. Returns a disconnect function. */
export function observeSize(el, callback) {
  const observer = new ResizeObserver((entries) => {
    const rect = entries[0].contentRect;
    callback(Math.floor(rect.width), Math.floor(rect.height));
  });
  observer.observe(el);
  return () => observer.disconnect();
}

/** Sizes a canvas for the device pixel ratio and returns its 2D context in CSS pixel units. */
export function fitCanvas(canvas, width, height) {
  const dpr = window.devicePixelRatio || 1;
  const w = Math.max(1, Math.floor(width));
  const hh = Math.max(1, Math.floor(height));
  if (canvas.width !== Math.floor(w * dpr) || canvas.height !== Math.floor(hh * dpr)) {
    canvas.width = Math.floor(w * dpr);
    canvas.height = Math.floor(hh * dpr);
    canvas.style.width = `${w}px`;
    canvas.style.height = `${hh}px`;
  }
  const ctx = canvas.getContext('2d');
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  return ctx;
}

/** Fills a rounded rectangle path. */
export function roundRectPath(ctx, x, y, w, hh, r) {
  const rr = Math.min(r, w / 2, hh / 2);
  ctx.beginPath();
  ctx.moveTo(x + rr, y);
  ctx.arcTo(x + w, y, x + w, y + hh, rr);
  ctx.arcTo(x + w, y + hh, x, y + hh, rr);
  ctx.arcTo(x, y + hh, x, y, rr);
  ctx.arcTo(x, y, x + w, y, rr);
  ctx.closePath();
}
