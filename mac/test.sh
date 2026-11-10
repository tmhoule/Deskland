#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/mac/build/tests"
xcrun swiftc -swift-version 5 "$ROOT/mac/Sources/Geometry.swift" "$ROOT/mac/Tests/GeometryTests.swift" \
  -o "$ROOT/mac/build/tests/geometry-tests"
"$ROOT/mac/build/tests/geometry-tests"
xcrun swiftc -swift-version 5 "$ROOT/mac/Sources/SettingsStore.swift" "$ROOT/mac/Tests/SettingsStoreTests.swift" \
  -o "$ROOT/mac/build/tests/settings-store-tests"
TEST_TMP="$(mktemp -d "$ROOT/mac/build/tests/settings.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT
"$ROOT/mac/build/tests/settings-store-tests" "$ROOT/prototype/themes.json" "$TEST_TMP"
node "$ROOT/mac/Tests/bridge.test.mjs"
