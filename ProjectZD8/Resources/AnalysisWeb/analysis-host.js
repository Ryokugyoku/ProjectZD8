// Bridge to the native host (WKWebView script messages) and file export fallbacks.
import { utf8ToBase64 } from './analysis-csv.js';

const handler = () => window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.analysisBridge;

/** True when running inside the native app. */
export function hasHost() {
  return Boolean(handler());
}

/** Sends a message to the native side; ignored when running standalone in a browser. */
export function postToHost(message) {
  const h = handler();
  if (h) h.postMessage(message);
}

/** Registers the function the host calls with configuration updates (window.RTHost.receive). */
export function onHostMessage(callback) {
  window.RTHost = { receive: (message) => callback(message) };
}

function download(filename, blob) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = filename;
  document.body.append(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
}

/** Exports a CSV text through the native share/save sheet, or as a browser download. */
export function exportCsv(filename, text) {
  if (hasHost()) postToHost({ type: 'export', filename, mimeType: 'text/csv', base64: utf8ToBase64(text) });
  else download(filename, new Blob([text], { type: 'text/csv;charset=utf-8' }));
}

/** Exports a canvas as PNG through the native side, or as a browser download. */
export function exportPng(filename, canvas) {
  if (hasHost()) {
    const base64 = canvas.toDataURL('image/png').split(',')[1];
    postToHost({ type: 'export', filename, mimeType: 'image/png', base64 });
  } else canvas.toBlob((blob) => download(filename, blob), 'image/png');
}
