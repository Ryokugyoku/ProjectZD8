// Histogram and box plot chart (overlay of several series).
import { h, fitCanvas, fmt, fmtTick, frameThrottle, observeSize } from './analysis-dom.js';
import { theme, watchTheme } from './analysis-theme.js';
import { niceTicks } from './analysis-stats.js';

const M = { left: 46, right: 12, top: 8, bottom: 22 };

export class HistogramChart {
  constructor(container) {
    this.canvas = h('canvas', { class: 'bc-canvas' });
    this.tip = h('div', { class: 'chart-tip', hidden: true });
    this.el = h('div', { class: 'bc-wrap' }, this.canvas, this.tip);
    container.append(this.el);
    this.width = 360; this.height = 220; this.data = null;
    this.requestDraw = frameThrottle(() => this.draw());
    this.stopObserve = observeSize(this.el, (w, hh) => { this.width = Math.max(w, 120); this.height = Math.max(hh, 120); this.requestDraw(); });
    this.unwatch = watchTheme(() => this.requestDraw());
    this.canvas.addEventListener('pointermove', (e) => this.hoverAt(e));
    this.canvas.addEventListener('pointerleave', () => { this.tip.hidden = true; });
  }

  /**
   * data: { series: [{ label, color, hist: { edges, counts, total }, box }], unit, xLabel }
   * Histograms are drawn as density (share of samples) so differently sized sessions compare fairly.
   */
  setData(data) { this.data = data; this.requestDraw(); }

  layout() {
    const d = this.data;
    const boxRows = d ? d.series.filter((s) => s.box && s.box.n > 0).length : 0;
    const boxH = Math.min(boxRows * 16, 80);
    return { x: M.left, y: M.top, w: this.width - M.left - M.right, h: this.height - M.top - M.bottom - boxH - (boxH ? 8 : 0), boxY: this.height - M.bottom - boxH, boxH };
  }

  domain() {
    let lo = Infinity, hi = -Infinity, top = 0;
    for (const s of this.data.series) {
      if (!s.hist || !s.hist.total) continue;
      lo = Math.min(lo, s.hist.min); hi = Math.max(hi, s.hist.max);
      for (const c of s.hist.counts) top = Math.max(top, c / s.hist.total);
    }
    return { lo, hi, top: top || 1 };
  }

  hoverAt(e) {
    if (!this.data) return;
    const rect = this.canvas.getBoundingClientRect();
    const px = e.clientX - rect.left;
    const p = this.layout();
    const { lo, hi } = this.domain();
    if (!(hi > lo) || px < p.x || px > p.x + p.w) { this.tip.hidden = true; return; }
    const v = lo + ((px - p.x) / p.w) * (hi - lo);
    const lines = [`${fmt(v)} ${this.data.unit || ''}`];
    for (const s of this.data.series) {
      if (!s.hist || !s.hist.total) continue;
      let b = Math.floor((v - s.hist.min) / s.hist.binWidth);
      if (b < 0 || b >= s.hist.counts.length) continue;
      lines.push(`${s.label}: ${(s.hist.counts[b] / s.hist.total * 100).toFixed(1)} % (${s.hist.counts[b]})`);
    }
    this.tip.replaceChildren(...lines.map((l) => h('div', { text: l })));
    this.tip.hidden = false;
    this.tip.style.left = `${Math.min(px + 10, this.width - 170)}px`;
    this.tip.style.top = `${Math.max(e.clientY - rect.top - 30, 0)}px`;
  }

