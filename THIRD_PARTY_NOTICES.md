# Third-party components / 第三方组件

## macOS system frameworks

The native host uses Apple's AppKit, WebKit (WKWebView), ApplicationServices/Accessibility, Foundation, and Core Graphics frameworks provided by macOS. Xcode and its SDK are build tools; their binaries are not included in this repository. Apple components remain subject to Apple's applicable licenses and are not relicensed under this project's GPL-3.0 license.

macOS 原生宿主使用系统提供的 AppKit、WebKit（WKWebView）、ApplicationServices/Accessibility、Foundation 与 Core Graphics。Xcode 和 SDK 仅用于构建，不随仓库分发。Apple 组件适用其自身许可，不因本项目 GPL-3.0 许可而变更。

## Upstream source and assets

The shared themes, settings interface, illustrations, and other original assets derive from [BLEZZ0102/Deskland](https://github.com/BLEZZ0102/Deskland). Original authors retain copyright. See LICENSE, NOTICE, and TRADEMARKS.md.

共享主题、设置界面、插画等原始内容来自 Deskland 上游项目，原作者保留著作权。许可、版权与商标说明见 LICENSE、NOTICE 和 TRADEMARKS.md。

## Historical Windows tooling

Earlier upstream history includes Microsoft Edge WebView2 and NSIS build integration. That host and installer are removed from this Mac-only working tree. Historical dependency notices remain available in Git history; those components are not required or bundled by the Mac build.
