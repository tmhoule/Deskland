import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = path => readFileSync(new URL(path, import.meta.url), 'utf8');
const registry = JSON.parse(read('../../prototype/themes.json'));
const html = read('../../prototype/settings.html');
const native = read('../Sources/main.swift');
const locked = registry.themes.filter(theme => theme.locked === true);
assert.equal(locked.length, 11);
for (const locale of ['en', 'zh-CN']) {
  const translations = JSON.parse(read(`../../prototype/i18n/${locale}.json`));
  for (const theme of locked) {
    const translation = translations.themes?.[theme.id];
    if (locale === 'en') {
      assert.ok(translation?.name && translation?.desc, `${locale}: ${theme.id} requires name and description`);
    }
    if (!translation) continue; // Chinese falls back to the registry.
    assert.deepEqual(Object.keys(translation).sort(), ['desc', 'name'], `${locale}: ${theme.id} must contain only name and description`);
  }
  for (const key of ['helpIconsQ', 'helpIconsA', 'helpIconsStep1', 'helpIconsStep2', 'helpWallpaperQ', 'helpWallpaperA', 'helpWallpaperStep1', 'helpWallpaperStep2', 'helpWallpaperStep3']) {
    assert.ok(translations.ui[key], `${locale}: missing ${key}`);
    assert.ok(html.includes(`data-i18n="${key}"`), `${key} missing from help`);
  }
  const help = Object.keys(translations.ui).filter(key => key.startsWith('help')).map(key => translations.ui[key]).join(' ');
  assert.doesNotMatch(help, /Windows|slideshow|个性化|幻灯片|Ctrl\+Alt/i);
  for (const title of locale === 'en' ? ['Enable Icon Adaptation…', 'Reload Wallpaper', 'Quit Deskland Preview'] : ['启用图标适配…', '重新载入壁纸', '退出 Deskland Preview']) {
    assert.ok(help.includes(title), `${locale}: help does not mention ${title}`);
    assert.ok(native.includes(title), `${locale}: ${title} does not match the native menu`);
  }
}
console.log('i18n tests passed (locked metadata and localized macOS help)');
