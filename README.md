# Deskland — experimental macOS fork

A **Mac-only development fork** of [BLEZZ0102/Deskland](https://github.com/BLEZZ0102/Deskland), adapting its icon-aware landscapes to macOS with Swift, AppKit, and WKWebView.

This fork is maintained at **[tmhoule/Deskland](https://github.com/tmhoule/Deskland)**. It is not an official upstream Mac release. There is no signed/notarized download yet. The Windows host and installer have been removed from this fork; Windows users should use the upstream project.

## Build and run

Requires macOS 14 or later and full Xcode. Apple Silicon is locally tested; Intel is not yet validated.

```sh
bash mac/build.sh
open "mac/build/Deskland Preview.app"
```

The locally built app uses an ad-hoc development signature. It runs from the menu bar and does not replace your system wallpaper. Quit from its menu to remove the desktop surface. Rebuilding may require renewing Accessibility permission.

**Icon adaptation requires permission:** use the application's Enable Icon Adaptation action and enable it in System Settings → Privacy & Security → Accessibility. Without permission the wallpaper still runs, but does not adapt to real icons. No permission is granted automatically.

Settings opens at launch and provides Beach/Meadow switching, live previews, parameter controls, English/Simplified Chinese, and persistent per-theme landscapes. Closing Settings leaves the wallpaper running; use the menu bar to reopen Settings or quit.

See [`mac/README.md`](mac/README.md) for diagnostics, testing, and known limitations. This is active development, not a completed macOS release; exports, login startup, automatic window-coverage pause, and distribution packaging remain outside the current milestone.

## Themes and privacy

The shared renderer includes **Beach** and **Meadow**. Eleven additional themes remain locked display metadata and thumbnails only—no implementation or parameters are included for them. Locked cards must never switch the wallpaper.

Finder integration reads geometry, not file names, paths, file contents, or desktop screenshots. Finder's locally observed accessibility tree exposes image bounds rather than full label bounds. Desktop icon movement was manually verified in the initial prototype; localized discovery, Stacks, hidden icons, and the broader Spaces/Stage Manager/display matrix still need testing.

The interface supports English and Simplified Chinese. No accounts, entitlement service, purchase restoration, automatic updater, or store integration is included.

## Development checks

Node.js is needed for JavaScript tests and browser preview only, not to run the app.

```sh
bash mac/test.sh
bash mac/resource-test.sh
```

For a browser-only preview with sample icons:

```sh
node prototype/serve.mjs
```

Open `http://localhost:5178/settings.html`. Actual Finder integration requires the native app. Native smoke-test commands and their limitations are documented in [`mac/README.md`](mac/README.md).

## Layout

| Path | Purpose |
| --- | --- |
| `mac/` | Native host, development build, and tests |
| `prototype/flat.html` | Beach renderer |
| `prototype/meadow.html` | Meadow renderer |
| `prototype/settings.html` | Shared settings interface and previews |
| `prototype/themes.json` | Free-theme definitions and locked-theme metadata |
| `prototype/i18n/` | English and Simplified Chinese |
| `prototype/thumbs/` | Original manually designed thumbnails |

## License and attribution

Original source and included theme assets are from the Deskland authors and licensed under [GPL-3.0](LICENSE). See [NOTICE](NOTICE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The upstream name and icon are not granted as trademarks. This repository identifies the source project and is an experimental fork, not an official endorsement. No new release branding or icons have been created; any modified distribution must follow [TRADEMARKS.md](TRADEMARKS.md), with branding resolved before a public binary release.

---

## 简体中文

这是 [Deskland 上游项目](https://github.com/BLEZZ0102/Deskland)的 **macOS 实验分支**，维护于 [tmhoule/Deskland](https://github.com/tmhoule/Deskland)，并非上游官方 Mac 发布版。此分支已移除 Windows 宿主与安装器。

使用 macOS 14+ 和完整 Xcode，运行 `bash mac/build.sh`，再打开 `mac/build/Deskland Preview.app`。真实图标适配需要在系统设置中授予辅助功能权限；未授权时仍可运行非自适应壁纸。当前采用本地临时签名，尚未签名公证发行，重建后可能需要重新授权。

仅包含沙滩与草地的完整实现，其他 11 个主题仅有锁定展示资料。只保留简体中文和英文，不提供账号、授权恢复、自动更新或商店接口。构建、测试、实现进度和限制见 [`mac/README.md`](mac/README.md)。许可、来源与商标说明见上述链接。
