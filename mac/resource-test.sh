#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
mkdir -p "$ROOT/mac/build/tests"
TEST_DIR="$(mktemp -d "$ROOT/mac/build/tests/resource.XXXXXX")"
# Only this invocation's isolated test directory is removed.
trap 'rm -rf -- "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 "$ROOT/mac/Sources/ResourceScheme.swift" \
  "$ROOT/mac/Tests/ResourceSchemeTests.swift" -o "$TEST_DIR/resource-tests"
"$TEST_DIR/resource-tests" "$TEST_DIR"
