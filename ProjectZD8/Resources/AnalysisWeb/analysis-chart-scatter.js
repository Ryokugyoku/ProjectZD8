// XY scatter chart: points coloured by a third channel, density mode, regression line, pan / zoom.
import { h, fitCanvas, fmt, fmtTick, frameThrottle, observeSize } from './analysis-dom.js';
import { heatColor, theme, watchTheme } from './analysis-theme.js';
import { niceTicks } from './analysis-stats.js';

const M = { left: 60, right: 14, top: 10, bottom: 38 };

export class ScatterChart {
  constructor(container) {
    this.canvas = h('canvas', { class: 'sc-canvas' });
    this.canvas.style.touchAction = 'none';
    this.tip = h('div', { class: 'chart-tip', hidden: true });
    this.el = h('div', { class: 'sc-wrap' }, this.canvas, this.tip);
    container.append(this.el);
    this.width = 400; this.height = 320;
    this.data = null; this.opts = {}; this.view = null; this.hover = -1; this.pointers = new Map();
    this.requestDraw = frameThrottle(() => this.draw());
    this.stopObserve = observeSize(this.el, (w, hh) => { this.width = Math.max(w, 120); this.height = Math.max(hh, 160); this.requestDraw(); });
    this.unwatch = watchTheme(() => this.requestDraw());
    this.bind();
  }

  /**
   * data: { x, y, z } Float64Arrays (z may contain NaN). opts: { xLabel, yLabel, zLabel, xUnit, yUnit, zUnit,
   * density, regression: { slope, intercept, r2 } | null, categorical }
   */
  setData(data, opts) {
    this.data = data;
    this.opts = opts;
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity, z0 = Infinity, z1 = -Infinity;
    for (let i = 0; i < data.n; i++) {
      if (data.x[i] < x0) x0 = data.x[i]; if (data.x[i] > x1) x1 = data.x[i];
      if (data.y[i] < y0) y0 = data.y[i]; if (data.y[i] > y1) y1 = data.y[i];
      const z = data.z[i];
      if (Number.isFinite(z)) { if (z < z0) z0 = z; if (z > z1) z1 = z; }
    }
    if (data.n === 0) { x0 = 0; x1 = 1; y0 = 0; y1 = 1; }
    if (x0 === x1) { x0 -= 1; x1 += 1; }
    if (y0 === y1) { y0 -= 1; y1 += 1; }
    const px = (x1 - x0) * 0.04, py = (y1 - y0) * 0.04;
    this.full = [x0 - px, x1 + px, y0 - py, y1 + py];
    this.view = [...this.full];
    this.zRange = z0 <= z1 ? [z0, z1] : null;
    this.requestDraw();
  }

  reset() { if (this.full) { this.view = [...this.full]; this.requestDraw(); } }

  get plot() { return { x: M.left, y: M.top, w: this.width - M.left - M.right, h: this.height - M.top - M.bottom }; }

  toX(v) { const p = this.plot; return p.x + ((v - this.view[0]) / (this.view[1] - this.view[0])) * p.w; }
  toY(v) { const p = this.plot; return p.y + p.h - ((v - this.view[2]) / (this.view[3] - this.view[2])) * p.h; }
  fromX(px) { const p = this.plot; return this.view[0] + ((px - p.x) / p.w) * (this.view[1] - this.view[0]); }
  fromY(py) { const p = this.plot; return this.view[2] + ((p.y + p.h - py) / p.h) * (this.view[3] - this.view[2]); }

  bind() {
    const c = this.canvas;
    let drag = null;
    c.addEventListener('pointerdown', (e) => {
      c.setPointerCapture(e.pointerId);
      this.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
      drag = this.pointers.size === 2 ? { pinch: this.pinch() } : { x: e.clientX, y: e.clientY, view: [...this.view] };
    });
    c.addEventListener('pointermove', (e) => {
      const rect = c.getBoundingClientRect();
      if (this.pointers.has(e.pointerId)) this.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
      if (drag && drag.pinch && this.pointers.size >= 2) {
        const now = this.pinch();
        this.zoom(drag.pinch.distance / Math.max(now.distance, 1), now.cx - rect.left, now.cy - rect.top);
        drag.pinch = now;
        return;
      }
      if (drag && drag.view) {
        const p = this.plot;
        const dx = ((e.clientX - drag.x) / p.w) * (drag.view[1] - drag.view[0]);
        const dy = ((e.clientY - drag.y) / p.h) * (drag.view[3] - drag.view[2]);
        this.view = [drag.view[0] - dx, drag.view[1] - dx, drag.view[2] + dy, drag.view[3] + dy];
        this.requestDraw();
        return;
      }
      this.updateHover(e.clientX - rect.left, e.clientY - rect.top);
    });
    const end = (e) => { this.pointers.delete(e.pointerId); if (this.pointers.size === 0) drag = null; else if (drag && drag.pinch) drag = { x: e.clientX, y: e.clientY, view: [...this.view] }; };
    c.addEventListener('pointerup', end);
    c.addEventListener('pointercancel', end);
    c.addEventListener('pointerleave', () => { this.hover = -1; this.tip.hidden = true; this.requestDraw(); });
    c.addEventListener('wheel', (e) => { e.preventDefault(); const r = c.getBoundingClientRect(); this.zoom(Math.exp(e.deltaY * (e.ctrlKey ? 0.01 : 0.0015)), e.clientX - r.left, e.clientY - r.top); }, { passive: false });
    c.addEventListener('dblclick', () => this.reset());
  }

