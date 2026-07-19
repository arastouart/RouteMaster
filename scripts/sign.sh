#!/usr/bin/env bash
#
# sign.sh — code-sign RouteMaster.app INSIDE-OUT (embedded daemon first, then the app)
# with Hardened Runtime.
#
# Usage: scripts/sign.sh /path/to/RouteMaster.app
#
# Signing identity:
#   * DEV_TEAM empty  -> "RouteMaster Local Dev" (self-signed)
#   * DEV_TEAM set    -> "Developer ID Application" (notarize-ready)
#
# NOTE under LOCAL_DEV: `spctl -a -vvv` is EXPECTED TO WARN/REJECT — Gatekeeper only
# accepts Apple-notarized or App-Store apps. That is normal for a self-signed dev build;
# the app still runs (right-click > Open, or xattr -dr com.apple.quarantine). A real
# Developer ID identity + notarization removes the warning (see notarize.sh).
set -euo pipefail

APP="${1:-}"
if [[ -z "${APP}" || ! -d "${APP}" ]]; then
  echo "usage: sign.sh /path/to/RouteMaster.app" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ENT="${ROOT}/Resources/App/App.entitlements"
HELPER_ENT="${ROOT}/Resources/Helper/Helper.entitlements"

if [[ -n "${DEV_TEAM:-}" ]]; then
  IDENTITY="Developer ID Application"
  echo "==> Signing with Developer ID (team ${DEV_TEAM})"
else
  IDENTITY="RouteMaster Local Dev"
  echo "==> Signing with self-signed LOCAL_DEV identity: ${IDENTITY}"
fi

HELPER_BIN="${APP}/Contents/MacOS/RouteMasterHelper"

# 1) Sign the embedded daemon FIRST (inside-out), Hardened Runtime + timestamp.
echo "==> Signing embedded helper: ${HELPER_BIN}"
codesign --force --options runtime --timestamp \
  --entitlements "${HELPER_ENT}" \
  --sign "${IDENTITY}" \
  "${HELPER_BIN}"

# 2) Then sign the app bundle.
echo "==> Signing app: ${APP}"
codesign --force --options runtime --timestamp \
  --entitlements "${APP_ENT}" \
  --sign "${IDENTITY}" \
  "${APP}"

# 3) Verify.
echo "==> Verifying signatures (codesign --verify --deep --strict)"
codesign --verify --deep --strict --verbose=2 "${APP}"

echo "==> codesign display for embedded helper"
codesign -dvvv "${HELPER_BIN}" 2>&1 | grep -E "Identifier|Authority|TeamIdentifier" || true

echo "==> Gatekeeper assessment (spctl). Under LOCAL_DEV a rejection here is EXPECTED:"
spctl -a -vvv "${APP}" || echo "    (expected 'rejected' for a non-notarized self-signed build)"

echo "==> sign.sh complete."
