// Stacked time-series chart engine on canvas: HiDPI, pan / zoom / pinch, synchronized crosshair,
// brush selection, min/max decimation, gap-aware lines, markers and shaded bands.
import { h, fitCanvas, fmt, fmtTick, formatClock, frameThrottle, observeSize, roundRectPath } from './analysis-dom.js';
import { theme, watchTheme } from './analysis-theme.js';
import { findGaps, hasGapBetween, minMaxDecimate, visibleRange } from './analysis-decimate.js';
import { medianInterval, nearestIndex, niceTicks, niceTimeTicks } from './analysis-stats.js';

const MARGIN = { left: 54, right: 12, top: 6, bottom: 4 };
const AXIS_HEIGHT = 20;

/**
 * Series: { label, unit, times, values, color, normalize?, band?: { lo, hi }, points?, gapSeconds? }.
 * Panel spec: { id, title, unit, series, markers?, bands?, yRange?, height? }.
 * Marker: { x, label, color }. Band (background): { x0, x1, color }.
 */
export class TimeChartGroup {
  /** Live groups (used by tests and diagnostics). */
  static instances = new Set();

  constructor(container, options = {}) {
    TimeChartGroup.instances.add(this);
    this.container = container;
    this.options = { xFormat: formatClock, minSpan: 0.5, ticks: niceTimeTicks, ...options };
    this.panels = [];
    this.extent = [0, 1];
    this.domain = [0, 1];
    this.cursor = null;
    this.brush = null;
    this.brushMode = false;
    this.listeners = { brush: [], cursor: [], domain: [] };
    this.pointers = new Map();
    this.drag = null;
    this.requestDraw = frameThrottle(() => this.drawAll());
    this.root = h('div', { class: 'tc-group' });
    container.append(this.root);
    this.unwatchTheme = watchTheme(() => this.requestDraw());
  }

  on(event, callback) { this.listeners[event].push(callback); return this; }
  emit(event, payload) { for (const cb of this.listeners[event]) cb(payload); }

  /** Replaces all panels. Keeps the current zoom when `keepDomain` is true. */
  setPanels(specs, extent, keepDomain = false) {
    for (const p of this.panels) p.destroy();
    this.panels = [];
    this.root.textContent = '';
    if (extent) this.extent = extent;
    if (!keepDomain || !(this.domain[1] > this.domain[0])) this.domain = [...this.extent];
    specs.forEach((spec, i) => {
      const panel = new TimePanel(this, spec, i === specs.length - 1);
      panel.isFirstWithLabels = i === 0;
      this.panels.push(panel);
      this.root.append(panel.el);
    });
    this.requestDraw();
  }

  setDomain(x0, x1) {
    const [e0, e1] = this.extent;
    const span = Math.max(x1 - x0, this.options.minSpan);
    const maxSpan = (e1 - e0) * 1.02 + this.options.minSpan;
    const s = Math.min(span, maxSpan);
    let a = x0, b = x0 + s;
    const pad = (e1 - e0) * 0.01;
    if (a < e0 - pad) { a = e0 - pad; b = a + s; }
    if (b > e1 + pad) { b = e1 + pad; a = b - s; }
    this.domain = [a, b];
    this.emit('domain', this.domain);
    this.requestDraw();
  }

  resetZoom() { this.setDomain(this.extent[0], this.extent[1]); }

  zoomBy(factor, centerX) {
    const [a, b] = this.domain;
    const c = centerX ?? (a + b) / 2;
    const f = Math.min(Math.max(factor, 0.05), 20);
    this.setDomain(c - (c - a) * f, c + (b - c) * f);
  }

  zoomToBrush() { if (this.brush) this.setDomain(this.brush[0], this.brush[1]); }

  setBrush(range) {
    this.brush = range ? [Math.min(range[0], range[1]), Math.max(range[0], range[1])] : null;
    this.emit('brush', this.brush);
    this.requestDraw();
  }

  setBrushMode(on) { this.brushMode = on; for (const p of this.panels) p.canvas.style.cursor = on ? 'crosshair' : 'grab'; }

  setCursor(x, source) {
    this.cursor = x;
    this.emit('cursor', x);
    for (const p of this.panels) p.updateReadout();
    this.requestDraw();
  }