  draw() {
    const t = theme();
    const ctx = fitCanvas(this.canvas, this.width, this.height);
    ctx.fillStyle = t.panel; ctx.fillRect(0, 0, this.width, this.height);
    if (!this.data) return;
    const p = this.layout();
    const { lo, hi, top } = this.domain();
    if (!(hi > lo)) { ctx.fillStyle = t.muted; ctx.font = `12px ${t.font}`; ctx.textAlign = 'center'; ctx.fillText('—', this.width / 2, this.height / 2); return; }
    const xPx = (v) => p.x + ((v - lo) / (hi - lo)) * p.w;
    const yPx = (f) => p.y + p.h - (f / top) * p.h * 0.95;
    ctx.font = `10px ${t.font}`; ctx.lineWidth = 1;
    const xTicks = niceTicks(lo, hi, Math.max(2, Math.floor(p.w / 70)));
    const step = xTicks.length > 1 ? xTicks[1] - xTicks[0] : undefined;
    ctx.textAlign = 'center'; ctx.textBaseline = 'top';
    for (const v of xTicks) { const x = Math.round(xPx(v)) + 0.5; ctx.strokeStyle = t.grid; ctx.beginPath(); ctx.moveTo(x, p.y); ctx.lineTo(x, p.boxY + p.boxH); ctx.stroke(); ctx.fillStyle = t.muted; ctx.fillText(fmtTick(v, step), x, this.height - M.bottom + 5); }
    ctx.textAlign = 'right'; ctx.textBaseline = 'middle';
    for (const f of niceTicks(0, top, 3)) { const y = Math.round(yPx(f)) + 0.5; ctx.strokeStyle = t.grid; ctx.beginPath(); ctx.moveTo(p.x, y); ctx.lineTo(p.x + p.w, y); ctx.stroke(); ctx.fillStyle = t.muted; ctx.fillText(`${Math.round(f * 100)}%`, p.x - 5, y); }
    this.data.series.forEach((s, i) => {
      const color = s.color || t.series[i % t.series.length];
      if (s.hist && s.hist.total) {
        ctx.globalAlpha = this.data.series.length > 1 ? 0.45 : 0.75;
        ctx.fillStyle = color;
        for (let b = 0; b < s.hist.counts.length; b++) {
          const x0 = xPx(s.hist.edges[b]), x1 = xPx(s.hist.edges[b + 1]);
          const y = yPx(s.hist.counts[b] / s.hist.total);
          ctx.fillRect(x0 + 0.5, y, Math.max(1, x1 - x0 - 1), p.y + p.h - y);
        }
        ctx.globalAlpha = 1;
        if (this.data.series.length > 1) {
          ctx.strokeStyle = color; ctx.lineWidth = 1.5; ctx.beginPath();
          for (let b = 0; b < s.hist.counts.length; b++) {
            const x0 = xPx(s.hist.edges[b]), x1 = xPx(s.hist.edges[b + 1]), y = yPx(s.hist.counts[b] / s.hist.total);
            if (b === 0) ctx.moveTo(x0, y); else ctx.lineTo(x0, y);
            ctx.lineTo(x1, y);
          }
          ctx.stroke();
        }
      }
    });
    let row = 0;
    this.data.series.forEach((s, i) => {
      if (!s.box || s.box.n === 0) return;
      const color = s.color || t.series[i % t.series.length];
      const y = p.boxY + row * 16 + 8; row++;
      const b = s.box;
      ctx.strokeStyle = color; ctx.fillStyle = color; ctx.lineWidth = 1.5;
      ctx.beginPath(); ctx.moveTo(xPx(b.lowWhisker), y); ctx.lineTo(xPx(b.highWhisker), y); ctx.moveTo(xPx(b.lowWhisker), y - 4); ctx.lineTo(xPx(b.lowWhisker), y + 4); ctx.moveTo(xPx(b.highWhisker), y - 4); ctx.lineTo(xPx(b.highWhisker), y + 4); ctx.stroke();
      ctx.globalAlpha = 0.35; ctx.fillRect(xPx(b.q1), y - 5, Math.max(1, xPx(b.q3) - xPx(b.q1)), 10); ctx.globalAlpha = 1;
      ctx.strokeRect(xPx(b.q1), y - 5, Math.max(1, xPx(b.q3) - xPx(b.q1)), 10);
      ctx.lineWidth = 2.5; ctx.beginPath(); ctx.moveTo(xPx(b.median), y - 5); ctx.lineTo(xPx(b.median), y + 5); ctx.stroke();
    });
    ctx.strokeStyle = t.grid; ctx.strokeRect(p.x + 0.5, p.y + 0.5, p.w, p.h);
  }

  toCanvas() { this.draw(); return this.canvas; }
  destroy() { this.stopObserve(); this.unwatch(); this.el.remove(); }
}
