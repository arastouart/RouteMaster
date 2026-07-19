#!/usr/bin/env bash
#
# build.sh — generate the Xcode project and build a Release RouteMaster.app with the
# helper embedded.
#
# Signing mode is chosen from the DEV_TEAM environment variable:
#   * DEV_TEAM empty  -> LOCAL_DEV: self-signed "RouteMaster Local Dev" identity
#   * DEV_TEAM=<TEAM_ID> -> Developer ID: real identity + RELEASE code-signing requirement
#
# Output: build/Build/Products/Release/RouteMaster.app
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
BUILD_DIR="${ROOT}/build"
SCHEME="RouteMaster"
LOCAL_CERT_CN="RouteMaster Local Dev"

echo "==> Ensuring XcodeGen is installed"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "    xcodegen not found. Install with: brew install xcodegen" >&2
  exit 1
fi

echo "==> Generating Xcode project"
xcodegen generate

# Choose signing configuration.
EXTRA_SETTINGS=()
if [[ -n "${DEV_TEAM:-}" ]]; then
  echo "==> Developer ID mode (DEV_TEAM=${DEV_TEAM})"
  EXTRA_SETTINGS+=(
    "DEVELOPMENT_TEAM=${DEV_TEAM}"
    "CODE_SIGN_IDENTITY=Developer ID Application"
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS=RELEASE_SIGNING"
  )
else
  echo "==> LOCAL_DEV mode (self-signed: ${LOCAL_CERT_CN})"
  if ! security find-identity -v -p codesigning | grep -qF "${LOCAL_CERT_CN}"; then
    echo "    Missing local identity. Run scripts/make_local_cert.sh first." >&2
    exit 1
  fi
  EXTRA_SETTINGS+=(
    "DEVELOPMENT_TEAM="
    "CODE_SIGN_IDENTITY=${LOCAL_CERT_CN}"
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS=LOCAL_DEV"
  )
fi

echo "==> Building ${SCHEME} (Release)"
xcodebuild \
  -project RouteMaster.xcodeproj \
  -scheme "${SCHEME}" \
  -configuration Release \
  -derivedDataPath "${BUILD_DIR}" \
  CODE_SIGN_STYLE=Manual \
  "${EXTRA_SETTINGS[@]}" \
  build

APP="${BUILD_DIR}/Build/Products/Release/RouteMaster.app"
echo "==> Built: ${APP}"
echo "==> Verifying embedded helper layout"
test -f "${APP}/Contents/MacOS/RouteMasterHelper" \
  && echo "    OK: Contents/MacOS/RouteMasterHelper"
test -f "${APP}/Contents/Library/LaunchDaemons/com.routemaster.helper.plist" \
  && echo "    OK: Contents/Library/LaunchDaemons/com.routemaster.helper.plist"

echo "==> Signing (inside-out) via scripts/sign.sh"
"${ROOT}/scripts/sign.sh" "${APP}"

echo "==> build.sh complete."
