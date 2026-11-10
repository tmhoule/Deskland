// P0 compatibility adapter: keep existing Windows/theme code unchanged.
(() => {
  'use strict';
  const listeners = new Set();
  const errors = [];
  const report = message => {
    errors.push(String(message).slice(0, 300));
    if (errors.length > 8) errors.shift();
  };
  addEventListener('error', event => report(event.message));
  addEventListener('unhandledrejection', event => report(event.reason));
  window.chrome = window.chrome || {};
  window.chrome.webview = {
    postMessage(message) { window.webkit.messageHandlers.deskland.postMessage(message); },
    addEventListener(type, listener) { if (type === 'message') listeners.add(listener); },
    removeEventListener(type, listener) { if (type === 'message') listeners.delete(listener); }
  };
  window.__desklandReceive = message => {
    try {
      if (typeof message === 'string') message = JSON.parse(message);
      if (!message || typeof message !== 'object') return;
      // Settings consumes logical points; wallpaper handlers divide by their DPR.
      const settings = /(?:^|\/)settings\.html$/.test(window.location?.pathname || '');
      if (message.t === 'icons' && !settings) {
        const scale = window.devicePixelRatio || 1;
        message = { ...message, r: message.r.map(rect => rect.map(n => n * scale)) };
      }
      const event = { data: JSON.stringify(message) };
      for (const listener of listeners) {
        try { listener(event); } catch (error) { report(error); }
      }
    } catch (error) { report(error); }
  };
  // Read actual theme render counters, not a separate RAF loop: a healthy
  // diagnostic timer does not prove that WebKit is drawing the wallpaper.
  window.__desklandDiagnostics = () => ({
    frames: typeof frameN === 'number' ? frameN : null,
    fps: typeof fpsEMA === 'number' ? fpsEMA : null,
    paused: typeof paused === 'boolean' ? paused : null,
    webgl: typeof gl !== 'undefined' && !!gl,
    contextLost: typeof gl !== 'undefined' && gl ? gl.isContextLost() : null,
    icons: typeof icons !== 'undefined' ? icons.length : null,
    viewport: [innerWidth, innerHeight],
    dpr: devicePixelRatio,
    canvas: typeof cv !== 'undefined' ? [cv.width, cv.height] : null,
    visibility: document.visibilityState,
    errors: errors.slice()
  });
})();
