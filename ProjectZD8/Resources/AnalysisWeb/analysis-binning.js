// Two-dimensional binning for map tables. No DOM access.

/**
 * Bins (x, y) points on an nx by ny grid. Cell index = iy * nx + ix (iy = 0 is the lowest y).
 * `weights` (seconds each sample covers) give occupancy time; `zs` gives the per-cell mean.
 * Points outside the range or with non-finite coordinates are ignored.
 */
export function binGrid({ xs, ys, zs = null, weights = null, xMin, xMax, yMin, yMax, nx, ny }) {
  const size = nx * ny;
  const count = new Float64Array(size);
  const occupancy = new Float64Array(size);
  const zSum = new Float64Array(size);
  const zCount = new Float64Array(size);
  const xw = (xMax - xMin) / nx;
  const yw = (yMax - yMin) / ny;
  let total = 0;
  for (let i = 0; i < xs.length; i++) {
    const x = xs[i], y = ys[i];
    if (!Number.isFinite(x) || !Number.isFinite(y) || x < xMin || x > xMax || y < yMin || y > yMax) continue;
    let ix = Math.floor((x - xMin) / xw);
    let iy = Math.floor((y - yMin) / yw);
    if (ix >= nx) ix = nx - 1;
    if (iy >= ny) iy = ny - 1;
    const cell = iy * nx + ix;
    count[cell]++;
    total++;
    if (weights) occupancy[cell] += weights[i];
    if (zs && Number.isFinite(zs[i])) { zSum[cell] += zs[i]; zCount[cell]++; }
  }
  const mean = new Float64Array(size).fill(NaN);
  let zMin = Infinity, zMax = -Infinity, maxCount = 0, maxOccupancy = 0;
  for (let c = 0; c < size; c++) {
    if (zCount[c] > 0) {
      mean[c] = zSum[c] / zCount[c];
      if (mean[c] < zMin) zMin = mean[c];
      if (mean[c] > zMax) zMax = mean[c];
    }
    if (count[c] > maxCount) maxCount = count[c];
    if (occupancy[c] > maxOccupancy) maxOccupancy = occupancy[c];
  }
  return { nx, ny, xMin, xMax, yMin, yMax, count, occupancy, mean, zCount, zMin, zMax, maxCount, maxOccupancy, total };
}

/** Bin boundaries for a cell index. */
export function cellBounds(grid, ix, iy) {
  const xw = (grid.xMax - grid.xMin) / grid.nx;
  const yw = (grid.yMax - grid.yMin) / grid.ny;
  return { x0: grid.xMin + ix * xw, x1: grid.xMin + (ix + 1) * xw, y0: grid.yMin + iy * yw, y1: grid.yMin + (iy + 1) * yw };
}
