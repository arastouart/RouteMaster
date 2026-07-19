#!/usr/bin/env bash
#
# run.sh — launch the built RouteMaster.app.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Build/Products/Release/RouteMaster.app"

if [[ ! -d "${APP}" ]]; then
  echo "Not built yet. Run scripts/build.sh first." >&2
  exit 1
fi

echo "==> Launching ${APP}"
open "${APP}"
echo "==> Daemon logs (once installed + started):"
echo "    /Library/Logs/RouteMaster/helper.err.log"
echo "    /Library/Logs/RouteMaster/helper.out.log"
