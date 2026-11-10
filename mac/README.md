# Deskland Preview — macOS P1

This Mac-only fork uses native AppKit windows and WKWebView to run the shared Beach and Meadow renderers and existing `settings.html`. Requires macOS 14+, Xcode Command Line Tools, and Node.js for JavaScript tests. Build architecture follows the local machine; this is not a universal or signed distribution.

## Build and run

```sh
bash mac/build.sh
open 'mac/build/Deskland Preview.app'
```

The menu-bar app opens Settings at launch. Settings supports Beach/Meadow selection, live parameter previews, stable per-theme seeds, and English/Simplified Chinese. Other themes show purchase information only. Closing Settings leaves the wallpaper running; reopen it from the menu bar. Pause/Resume, Reload Wallpaper, Diagnostics and Quit are available there too.

The bundle identifier remains `app.deskland.preview.mac.p0` and executable remains `DesklandPreviewP0` for local Accessibility permission continuity. This does not mean the build is still P0. Local builds default to ad-hoc signing; macOS can require renewed permission after rebuilding or moving the app. To use an existing Apple Development identity consistently across rebuilds, quit the app first and set `DESKLAND_SIGNING_IDENTITY` to the certificate name or SHA-1 when building:

```sh
security find-identity -v -p codesigning
DESKLAND_SIGNING_IDENTITY='YOUR DEVELOPMENT CERTIFICATE NAME OR SHA-1' bash mac/build.sh
```

Use the same app path and identity each time. Development signing does not guarantee Accessibility trust and is not a notarized distribution signature. After changing signatures, add or re-enable this exact app in **System Settings → Privacy & Security → Accessibility**, then quit and reopen it. Do not reset the system privacy database. macOS versions vary in how their permissions list is edited.

## Troubleshooting: icons stop generating land after a rebuild

If the wallpaper renders a flat beach with **no sand/land around your desktop icons** (or the Settings live preview shows only icon placeholders), the usual cause is that the new binary **lost its Accessibility grant**, not a code regression.

- The Finder icon provider returns an **empty icon list** when `AXIsProcessTrusted()` is false. With no icon geometry the renderer has nothing to raise land from, so it draws a flat scene while still running at full frame rate. The smoke test does **not** catch this: it passes with zero icons because it only verifies rendering, not Finder permission.
- A rebuilt ad-hoc-signed binary has a **different code signature**, and macOS re-locks the Accessibility trust after rebuilds or app moves. So `bash mac/build.sh` (default ad-hoc signing) can silently drop the grant every time.
- Recovery: quit the app, re-grant in **System Settings → Privacy & Security → Accessibility** for this exact app, then reopen. Or use the menu-bar **Enable Icon Adaptation…** action (and the Settings banner button) to re-prompt. The in-app menu-bar "Icons:" item and Diagnostics show whether the icon read is `ready` or `permissionRequired`.
- To avoid the repeated re-grant, build with a stable Apple Development identity (`DESKLAND_SIGNING_IDENTITY=… bash mac/build.sh`) and keep the same app path; re-add the app to Accessibility once after changing the identity. Do **not** "fix" the missing land by inventing icon geometry or skipping the permission gate.

## Privacy and permission

Without Accessibility access the wallpaper still renders. Settings shows an explicit onboarding banner when permission is needed. Only clicking its permission button or the menu-bar Enable Icon Adaptation action requests access. Nothing automatically changes system privacy settings. The provider reads Finder icon positions, not filenames, file contents, screenshots or telemetry. Geometry stays local.

Settings are validated against the two free themes in bundled `themes.json` and stored atomically at:

```text
~/Library/Application Support/DesklandPreview/settings.json
```

Numeric values must be finite, within registry bounds, and on the declared step. Unknown themes/parameters, booleans masquerading as numbers, and unsupported locales are rejected. Both themes retain stable seeds across relaunches. Successful save indicators require a host acknowledgement after the atomic write; failed writes roll back native state.

The app has no accounts, activation service, updates, login startup integration, sharing/export, or purchase restoration. Unsupported controls are hidden/disabled via host capabilities. Purchase actions open only the fixed `https://deskland.app` URL in the default browser; bridged views cannot navigate to external pages.

## Tests and runtime smoke

```sh
bash mac/test.sh
node --test mac/Tests/bridge.test.mjs mac/Tests/settings.test.mjs
bash mac/resource-test.sh
bash mac/build.sh
PROFILE="$(mktemp -d mac/build/tests/smoke.XXXXXX)"
trap 'rm -rf "$PROFILE"' EXIT
'mac/build/Deskland Preview.app/Contents/MacOS/DesklandPreviewP0' --windowed --smoke-test --theme=beach --settings --profile-dir "$PROFILE"
'mac/build/Deskland Preview.app/Contents/MacOS/DesklandPreviewP0' --windowed --smoke-test --theme=meadow --settings --profile-dir "$PROFILE"
```

Quit any existing instance first. `--profile-dir PATH` isolates tests from the normal profile. `--theme=beach` or `--theme=meadow` overrides the running theme without changing the saved selection; actual user selections in Settings still save normally. `--windowed` maps the main desktop geometry into a resizable comparison window rather than placing the renderer behind Finder. Smoke mode samples the real theme render counter, pauses at 5 seconds, resumes at 9 seconds, reports JSON, and exits after 15 seconds (nonzero on failure). `--settings` additionally closes and reopens Settings, verifies WebView teardown and readiness, persisted parameters, all 13 decoded thumbnails, disabled unsupported features and the iframe's WebGL renderer. Smoke does not request permission or interact with other apps.

## Implementation and remaining limits

- Only the main display is targeted. Screen dimensions and Finder bounds use fractional logical points; the wallpaper bridge converts icons to backing pixels using its current DPR. Settings receives unconverted logical geometry and `screen.coordinateScale: 1` / `iconsScale: 1`.
- Settings and wallpaper have separate nonpersistent WebKit stores and role-checked message handling. Only trusted main-frame Settings messages can change native state or request permission. Settings previews do not receive native privileges.
- Bundle assembly is an explicit allowlist: Settings, registry, bridge, two free renderers and their assets, 13 existing thumbnails, embedded thumbnail data, and English/Simplified Chinese text. Locked implementations are not included.
- Sleep/session inactivity pause rendering; display/Space changes refresh the target geometry. Repeated wallpaper WebContent crashes are bounded to three reload attempts.
- Finder image bounds are not guaranteed label bounds. Hidden desktop icons, localized Finder discovery, multiple monitors, Spaces, Stage Manager, prolonged energy usage and signed distribution need further manual validation. Permission/read failures appear in Settings and diagnostics; wallpapers continue rendering. Explicit permission actions also open the Accessibility settings pane so a previously denied grant can be changed.
- P1 smoke validates rendering and the Settings handshake, not every desktop arrangement or manual permission flow. There is no notarization, installer, public release, auto-restart service or release branding change in this work.