  drawAll() { for (const p of this.panels) p.draw(); }

  /** Composite PNG canvas of all panels stacked, with a title line. */
  toCanvas(title = '') {
    const t = theme();
    const width = Math.max(...this.panels.map((p) => p.width), 100);
    const titleH = title ? 28 : 0;
    const total = this.panels.reduce((s, p) => s + p.height, 0) + titleH;
    const out = document.createElement('canvas');
    out.width = width * 2; out.height = total * 2;
    const ctx = out.getContext('2d');
    ctx.scale(2, 2);
    ctx.fillStyle = t.bg; ctx.fillRect(0, 0, width, total);
    if (title) { ctx.fillStyle = t.fg; ctx.font = `600 14px ${t.font}`; ctx.fillText(title, 10, 19); }
    let y = titleH;
    for (const p of this.panels) {
      p.draw();
      ctx.drawImage(p.canvas, 0, y, p.width, p.height);
      ctx.fillStyle = t.fg; ctx.font = `600 11px ${t.font}`;
      ctx.fillText(p.spec.title || '', MARGIN.left + 4, y + 14);
      y += p.height;
    }
    return out;
  }

  destroy() {
    TimeChartGroup.instances.delete(this);
    for (const p of this.panels) p.destroy();
    this.unwatchTheme();
    this.root.remove();
  }
}

class TimePanel {
  constructor(group, spec, isLast) {
    this.group = group;
    this.spec = spec;
    this.isLast = isLast;
    this.width = 300;
    this.height = spec.height || 150;
    this.canvas = h('canvas', { class: 'tc-canvas' });
    this.canvas.style.touchAction = 'none';
    this.canvas.style.cursor = group.brushMode ? 'crosshair' : 'grab';
    this.legend = h('div', { class: 'tc-legend' });
    this.el = h('div', { class: 'tc-panel', style: { height: `${this.height}px` } }, this.canvas, this.legend);
    this.spec.series.forEach((s, i) => {
      s.color = s.color || theme().series[i % theme().series.length];
      s.gapSeconds = s.gapSeconds ?? Math.max(2, (medianInterval(s.times) || 1) * 4);
      s.gapIdx = findGaps(s.times, s.gapSeconds);
    });
    this.legendItems = spec.series.map((s) => {
      const value = h('span', { class: 'tc-value' });
      const item = h('span', { class: 'tc-legend-item' }, h('i', { style: { background: s.color } }), h('span', { class: 'tc-name', text: s.label }), value);
      this.legend.append(item);
      return value;
    });
    this.stopObserve = observeSize(this.el, (w) => { this.width = Math.max(w, 120); this.group.requestDraw(); });
    this.bind();
  }

  destroy() { this.stopObserve(); }

  get plot() {
    return {
      x: MARGIN.left, y: MARGIN.top,
      w: Math.max(10, this.width - MARGIN.left - MARGIN.right),
      h: Math.max(10, this.height - MARGIN.top - (this.isLast ? AXIS_HEIGHT : MARGIN.bottom)),
    };
  }

  xToTime(px) {
    const [a, b] = this.group.domain;
    const p = this.plot;
    return a + ((px - p.x) / p.w) * (b - a);
  }

  timeToX(t) {
    const [a, b] = this.group.domain;
    const p = this.plot;
    return p.x + ((t - a) / (b - a)) * p.w;
  }

  localX(event) {
    return event.clientX - this.canvas.getBoundingClientRect().left;
  }

