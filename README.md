# RouteMaster

Domain-based split-routing and VPN-bypass utility for macOS 13+.

> **Status:** source distribution. Full usage, signing/distribution, and legal notes are
> completed in Phase 8. This is the scaffold placeholder.

RouteMaster installs **host routes** at the OS routing-table level so specific domains egress
the physical interface (en0) instead of the active VPN tunnel, plus a location-aware
kill-switch ("Geo-Lock"). Everything is **dry-run by default** — no live routing changes happen
until you explicitly disable dry-run and confirm.

See the full README after Phase 8.
