// Map table: a 2-D binned grid drawn as a heat map with a cell read-out.
import { h, fitCanvas, fmt, fmtTick, frameThrottle, observeSize } from './analysis-dom.js';
import { heatColor, theme, watchTheme } from './analysis-theme.js';
import { cellBounds } from './analysis-binning.js';
import { niceTicks } from './analysis-stats.js';

const M = { left: 58, right: 64, top: 10, bottom: 38 };

export class HeatmapChart {
  constructor(container) {
    this.canvas = h('canvas', { class: 'hm-canvas' });
    this.tip = h('div', { class: 'chart-tip', hidden: true });
    this.el = h('div', { class: 'hm-wrap' }, this.canvas, this.tip);
    container.append(this.el);
    this.width = 480; this.height = 340; this.grid = null; this.selected = null; this.onSelect = null;
    this.requestDraw = frameThrottle(() => this.draw());
    this.stopObserve = observeSize(this.el, (w, hh) => { this.width = Math.max(w, 160); this.height = Math.max(hh, 180); this.requestDraw(); });
    this.unwatch = watchTheme(() => this.requestDraw());
    this.canvas.addEventListener('pointermove', (e) => this.hoverAt(e, false));
    this.canvas.addEventListener('pointerdown', (e) => this.hoverAt(e, true));
    this.canvas.addEventListener('pointerleave', () => { this.tip.hidden = true; this.hovered = null; this.requestDraw(); });
  }

  /** grid: result of binGrid. opts: { mode: 'occupancy' | 'mean', xLabel, yLabel, zLabel, xUnit, yUnit, zUnit, occupancyUnit } */
  setData(grid, opts) { this.grid = grid; this.opts = opts; this.selected = null; this.requestDraw(); }

  get plot() { return { x: M.left, y: M.top, w: this.width - M.left - M.right, h: this.height - M.top - M.bottom }; }

  cellValue(i) {
    const g = this.grid;
    return this.opts.mode === 'mean' ? g.mean[i] : g.occupancy[i];
  }

  range() {
    const g = this.grid;
    return this.opts.mode === 'mean' ? [g.zMin, g.zMax] : [0, g.maxOccupancy];
  }

  cellAt(px, py) {
    const p = this.plot;
    const g = this.grid;
    if (!g || px < p.x || px > p.x + p.w || py < p.y || py > p.y + p.h) return null;
    const ix = Math.min(g.nx - 1, Math.floor(((px - p.x) / p.w) * g.nx));
    const iy = Math.min(g.ny - 1, Math.floor(((p.y + p.h - py) / p.h) * g.ny));
    return { ix, iy, index: iy * g.nx + ix };
  }

  hoverAt(e, select) {
    const rect = this.canvas.getBoundingClientRect();
    const px = e.clientX - rect.left, py = e.clientY - rect.top;
    const cell = this.cellAt(px, py);
    this.hovered = cell;
    if (!cell) { this.tip.hidden = true; this.requestDraw(); return; }
    if (select) { this.selected = cell; if (this.onSelect) this.onSelect(cell); }
    const g = this.grid, o = this.opts;
    const b = cellBounds(g, cell.ix, cell.iy);
    const lines = [
      `${o.xLabel}: ${fmt(b.x0)} – ${fmt(b.x1)} ${o.xUnit || ''}`,
      `${o.yLabel}: ${fmt(b.y0)} – ${fmt(b.y1)} ${o.yUnit || ''}`,
      `${o.occupancyLabel}: ${fmt(g.occupancy[cell.index])} s (n=${g.count[cell.index]})`,
    ];
    if (o.mode === 'mean') lines.push(`${o.zLabel}: ${fmt(g.mean[cell.index])} ${o.zUnit || ''}`);
    this.tip.replaceChildren(...lines.map((l) => h('div', { text: l })));
    this.tip.hidden = false;
    this.tip.style.left = `${Math.min(px + 12, this.width - 210)}px`;
    this.tip.style.top = `${Math.max(py - 40, 0)}px`;
    this.requestDraw();
  }

