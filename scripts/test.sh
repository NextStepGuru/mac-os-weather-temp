#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Running tests (arm64)..."
swift test --arch arm64

echo ""
echo "All tests passed."
