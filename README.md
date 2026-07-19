# RouteMaster

**Domain-based split-routing and VPN-bypass utility for macOS 13+**, with a
location-aware kill-switch ("Geo-Lock"). Native SwiftUI app + a privileged `launchd`
daemon, distributed as **source** (direct download, not the Mac App Store).

> ⚠️ **Safety first.** RouteMaster is **dry-run by default**. In dry-run it only
> *previews* the routing commands it would run — it never touches the live routing
> table. Nothing mutates your routes until you explicitly disable dry-run **and**
> confirm a warning dialog.

---

## What it does

- **Split routing.** For chosen domains (seed: `bitgraph.ir`), RouteMaster installs
  **host routes** (`route add -host <ip> <physical-gateway>`) that are more specific
  than the VPN's default route, so those domains egress your **physical interface
  (en0)** instead of the tunnel.
- **ISP-accurate resolution.** Split domains are resolved with a raw DNS query sent
  over a UDP socket **bound to the physical interface** (`IP_BOUND_IF` + source-IP
  bind) toward a public resolver (1.1.1.1, fallback 8.8.8.8). This returns the CDN edge
  IPs your ISP would serve — not what the VPN's resolver returns. CDN IP churn is
  handled by re-resolving + reconciling every `resolveIntervalSeconds` (default 300s).
- **Geo-Lock kill-switch.** For chosen domains (seed: `claude.ai` requires `TR`),
  RouteMaster checks your external country over the **default route** (the VPN exit)
  every `geoCheckIntervalSeconds` (default 30s). If the country doesn't match — or the
  VPN default is down — the domain's IPs are **blackholed** to `127.0.0.1`. State flips
  are debounced (N consecutive checks) to avoid flapping, and you get a notification.
- **Glassmorphism UI** (Dark + Light) with a Dashboard, Split Routing, Geo-Lock, and
  Logs screens, plus a **menu bar** item showing engine state, VPN location, and
  Geo-Lock status.

---

## Architecture

```
RouteMaster.app
├─ Contents/MacOS/RouteMaster              # SwiftUI app (non-sandboxed, hardened runtime)
├─ Contents/MacOS/RouteMasterHelper        # privileged daemon (root, via launchd)
└─ Contents/Library/LaunchDaemons/
      com.routemaster.helper.plist          # SMAppService daemon plist
```

- **Privileged helper:** installed with **`SMAppService.daemon(plistName:)`** (macOS 13+).
  No `SMJobBless`, no deprecated bless APIs.
- **IPC:** `NSXPCConnection` / `NSXPCListener`. **Both peers validate each other** with
  `setCodeSigningRequirement(_:)` — no custom auth handshake.
- **Single source of truth:** the daemon owns `/Library/Application Support/RouteMaster/
  config.json` (root, 0644). The app pushes `AppConfig`; the daemon persists + applies.
- **One choke point:** every `route`/`ifconfig`/… shell-out goes through `ShellRunner`,
  which logs the exact command and **suppresses all mutating commands while dry-run is on**.

| Layer | Key files |
|-------|-----------|
| Shared contract | `Sources/Shared/{HelperConstants,RoutingProtocol,DTOs}.swift` |
| Daemon | `Sources/Helper/{main,RoutingService,NetworkInspector,DNSResolver,RouteManager,ConfigStore,EngineLoop,GeoLockLoop,GeoDebouncer,ShellRunner}.swift` |
| App | `Sources/App/{RouteMasterApp,HelperConnection,HelperInstaller,ConfigViewModel}.swift`, `Sources/App/Views/*`, `Sources/App/Design/GlassStyle.swift` |

---

## Build requirements

- macOS **13.0+**
- **Xcode 15+** (Command Line Tools installed)
- **XcodeGen** (`brew install xcodegen`) — the `.xcodeproj` is generated, not committed

## Build from source (no Apple account needed)

```bash
git clone <this-repo> routemaster && cd routemaster
scripts/make_local_cert.sh     # one-time: creates a self-signed "RouteMaster Local Dev" cert
scripts/build.sh               # xcodegen generate + xcodebuild Release + inside-out signing
scripts/run.sh                 # launch the app
```

Then in the app: **Install Helper** (approve it once in *System Settings › General ›
Login Items & Extensions* if prompted), **Start** the engine, and use the **Logs** tab's
*Dry-run preview* to see exactly what would happen. Leave dry-run ON until you're sure.

Run the logic tests:

```bash
xcodebuild -project RouteMaster.xcodeproj -scheme RouteMaster -destination 'platform=macOS' test
```

---

## Signing & Distribution (the honest version)

RouteMaster ships a **privileged `SMAppService` daemon**. macOS will only *install and
run that daemon smoothly* from an app that is **signed with a Developer ID certificate
and notarized by Apple** — which requires a **paid Apple Developer Program membership**.

Because this repository has no Apple account baked in, it is distributed **as source**:

- **You (building locally):** `scripts/make_local_cert.sh` creates a **self-signed**
  "RouteMaster Local Dev" identity, and `scripts/build.sh` signs with Hardened Runtime
  using it. This works **today, for free**. Under this mode Gatekeeper is *not* satisfied
  — `spctl -a -vvv` will report the app as **rejected**. **That is expected** for a
  self-signed, un-notarized build.

- **Gatekeeper bypass for an un-notarized app** (only do this for software you trust and
  built yourself):
  - Right-click the app → **Open** → confirm, **or**
  - `xattr -dr com.apple.quarantine /path/to/RouteMaster.app`

- **A one-click prebuilt binary** for other users requires **Developer ID + notarization**.
  Once you have a paid account and a Team ID, build in Developer ID mode and follow the
  documented notarization steps:
  ```bash
  DEV_TEAM=<TEAM_ID> scripts/build.sh   # signs with "Developer ID Application" + RELEASE requirement
  cat scripts/notarize.sh               # exact notarytool submit + stapler staple commands
  ```

### Placeholders a maintainer must replace for a notarized release

| Placeholder | Meaning | Where |
|-------------|---------|-------|
| `<TEAM_ID>` | Your Apple Developer **Team ID** | `HelperConstants.releaseTeamOU`, `DEV_TEAM` env |
| `<BUNDLE_PREFIX>` | Bundle id prefix (default **`com.routemaster`**) | `HelperConstants.bundlePrefix`, `project.yml`, plists |

The RELEASE XPC code-signing requirements pin `anchor apple generic`, the bundle
identifier, and `certificate leaf[subject.OU] = "<TEAM_ID>"`. LOCAL_DEV pins the
self-signed leaf common name instead. The active mode is selected by the
`RELEASE_SIGNING` Swift compilation condition (`build.sh` sets it when `DEV_TEAM` is set).

---

## Recovering if a route drops connectivity

Host routes added by RouteMaster are volatile (cleared on reboot). If a wrong/stale
route causes trouble:

```bash
sudo route delete -host <ip>     # remove a specific host route
# or simply reboot — volatile host routes do not persist
```

Uninstall the daemon cleanly from the app (**Uninstall Helper**, i.e.
`SMAppService.unregister()`), or via `scripts/reset_dev.sh`.

---

## Legal / responsible use

RouteMaster is a **personal networking tool**. It changes how *your own* machine routes
traffic and where DNS queries egress. **You are solely responsible** for complying with
your local laws and with the terms of service of any network or service you connect to
or bypass. Nothing here is legal advice. Use it only where you are authorized to.

---

## License

MIT — see [LICENSE](LICENSE).
