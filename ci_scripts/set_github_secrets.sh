#!/usr/bin/env bash
# Usage: ./ci_scripts/set_github_secrets.sh \
#   --issuer-id <UUID> \
#   [--repo owner/repo] \
#   [--auth-key path/to/AuthKey_*.p8] \
#   [--p12 path/to/Certificates.p12] \
#   [--p12-password password] \
#   [--keychain-password password] \
#   [--app-profile path/to/AppTemplate.mobileprovision]
set -euo pipefail

REPO=""
ISSUER_ID=""
AUTH_KEY_PATH=""
P12_PATH=""
P12_PASSWORD=""
KEYCHAIN_PASSWORD=""
APP_PROFILE_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --issuer-id) ISSUER_ID="$2"; shift 2 ;;
    --auth-key) AUTH_KEY_PATH="$2"; shift 2 ;;
    --p12) P12_PATH="$2"; shift 2 ;;
    --p12-password) P12_PASSWORD="$2"; shift 2 ;;
    --keychain-password) KEYCHAIN_PASSWORD="$2"; shift 2 ;;
    --app-profile) APP_PROFILE_PATH="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  REPO="$(git remote get-url origin | sed 's/.*github.com[:/]//' | sed 's/\.git$//')"
fi
echo "Target repo: $REPO"

if [[ -z "$AUTH_KEY_PATH" ]]; then
  AUTH_KEY_PATH="$(ls -t ~/Downloads/AuthKey_*.p8 2>/dev/null | head -1 || true)"
fi

if [[ -z "$AUTH_KEY_PATH" ]] || [[ ! -f "$AUTH_KEY_PATH" ]]; then
  echo "Error: --auth-key not provided and no AuthKey_*.p8 found in ~/Downloads" >&2
  exit 1
fi

KEY_ID="$(basename "$AUTH_KEY_PATH" .p8 | sed 's/AuthKey_//')"
echo "Using App Store Connect key: $KEY_ID"

gh secret set APP_STORE_CONNECT_KEY_ID --body "$KEY_ID" --repo "$REPO"
gh secret set APP_STORE_CONNECT_ISSUER_ID --body "$ISSUER_ID" --repo "$REPO"
gh secret set APP_STORE_CONNECT_API_KEY_P8 < "$AUTH_KEY_PATH" --repo "$REPO"

if [[ -n "$P12_PATH" ]] && [[ -f "$P12_PATH" ]]; then
  P12_B64="$(base64 -i "$P12_PATH")"
  gh secret set APPLE_DISTRIBUTION_CERTIFICATE_BASE64 --body "$P12_B64" --repo "$REPO"
  gh secret set APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD --body "$P12_PASSWORD" --repo "$REPO"
  if [[ -z "$KEYCHAIN_PASSWORD" ]]; then
    KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"
  fi
  gh secret set KEYCHAIN_PASSWORD --body "$KEYCHAIN_PASSWORD" --repo "$REPO"
  echo "Uploaded distribution certificate."
fi

if [[ -n "$APP_PROFILE_PATH" ]] && [[ -f "$APP_PROFILE_PATH" ]]; then
  PROFILE_B64="$(base64 -i "$APP_PROFILE_PATH")"
  gh secret set APP_PROVISION_PROFILE_BASE64 --body "$PROFILE_B64" --repo "$REPO"
  echo "Uploaded app provisioning profile."
fi

echo "Done. GitHub secrets updated for $REPO."
