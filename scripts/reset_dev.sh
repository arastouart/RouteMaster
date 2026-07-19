#!/usr/bin/env bash
#
# reset_dev.sh — unregister the RouteMaster daemon during development iteration.
#
# The clean path is SMAppService.unregister(), which the app exposes via
# "Uninstall Helper". This script provides a CLI equivalent plus documents the
# last-resort nuclear option.
set -euo pipefail

PLIST_LABEL="com.routemaster.helper"

echo "==> Attempting to bootout the daemon (if currently loaded)"
sudo launchctl bootout system/"${PLIST_LABEL}" 2>/dev/null \
  && echo "    booted out ${PLIST_LABEL}" \
  || echo "    ${PLIST_LABEL} not loaded (ok)"

echo
echo "The supported way to unregister is from the app: 'Uninstall Helper'"
echo "(calls SMAppService.unregister()). Prefer that."
echo
echo "-------------------------------------------------------------------------"
echo "LAST RESORT ONLY — do NOT run casually:"
echo
echo "    sudo sfltool resetbtm"
echo
echo "This clears the ENTIRE Background Task Management database — i.e. ALL login"
echo "items and daemons for ALL apps on this Mac, not just RouteMaster. You will"
echo "have to re-approve every background item afterwards. Use only if the daemon"
echo "is wedged and unregister() will not clear it. A reboot is often enough."
echo "-------------------------------------------------------------------------"
