import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const html = readFileSync(new URL('../../prototype/settings.html', import.meta.url), 'utf8');
const section = (start, end) => html.slice(html.indexOf(start), html.indexOf(end, html.indexOf(start)));
const sent = [], previews = [], timers = [];
const context = vm.createContext({
  send: m => sent.push(m), toPreview: m => previews.push(m),
  setTimeout: fn => timers.push(fn), clearTimeout() {},
  $: () => ({ checked: false }), themeById: () => ({ adaptive: true }),
  state: { theme: 'beach', params: {}, capabilities: { saveAcknowledgement: true } },
  flashSaved() { throw Error('Must wait for native ACK'); }
});
vm.runInContext(section('let pending =', "$('controls').addEventListener('input'"), context);
vm.runInContext(section('function flush()', 'let savedT ='), context);
vm.runInContext("setParam('adaptive', 0); flush(); state.theme = 'meadow'; setParam('adaptive', 1);", context);
// The old scheduled timer may fire after switching; edits still retain origin.
for (const timer of timers) timer();
assert.deepEqual(JSON.parse(JSON.stringify(sent)), [
  { t: 'set', theme: 'beach', key: 'adaptive', value: 0 },
  { t: 'set', theme: 'meadow', key: 'adaptive', value: 1 }
]);
assert.match(html, /flush\(\);\s+state.theme = b.dataset.id/);
assert.match(html, /flush\(\);\s+state.theme = m.id/);
for (const settingsDpr of [1, 2]) for (const previewDpr of [1, 1.5, 2]) {
  const messages = [];
  const c = vm.createContext({ window: { devicePixelRatio: settingsDpr },
    state: { iconsScale: 1, screen: { w: 1707.5, h: 1067.25, coordinateScale: 1 } },
    frame: { contentWindow: { devicePixelRatio: previewDpr, postMessage: m => messages.push(JSON.parse(m)) } } });
  vm.runInContext(section('const toPreview =', 'function layoutPreview()'), c);
  vm.runInContext("toPreview({t:'icons',vis:true,r:[[1.25,2.5,77.75,102.75]]})", c);
  assert.deepEqual(messages[0].r[0].map(n => n / previewDpr), [1.25, 2.5, 77.75, 102.75]);
  assert.equal(vm.runInContext('screenCss().w', c), 1707.5);
}
{
  const messages = [];
  const c = vm.createContext({ window: { devicePixelRatio: 2 },
    state: { iconsScale: null, screen: { w: 3840, h: 2160 } },
    frame: { contentWindow: { devicePixelRatio: 2, postMessage: m => messages.push(JSON.parse(m)) } } });
  vm.runInContext(section('const toPreview =', 'function layoutPreview()'), c);
  vm.runInContext("toPreview({t:'icons',vis:true,r:[[20,40,60,80]]})", c);
  assert.deepEqual(messages[0].r[0], [20, 40, 60, 80], 'Legacy Windows messages are unchanged');
  assert.equal(vm.runInContext('screenCss().w', c), 1920);
}
console.log('Settings tests passed (theme-scoped pending edits, ACK gating, mixed-DPR preview, legacy Windows)');