  bind() {
    const g = this.group;
    const c = this.canvas;
    c.addEventListener('pointerdown', (e) => {
      c.setPointerCapture(e.pointerId);
      this.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
      if (this.pointers.size === 2) { g.drag = { kind: 'pinch', ...this.pinchState() }; return; }
      const x = this.localX(e);
      if (g.brushMode || e.shiftKey) g.drag = { kind: 'brush', start: this.xToTime(x) };
      else g.drag = { kind: 'pan', startX: x, domain: [...g.domain], moved: false };
      if (g.drag.kind === 'brush') g.setBrush([g.drag.start, g.drag.start]);
      c.style.cursor = g.drag.kind === 'pan' ? 'grabbing' : 'crosshair';
    });
    c.addEventListener('pointermove', (e) => {
      if (this.pointers.has(e.pointerId)) this.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
      const x = this.localX(e);
      const d = g.drag;
      if (d && d.kind === 'pinch' && this.pointers.size >= 2) {
        const now = this.pinchState();
        const factor = d.distance / Math.max(now.distance, 1);
        const centerTime = this.xToTime(now.centerX - c.getBoundingClientRect().left);
        g.zoomBy(factor, centerTime);
        d.distance = now.distance;
        return;
      }
      if (d && d.kind === 'pan') {
        const span = d.domain[1] - d.domain[0];
        const dt = -((x - d.startX) / this.plot.w) * span;
        if (Math.abs(x - d.startX) > 3) d.moved = true;
        g.setDomain(d.domain[0] + dt, d.domain[0] + dt + span);
      } else if (d && d.kind === 'brush') {
        g.setBrush([d.start, this.xToTime(x)]);
      }
      g.setCursor(this.xToTime(x), this);
    });
    const end = (e) => {
      this.pointers.delete(e.pointerId);
      const d = g.drag;
      if (d && d.kind === 'brush' && g.brush && g.brush[1] - g.brush[0] < (g.domain[1] - g.domain[0]) * 0.003) g.setBrush(null);
      if (this.pointers.size === 0) { g.drag = null; c.style.cursor = g.brushMode ? 'crosshair' : 'grab'; }
      else if (this.pointers.size === 1 && d && d.kind === 'pinch') {
        const only = [...this.pointers.values()][0];
        g.drag = { kind: 'pan', startX: only.x - c.getBoundingClientRect().left, domain: [...g.domain], moved: true };
      }
    };
    c.addEventListener('pointerup', end);
    c.addEventListener('pointercancel', end);
    c.addEventListener('pointerleave', () => { if (!g.drag) { g.cursor = null; g.emit('cursor', null); for (const p of g.panels) p.updateReadout(); g.requestDraw(); } });
    c.addEventListener('wheel', (e) => {
      e.preventDefault();
      const x = this.localX(e);
      if (!e.ctrlKey && Math.abs(e.deltaX) > Math.abs(e.deltaY)) {
        const span = g.domain[1] - g.domain[0];
        const dt = (e.deltaX / this.plot.w) * span;
        g.setDomain(g.domain[0] + dt, g.domain[1] + dt);
        return;
      }
      const factor = Math.exp(e.deltaY * (e.ctrlKey ? 0.01 : 0.0015));
      g.zoomBy(factor, this.xToTime(x));
    }, { passive: false });
    c.addEventListener('dblclick', () => g.resetZoom());
  }

  get pointers() { return this.group.pointers; }

  pinchState() {
    const pts = [...this.group.pointers.values()];
    const a = pts[0], b = pts[1];
    return { distance: Math.hypot(a.x - b.x, a.y - b.y), centerX: (a.x + b.x) / 2 };
  }

  yDomain() {
    const spec = this.spec;
    if (spec.yRange) return spec.yRange;
    const [x0, x1] = this.group.domain;
    let min = Infinity, max = -Infinity;
    for (const s of spec.series) {
      if (s.normalize) continue;
      const r = visibleRange(s.times, s.values, x0, x1);
      if (r) { min = Math.min(min, r.min); max = Math.max(max, r.max); }
      if (s.band) {
        const lo = visibleRange(s.times, s.band.lo, x0, x1);
        const hi = visibleRange(s.times, s.band.hi, x0, x1);
        if (lo) min = Math.min(min, lo.min);
        if (hi) max = Math.max(max, hi.max);
      }
    }
    if (spec.series.every((s) => s.normalize)) return [0, 1];
    if (!(min <= max)) return [0, 1];
    if (min === max) { min -= 1; max += 1; }
    const pad = (max - min) * 0.06;
    return [min - pad, max + pad];
  }

  updateReadout() {
    const cursor = this.group.cursor;
    this.spec.series.forEach((s, i) => {
      const el = this.legendItems[i];
      if (cursor === null || cursor === undefined) { el.textContent = ''; return; }
      const k = nearestIndex(s.times, cursor);
      if (k < 0 || Math.abs(s.times[k] - cursor) > s.gapSeconds) { el.textContent = '—'; return; }
      el.textContent = `${fmt(s.values[k])}${s.unit ? ' ' + s.unit : ''}`;
    });
  }

