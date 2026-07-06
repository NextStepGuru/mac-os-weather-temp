#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Running tests (arm64)..."
swift test --arch arm64

echo "Running tests (x86_64)..."
rm -rf .build/x86_64-apple-macosx
arch -x86_64 swift test --arch x86_64

echo ""
echo "All tests passed on arm64 and x86_64."
