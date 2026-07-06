#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/secrets.local.env"

usage() {
  cat <<'EOF'
Upload Apple signing + notarization secrets to GitHub Actions.

Usage:
  1. Copy secrets.local.env.example to secrets.local.env
  2. Fill in all values
  3. Run: ./scripts/setup_github_secrets.sh

Requires: gh CLI authenticated with workflow scope (gh auth login)
EOF
}

if ! command -v gh >/dev/null; then
  echo "error: gh CLI not found. Install from https://cli.github.com/" >&2
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  usage
  echo "" >&2
  echo "error: missing $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

required_vars=(
  P12_PATH
  P12_PASSWORD
  APPLE_ID
  APPLE_APP_PASSWORD
  APPLE_TEAM_ID
  KEYCHAIN_PASSWORD
  CODESIGN_IDENTITY
)

for var in "${required_vars[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "error: $var is not set in secrets.local.env" >&2
    exit 1
  fi
done

if [ ! -f "$P12_PATH" ]; then
  echo "error: P12 file not found at: $P12_PATH" >&2
  exit 1
fi

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
echo "Setting secrets on $REPO ..."

CERT_B64="$(base64 < "$P12_PATH" | tr -d '\n')"

gh secret set DEVELOPER_ID_APP_CERT_P12_BASE64 --body "$CERT_B64" -R "$REPO"
gh secret set DEVELOPER_ID_APP_CERT_PASSWORD --body "$P12_PASSWORD" -R "$REPO"
gh secret set APPLE_ID --body "$APPLE_ID" -R "$REPO"
gh secret set APPLE_APP_PASSWORD --body "$APPLE_APP_PASSWORD" -R "$REPO"
gh secret set APPLE_TEAM_ID --body "$APPLE_TEAM_ID" -R "$REPO"
gh secret set KEYCHAIN_PASSWORD --body "$KEYCHAIN_PASSWORD" -R "$REPO"
gh secret set CODESIGN_IDENTITY --body "$CODESIGN_IDENTITY" -R "$REPO"

echo ""
echo "Done. Installed secrets:"
gh secret list -R "$REPO"