  draw() {
    const t = theme();
    const ctx = fitCanvas(this.canvas, this.width, this.height);
    ctx.fillStyle = t.panel; ctx.fillRect(0, 0, this.width, this.height);
    if (!this.grid) return;
    const p = this.plot, g = this.grid;
    const cw = p.w / g.nx, ch = p.h / g.ny;
    const [lo, hi] = this.range();
    for (let iy = 0; iy < g.ny; iy++) for (let ix = 0; ix < g.nx; ix++) {
      const i = iy * g.nx + ix;
      const v = this.cellValue(i);
      if (!Number.isFinite(v) || (this.opts.mode === 'occupancy' && v <= 0) || g.count[i] === 0) continue;
      ctx.fillStyle = heatColor((v - lo) / (hi - lo || 1));
      ctx.fillRect(p.x + ix * cw, p.y + p.h - (iy + 1) * ch, Math.ceil(cw), Math.ceil(ch));
      if (cw >= 34 && ch >= 16) {
        ctx.fillStyle = (v - lo) / (hi - lo || 1) > 0.55 ? '#00181e' : t.fg;
        ctx.font = `9px ${t.font}`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        ctx.fillText(fmt(v, this.opts.mode === 'mean' ? 1 : 0), p.x + (ix + 0.5) * cw, p.y + p.h - (iy + 0.5) * ch);
      }
    }
    ctx.strokeStyle = t.grid; ctx.lineWidth = 1; ctx.strokeRect(p.x + 0.5, p.y + 0.5, p.w, p.h);
    ctx.font = `10px ${t.font}`;
    const xTicks = niceTicks(g.xMin, g.xMax, Math.max(2, Math.floor(p.w / 70)));
    const yTicks = niceTicks(g.yMin, g.yMax, Math.max(2, Math.floor(p.h / 40)));
    ctx.textAlign = 'center'; ctx.textBaseline = 'top'; ctx.fillStyle = t.muted;
    const xs = xTicks.length > 1 ? xTicks[1] - xTicks[0] : undefined, ys = yTicks.length > 1 ? yTicks[1] - yTicks[0] : undefined;
    for (const v of xTicks) ctx.fillText(fmtTick(v, xs), p.x + ((v - g.xMin) / (g.xMax - g.xMin)) * p.w, p.y + p.h + 4);
    ctx.textAlign = 'right'; ctx.textBaseline = 'middle';
    for (const v of yTicks) ctx.fillText(fmtTick(v, ys), p.x - 5, p.y + p.h - ((v - g.yMin) / (g.yMax - g.yMin)) * p.h);
    ctx.fillStyle = t.fg; ctx.font = `600 11px ${t.font}`; ctx.textAlign = 'center'; ctx.textBaseline = 'bottom';
    ctx.fillText(`${this.opts.xLabel}${this.opts.xUnit ? ' [' + this.opts.xUnit + ']' : ''}`, p.x + p.w / 2, this.height - 2);
    ctx.save(); ctx.translate(12, p.y + p.h / 2); ctx.rotate(-Math.PI / 2); ctx.textBaseline = 'top'; ctx.fillText(`${this.opts.yLabel}${this.opts.yUnit ? ' [' + this.opts.yUnit + ']' : ''}`, 0, -4); ctx.restore();
    // colour bar
    const bx = p.x + p.w + 14, bh = p.h;
    for (let i = 0; i < bh; i++) { ctx.fillStyle = heatColor(1 - i / (bh - 1)); ctx.fillRect(bx, p.y + i, 10, 1); }
    ctx.fillStyle = t.muted; ctx.font = `10px ${t.font}`; ctx.textAlign = 'left'; ctx.textBaseline = 'top'; ctx.fillText(fmt(hi), bx + 14, p.y);
    ctx.textBaseline = 'bottom'; ctx.fillText(fmt(lo), bx + 14, p.y + bh);
    for (const cell of [this.hovered, this.selected]) {
      if (!cell) continue;
      ctx.strokeStyle = t.fg; ctx.lineWidth = 2;
      ctx.strokeRect(p.x + cell.ix * cw + 1, p.y + p.h - (cell.iy + 1) * ch + 1, cw - 2, ch - 2);
    }
  }

  toCanvas() { this.draw(); return this.canvas; }
  destroy() { this.stopObserve(); this.unwatch(); this.el.remove(); }
}