  pinch() {
    const [a, b] = [...this.pointers.values()];
    return { distance: Math.hypot(a.x - b.x, a.y - b.y), cx: (a.x + b.x) / 2, cy: (a.y + b.y) / 2 };
  }

  zoom(factor, px, py) {
    const f = Math.min(Math.max(factor, 0.05), 20);
    const cx = this.fromX(px), cy = this.fromY(py);
    this.view = [cx - (cx - this.view[0]) * f, cx + (this.view[1] - cx) * f, cy - (cy - this.view[2]) * f, cy + (this.view[3] - cy) * f];
    this.requestDraw();
  }

  updateHover(px, py) {
    if (!this.data || this.opts.density) { this.tip.hidden = true; return; }
    const d = this.data;
    let best = -1, bestD = 14 * 14;
    for (let i = 0; i < d.n; i++) {
      const dx = this.toX(d.x[i]) - px, dy = this.toY(d.y[i]) - py;
      const dist = dx * dx + dy * dy;
      if (dist < bestD) { bestD = dist; best = i; }
    }
    this.hover = best;
    if (best < 0) { this.tip.hidden = true; this.requestDraw(); return; }
    const o = this.opts;
    const lines = [`${o.xLabel}: ${fmt(d.x[best])} ${o.xUnit || ''}`, `${o.yLabel}: ${fmt(d.y[best])} ${o.yUnit || ''}`];
    if (o.zLabel && Number.isFinite(d.z[best])) lines.push(`${o.zLabel}: ${fmt(d.z[best])} ${o.zUnit || ''}`);
    this.tip.replaceChildren(...lines.map((l) => h('div', { text: l })));
    this.tip.hidden = false;
    this.tip.style.left = `${Math.min(px + 12, this.width - 150)}px`;
    this.tip.style.top = `${Math.max(py - 10, 0)}px`;
    this.requestDraw();
  }

  colorFor(i) {
    const d = this.data;
    const z = d.z[i];
    if (!this.zRange || !Number.isFinite(z)) return theme().accent;
    if (this.opts.categorical) return theme().series[(Math.max(1, Math.round(z)) - 1) % theme().series.length];
    return heatColor((z - this.zRange[0]) / (this.zRange[1] - this.zRange[0] || 1));
  }

