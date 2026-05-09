#!/usr/bin/env bash
set -euo pipefail

KEYCHAIN_PATH="${KEYCHAIN_PATH:-${RUNNER_TEMP:-/tmp}/app-signing.keychain-db}"

if [[ -f "$KEYCHAIN_PATH" ]]; then
  security delete-keychain "$KEYCHAIN_PATH"
  echo "Deleted temporary keychain."
fi

security list-keychains -d user -s \
  "$HOME/Library/Keychains/login.keychain-db" \
  /Library/Keychains/System.keychain

security default-keychain -s "$HOME/Library/Keychains/login.keychain-db"

echo "Restored system keychains."