  draw() {
    const g = this.group;
    const t = theme();
    const ctx = fitCanvas(this.canvas, this.width, this.height);
    const p = this.plot;
    const [x0, x1] = g.domain;
    const [y0, y1] = this.yDomain();
    const yPx = (v) => p.y + p.h - ((v - y0) / (y1 - y0)) * p.h;
    const xPx = (v) => p.x + ((v - x0) / (x1 - x0)) * p.w;
    ctx.clearRect(0, 0, this.width, this.height);
    ctx.fillStyle = t.panel;
    ctx.fillRect(0, 0, this.width, this.height);

    ctx.save();
    ctx.beginPath(); ctx.rect(p.x, p.y, p.w, p.h); ctx.clip();
    for (const band of this.spec.bands || []) {
      if (band.x1 < x0 || band.x0 > x1) continue;
      ctx.fillStyle = band.color;
      ctx.fillRect(xPx(band.x0), p.y, Math.max(1, xPx(band.x1) - xPx(band.x0)), p.h);
    }
    ctx.restore();

    // grid and axes
    ctx.font = `10px ${t.font}`;
    ctx.textBaseline = 'middle';
    ctx.textAlign = 'right';
    ctx.lineWidth = 1;
    const showY = !this.spec.series.every((s) => s.normalize);
    const yTicks = showY ? niceTicks(y0, y1, Math.max(2, Math.floor(p.h / 34))) : [];
    const yStep = yTicks.length > 1 ? yTicks[1] - yTicks[0] : undefined;
    for (const v of yTicks) {
      const y = Math.round(yPx(v)) + 0.5;
      ctx.strokeStyle = t.grid; ctx.beginPath(); ctx.moveTo(p.x, y); ctx.lineTo(p.x + p.w, y); ctx.stroke();
      ctx.fillStyle = t.muted; ctx.fillText(fmtTick(v, yStep), p.x - 6, y);
    }
    const xTicks = g.options.ticks(x0, x1, Math.max(2, Math.floor(p.w / 90)));
    ctx.textAlign = 'center'; ctx.textBaseline = 'top';
    for (const v of xTicks) {
      const x = Math.round(xPx(v)) + 0.5;
      ctx.strokeStyle = t.grid; ctx.beginPath(); ctx.moveTo(x, p.y); ctx.lineTo(x, p.y + p.h); ctx.stroke();
      if (this.isLast) { ctx.fillStyle = t.muted; ctx.fillText(g.options.xFormat(v, x1 - x0 < 20), x, p.y + p.h + 4); }
    }

    ctx.save();
    ctx.beginPath(); ctx.rect(p.x, p.y, p.w, p.h); ctx.clip();
    // bands (e.g. p05..p95)
    for (const s of this.spec.series) {
      if (!s.band) continue;
      ctx.fillStyle = t.band;
      ctx.beginPath();
      let started = false;
      for (let i = 0; i < s.times.length; i++) { const x = xPx(s.times[i]); const y = yPx(s.band.hi[i]); if (!started) { ctx.moveTo(x, y); started = true; } else ctx.lineTo(x, y); }
      for (let i = s.times.length - 1; i >= 0; i--) ctx.lineTo(xPx(s.times[i]), yPx(s.band.lo[i]));
      ctx.closePath(); ctx.fill();
    }
    // lines
    const buckets = Math.max(50, Math.floor(p.w));
    for (const s of this.spec.series) {
      const lo = s.normalize ? s.normalize[0] : 0;
      const hi = s.normalize ? s.normalize[1] : 1;
      const mapY = s.normalize ? (v) => p.y + p.h - ((v - lo) / (hi - lo || 1)) * p.h * 0.9 - p.h * 0.05 : yPx;
      const d = minMaxDecimate(s.times, s.values, x0, x1, buckets);
      if (d.count === 0) continue;
      ctx.strokeStyle = s.color; ctx.lineWidth = s.lineWidth || 1.4; ctx.lineJoin = 'round';
      if (!s.markersOnly) {
        ctx.beginPath();
        let penDown = false;
        for (let i = 0; i < d.count; i++) {
          const x = xPx(d.x[i]), y = mapY(d.y[i]);
          if (!penDown || hasGapBetween(s.gapIdx, d.idx[i - 1], d.idx[i])) { ctx.moveTo(x, y); penDown = true; } else ctx.lineTo(x, y);
        }
        ctx.stroke();
      }
      if (s.points || s.markersOnly || (!d.decimated && d.count < p.w / 5)) {
        ctx.fillStyle = s.color;
        for (let i = 0; i < d.count; i++) { ctx.beginPath(); ctx.arc(xPx(d.x[i]), mapY(d.y[i]), s.markersOnly ? 3.5 : 2, 0, Math.PI * 2); ctx.fill(); }
      }
    }
    // markers
    ctx.font = `10px ${t.font}`;
    ctx.textAlign = 'left'; ctx.textBaseline = 'top';
    let lastLabelX = -1e9;
    for (const m of this.spec.markers || []) {
      if (m.x < x0 || m.x > x1) continue;
      const x = Math.round(xPx(m.x)) + 0.5;
      ctx.strokeStyle = m.color || t.warn; ctx.setLineDash([4, 3]); ctx.beginPath(); ctx.moveTo(x, p.y); ctx.lineTo(x, p.y + p.h); ctx.stroke(); ctx.setLineDash([]);
      if (m.label && this.isFirstWithLabels && x - lastLabelX > 60) {
        ctx.fillStyle = m.color || t.warn; ctx.fillText(m.label.slice(0, 18), x + 3, p.y + 2); lastLabelX = x;
      }
    }
    // brush
    if (g.brush) {
      const bx0 = xPx(g.brush[0]), bx1 = xPx(g.brush[1]);
      ctx.fillStyle = t.brush; ctx.fillRect(bx0, p.y, bx1 - bx0, p.h);
      ctx.strokeStyle = t.accent; ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(Math.round(bx0) + 0.5, p.y); ctx.lineTo(Math.round(bx0) + 0.5, p.y + p.h); ctx.moveTo(Math.round(bx1) + 0.5, p.y); ctx.lineTo(Math.round(bx1) + 0.5, p.y + p.h); ctx.stroke();
    }
    // crosshair + dots
    if (g.cursor !== null && g.cursor !== undefined && g.cursor >= x0 && g.cursor <= x1) {
      const x = Math.round(xPx(g.cursor)) + 0.5;
      ctx.strokeStyle = t.muted; ctx.lineWidth = 1; ctx.setLineDash([2, 3]);
      ctx.beginPath(); ctx.moveTo(x, p.y); ctx.lineTo(x, p.y + p.h); ctx.stroke(); ctx.setLineDash([]);
      for (const s of this.spec.series) {
        const k = nearestIndex(s.times, g.cursor);
        if (k < 0 || Math.abs(s.times[k] - g.cursor) > s.gapSeconds) continue;
        const lo = s.normalize ? s.normalize[0] : 0;
        const hi = s.normalize ? s.normalize[1] : 1;
        const y = s.normalize ? p.y + p.h - ((s.values[k] - lo) / (hi - lo || 1)) * p.h * 0.9 - p.h * 0.05 : yPx(s.values[k]);
        ctx.fillStyle = s.color; ctx.beginPath(); ctx.arc(xPx(s.times[k]), y, 3.5, 0, Math.PI * 2); ctx.fill();
      }
    }
    ctx.restore();
    // cursor time label on the last panel
    if (this.isLast && g.cursor !== null && g.cursor !== undefined && g.cursor >= x0 && g.cursor <= x1) {
      const label = g.options.xFormat(g.cursor, true);
      ctx.font = `600 10px ${t.font}`;
      const w = ctx.measureText(label).width + 10;
      const x = Math.min(Math.max(xPx(g.cursor) - w / 2, p.x), p.x + p.w - w);
      ctx.fillStyle = t.accent; roundRectPath(ctx, x, p.y + p.h + 2, w, 15, 4); ctx.fill();
      ctx.fillStyle = t.dark ? '#00232b' : '#ffffff'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(label, x + w / 2, p.y + p.h + 10);
    }
    // outer frame
    ctx.strokeStyle = t.grid; ctx.lineWidth = 1; ctx.strokeRect(p.x + 0.5, p.y + 0.5, p.w, p.h);
  }
}
