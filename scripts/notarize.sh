#!/usr/bin/env bash
#
# notarize.sh — STUB. Documents the exact steps to notarize + staple a RELEASE build
# once a paid Apple Developer Program membership, a Developer ID Application certificate,
# and a real <TEAM_ID> exist. This script intentionally DOES NOT run notarization.
#
# Prerequisites (replace placeholders):
#   * <TEAM_ID>                — your Apple Developer Team ID
#   * "Developer ID Application: <NAME> (<TEAM_ID>)" cert in your keychain
#   * A notarytool credential profile OR an app-specific password
#
# ---------------------------------------------------------------------------
# 0) Build + sign in Developer ID mode:
#       DEV_TEAM=<TEAM_ID> scripts/build.sh
#    (build.sh signs inside-out with Hardened Runtime + --timestamp.)
#
# 1) Store notarization credentials ONCE (creates a keychain profile "routemaster"):
#       xcrun notarytool store-credentials "routemaster" \
#         --apple-id "you@example.com" \
#         --team-id "<TEAM_ID>" \
#         --password "<APP_SPECIFIC_PASSWORD>"
#
# 2) Zip the .app for submission (notarytool accepts .zip/.pkg/.dmg):
#       ditto -c -k --keepParent \
#         "build/Build/Products/Release/RouteMaster.app" \
#         "build/RouteMaster.zip"
#
# 3) Submit and WAIT for the result:
#       xcrun notarytool submit "build/RouteMaster.zip" \
#         --keychain-profile "routemaster" \
#         --wait
#
# 4) On success, STAPLE the ticket to the .app so it validates offline:
#       xcrun stapler staple "build/Build/Products/Release/RouteMaster.app"
#
# 5) Verify Gatekeeper now ACCEPTS it (no warning):
#       spctl -a -vvv "build/Build/Products/Release/RouteMaster.app"
#       codesign --verify --deep --strict --verbose=2 \
#         "build/Build/Products/Release/RouteMaster.app"
#
# 6) (Optional) Distribute inside a signed, stapled DMG:
#       # create DMG, sign it with Developer ID, then:
#       xcrun notarytool submit RouteMaster.dmg --keychain-profile "routemaster" --wait
#       xcrun stapler staple RouteMaster.dmg
# ---------------------------------------------------------------------------

echo "notarize.sh is a documentation stub — it does not run notarization." >&2
echo "See the comments in this file for the exact commands. Build first with:" >&2
echo "    DEV_TEAM=<TEAM_ID> scripts/build.sh" >&2
exit 0
