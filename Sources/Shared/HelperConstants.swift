import Foundation

/// Constants shared by the app and the privileged daemon: bundle ids, the Mach
/// service name, the root-owned config path, and — most importantly — the two
/// code-signing requirement strings used to validate XPC peers.
///
/// Placeholders the maintainer replaces for a notarized release:
///   * `<BUNDLE_PREFIX>` -> `com.routemaster` (see `bundlePrefix`)
///   * `<TEAM_ID>`       -> the real Apple Developer Team ID (see `releaseTeamOU`)
public enum HelperConstants {

    // MARK: - Identifiers

    /// `<BUNDLE_PREFIX>` — default `com.routemaster`.
    public static let bundlePrefix = "com.routemaster"

    public static let appBundleID = "\(bundlePrefix).app"
    public static let helperBundleID = "\(bundlePrefix).helper"

    /// Mach service the daemon vends and the app connects to.
    public static let machServiceName = "\(bundlePrefix).helper.xpc"

    /// launchd plist file name registered via `SMAppService.daemon(plistName:)`.
    public static let helperPlistName = "\(bundlePrefix).helper.plist"

    // MARK: - Filesystem

    /// Daemon-owned application support directory (root-owned, created by ConfigStore).
    public static let supportDirectory = "/Library/Application Support/RouteMaster"

    /// Single source of truth for configuration. Written 0644, owned by root.
    public static let configPath = "\(supportDirectory)/config.json"

    /// Daemon log directory (matches the launchd plist Std*Path entries).
    public static let logDirectory = "/Library/Logs/RouteMaster"

    // MARK: - Signing requirement selection

    /// Which code-signing requirement family is active. Selected at runtime from the
    /// `RM_SIGNING_MODE` Info.plist key (LOCAL_DEV self-signed vs RELEASE Developer ID).
    public enum SigningMode: String {
        case localDev = "LOCAL_DEV"
        case release = "RELEASE"
    }

    /// `<TEAM_ID>` — placeholder. The maintainer sets this to the real Team ID; it is
    /// the value baked into the leaf certificate's Organizational Unit for Developer ID
    /// certs, which the RELEASE requirement pins.
    public static let releaseTeamOU = "<TEAM_ID>"

    /// Common Name of the self-signed LOCAL_DEV code-signing certificate created by
    /// `scripts/make_local_cert.sh`.
    public static let localDevLeafCN = "RouteMaster Local Dev"

    /// Resolve the active signing mode from an embedded Info.plist value.
    ///
    /// - Parameter infoValue: value of the `RM_SIGNING_MODE` key from the running
    ///   process's Info.plist (app) or embedded `__info_plist` section (daemon).
    public static func signingMode(fromInfoValue infoValue: String?) -> SigningMode {
        SigningMode(rawValue: infoValue ?? "") ?? .localDev
    }

    // MARK: - Requirement strings

    /// Code-signing requirement the DAEMON pins on the connecting APP.
    /// (Used by the daemon's `NSXPCListener` delegate.)
    public static func appRequirement(for mode: SigningMode) -> String {
        switch mode {
        case .localDev:
            // Pin the app identifier + the self-signed leaf common name.
            return """
            identifier "\(appBundleID)" and \
            certificate leaf[subject.CN] = "\(localDevLeafCN)"
            """
        case .release:
            // Apple-issued Developer ID chain, our bundle prefix, our team OU.
            return """
            anchor apple generic and \
            identifier "\(appBundleID)" and \
            certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and \
            certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and \
            certificate leaf[subject.OU] = "\(releaseTeamOU)"
            """
        }
    }

    /// Code-signing requirement the APP pins on the DAEMON.
    /// (Used by the app's `NSXPCConnection.setCodeSigningRequirement`.)
    public static func helperRequirement(for mode: SigningMode) -> String {
        switch mode {
        case .localDev:
            return """
            identifier "\(helperBundleID)" and \
            certificate leaf[subject.CN] = "\(localDevLeafCN)"
            """
        case .release:
            return """
            anchor apple generic and \
            identifier "\(helperBundleID)" and \
            certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and \
            certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and \
            certificate leaf[subject.OU] = "\(releaseTeamOU)"
            """
        }
    }
}
