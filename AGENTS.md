# Deskland macOS fork development guide

- This is the Mac-only fork at `https://github.com/tmhoule/Deskland`. `origin` must target that fork; `upstream` is `BLEZZ0102/Deskland`. Never push to upstream.
- Communicate with this fork's maintainer in English.
- The Windows host and NSIS tooling are intentionally removed. Do not restore Windows packaging or point downloads to upstream Windows binaries.
- Native host/build/tests live in `mac/`; shared HTML/JS renderers and settings live in `prototype/`.
- Build: `bash mac/build.sh`. Output: `mac/build/Deskland Preview.app`. Check `mac/README.md` for current test and smoke-test commands.
- Browser preview: `node prototype/serve.mjs`, then `http://localhost:5178/settings.html`. Browser mode uses sample icons, not real Finder geometry.
- Only Beach and Meadow have full implementations. The other 11 themes retain names, descriptions, and thumbnails only: no pages, groups, parameters, or scripts. Clicking locked themes opens purchase information and must never change the wallpaper.
- Keep theme defaults, `themes.json`, and English/Simplified Chinese text consistent. Do not add other languages.
- No accounts, license service, purchase restoration, automatic updates, or store integrations.
- Keep icon geometry private: no filenames, paths, desktop screenshots, file contents, or telemetry. Ask for Accessibility access only after an explicit user action; never change privacy settings automatically.
- Preserve fractional logical coordinates and actual backing pixels. Target 30fps, cache static work, and keep small objects in local layers rather than full-screen per-object loops.
- After theme changes test icon movement, preview, pause, and supported sharing paths. Sharing remains unavailable until its native implementation is validated.
- `prototype/thumbs/` contains manually designed thumbnails; never regenerate or overwrite without request.
- Preserve Preview's separate identity and user-data namespace. The prototype bundle ID is retained for local permission continuity; see native code for the current profile directory and test isolation flags.
- Do not commit `mac/build/`, personal profiles, credentials, signing keys, local paths, or generated binaries.
- Keep GPL-3.0 licensing, original copyright, NOTICE, and TRADEMARKS.md intact. The Deskland name/icon are not granted as trademarks. Public binary releases, release branding, and icon changes require explicit maintainer approval; do not publish a release as part of routine development.
- P0 was locally verified at about 30fps on Retina, reading 24 Finder image bounds; the maintainer manually confirmed moving icons adapts the scenery and granting Accessibility access works. This does not validate label bounds, hidden icons, localized AX discovery, Spaces/Stage Manager, energy use, or signed distribution.