  draw() {
    const t = theme();
    const ctx = fitCanvas(this.canvas, this.width, this.height);
    const p = this.plot;
    ctx.fillStyle = t.panel; ctx.fillRect(0, 0, this.width, this.height);
    if (!this.data) return;
    const xTicks = niceTicks(this.view[0], this.view[1], Math.max(2, Math.floor(p.w / 80)));
    const yTicks = niceTicks(this.view[2], this.view[3], Math.max(2, Math.floor(p.h / 40)));
    ctx.font = `10px ${t.font}`; ctx.lineWidth = 1;
    ctx.textAlign = 'center'; ctx.textBaseline = 'top';
    const xs = xTicks.length > 1 ? xTicks[1] - xTicks[0] : undefined;
    const ys = yTicks.length > 1 ? yTicks[1] - yTicks[0] : undefined;
    for (const v of xTicks) { const x = Math.round(this.toX(v)) + 0.5; ctx.strokeStyle = t.grid; ctx.beginPath(); ctx.moveTo(x, p.y); ctx.lineTo(x, p.y + p.h); ctx.stroke(); ctx.fillStyle = t.muted; ctx.fillText(fmtTick(v, xs), x, p.y + p.h + 4); }
    ctx.textAlign = 'right'; ctx.textBaseline = 'middle';
    for (const v of yTicks) { const y = Math.round(this.toY(v)) + 0.5; ctx.strokeStyle = t.grid; ctx.beginPath(); ctx.moveTo(p.x, y); ctx.lineTo(p.x + p.w, y); ctx.stroke(); ctx.fillStyle = t.muted; ctx.fillText(fmtTick(v, ys), p.x - 6, y); }
    ctx.fillStyle = t.fg; ctx.font = `600 11px ${t.font}`; ctx.textAlign = 'center'; ctx.textBaseline = 'bottom';
    ctx.fillText(`${this.opts.xLabel || ''}${this.opts.xUnit ? ' [' + this.opts.xUnit + ']' : ''}`, p.x + p.w / 2, this.height - 2);
    ctx.save(); ctx.translate(12, p.y + p.h / 2); ctx.rotate(-Math.PI / 2); ctx.textBaseline = 'top';
    ctx.fillText(`${this.opts.yLabel || ''}${this.opts.yUnit ? ' [' + this.opts.yUnit + ']' : ''}`, 0, -4); ctx.restore();

    ctx.save(); ctx.beginPath(); ctx.rect(p.x, p.y, p.w, p.h); ctx.clip();
    const d = this.data;
    if (this.opts.density) this.drawDensity(ctx, p);
    else {
      const stride = d.n > 60000 ? Math.ceil(d.n / 60000) : 1;
      ctx.globalAlpha = d.n > 5000 ? 0.55 : 0.85;
      for (let i = 0; i < d.n; i += stride) {
        const x = this.toX(d.x[i]), y = this.toY(d.y[i]);
        if (x < p.x - 3 || x > p.x + p.w + 3 || y < p.y - 3 || y > p.y + p.h + 3) continue;
        ctx.fillStyle = this.colorFor(i);
        ctx.fillRect(x - 1.5, y - 1.5, 3, 3);
      }
      ctx.globalAlpha = 1;
    }
    const r = this.opts.regression;
    if (r && Number.isFinite(r.slope)) {
      ctx.strokeStyle = t.warn; ctx.lineWidth = 2; ctx.setLineDash([6, 4]);
      ctx.beginPath(); ctx.moveTo(this.toX(this.view[0]), this.toY(r.slope * this.view[0] + r.intercept)); ctx.lineTo(this.toX(this.view[1]), this.toY(r.slope * this.view[1] + r.intercept)); ctx.stroke(); ctx.setLineDash([]);
    }
    if (this.hover >= 0 && !this.opts.density) { ctx.strokeStyle = t.fg; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(this.toX(d.x[this.hover]), this.toY(d.y[this.hover]), 6, 0, Math.PI * 2); ctx.stroke(); }
    ctx.restore();
    ctx.strokeStyle = t.grid; ctx.lineWidth = 1; ctx.strokeRect(p.x + 0.5, p.y + 0.5, p.w, p.h);
    if (this.zRange && !this.opts.density && !this.opts.categorical) this.drawColorBar(ctx, p);
  }

  drawDensity(ctx, p) {
    const d = this.data;
    const cell = 6;
    const nx = Math.max(1, Math.ceil(p.w / cell)), ny = Math.max(1, Math.ceil(p.h / cell));
    const grid = new Float64Array(nx * ny);
    let max = 0;
    for (let i = 0; i < d.n; i++) {
      const ix = Math.floor((this.toX(d.x[i]) - p.x) / cell), iy = Math.floor((this.toY(d.y[i]) - p.y) / cell);
      if (ix < 0 || iy < 0 || ix >= nx || iy >= ny) continue;
      const c = ++grid[iy * nx + ix];
      if (c > max) max = c;
    }
    for (let iy = 0; iy < ny; iy++) for (let ix = 0; ix < nx; ix++) {
      const c = grid[iy * nx + ix];
      if (!c) continue;
      ctx.fillStyle = heatColor(Math.sqrt(c / max));
      ctx.fillRect(p.x + ix * cell, p.y + iy * cell, cell, cell);
    }
  }

  drawColorBar(ctx, p) {
    const t = theme();
    const w = 90, x = p.x + p.w - w - 8, y = p.y + 8;
    for (let i = 0; i < w; i++) { ctx.fillStyle = heatColor(i / (w - 1)); ctx.fillRect(x + i, y, 1, 8); }
    ctx.fillStyle = t.fg; ctx.font = `10px ${t.font}`; ctx.textBaseline = 'top'; ctx.textAlign = 'left';
    ctx.fillText(fmt(this.zRange[0]), x, y + 11); ctx.textAlign = 'right'; ctx.fillText(fmt(this.zRange[1]), x + w, y + 11);
    ctx.textAlign = 'center'; ctx.fillText(this.opts.zLabel || '', x + w / 2, y + 22);
  }

  toCanvas() { this.draw(); return this.canvas; }

  destroy() { this.stopObserve(); this.unwatch(); this.el.remove(); }
}
