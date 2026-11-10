import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../Resources/bridge.js', import.meta.url), 'utf8');
for (const pathname of ['/settings.html', '/beach.html']) for (const dpr of [1, 1.5, 2]) {
  const sent = [];
  const context = vm.createContext({
    window: { location: { pathname }, devicePixelRatio: dpr, webkit: { messageHandlers: { deskland: { postMessage: m => sent.push(m) } } } },
    devicePixelRatio: dpr, innerWidth: 1000, innerHeight: 700,
    document: { visibilityState: 'visible' }, addEventListener() {}
  });
  vm.runInContext('let frameN = 12, fpsEMA = 30, paused = false, icons = []; const cv = {width: 2000, height: 1400}; const gl = {isContextLost: () => false};', context);
  vm.runInContext(source, context);
  const host = context.window.chrome.webview;
  host.postMessage('ready');
  assert.deepEqual(sent, ['ready']);
  let received;
  const listener = event => { received = JSON.parse(event.data); };
  host.addEventListener('message', listener);
  const input = {t: 'icons', vis: true, r: [[1.25, 2.5, 77.75, 102.75]]};
  context.window.__desklandReceive(input);
  assert.deepEqual(received.r[0], input.r[0].map(n => n * (pathname === '/settings.html' ? 1 : dpr)));
  host.addEventListener('message', () => { throw new Error('isolated callback'); });
  context.window.__desklandReceive('{invalid');
  context.window.__desklandReceive(JSON.stringify(input));
  assert.equal(received.t, 'icons', 'Malformed input and callback failures do not break delivery');
  assert.deepEqual(input.r[0], [1.25, 2.5, 77.75, 102.75], 'Do not mutate logical input');
  context.window.__desklandReceive({t: 'pause', v: true});
  assert.deepEqual(received, {t: 'pause', v: true});
  assert.equal(context.window.__desklandDiagnostics().frames, 12);
  host.removeEventListener('message', listener);
  context.window.__desklandReceive({t: 'pause', v: false});
  assert.equal(received.v, true);
}
console.log('Bridge tests passed (1×, 1.5×, 2×)');
