import Foundation

/// The single choke point for every shell-out to `route`, `ifconfig`, `netstat`,
/// `scutil`, etc. It logs the exact command and honors a global dry-run flag.
///
/// SAFETY: when `dryRun` is true, commands classified as *mutating* (see
/// `Command.mutates`) are NEVER executed — they are only recorded and returned. Read-
/// only inspection commands still run so the UI can show real state.
final class ShellRunner {

    struct Result {
        let command: String
        let exitCode: Int32
        let stdout: String
        let stderr: String
        /// True if this was a mutating command suppressed by dry-run.
        let skippedForDryRun: Bool
    }

    /// A command description. `mutates` marks commands that change system state
    /// (route add/delete, etc.) so dry-run can suppress them.
    struct Command {
        let executable: String
        let arguments: [String]
        let mutates: Bool

        var displayString: String {
            ([executable] + arguments).joined(separator: " ")
        }
    }

    /// Global dry-run flag, updated whenever config changes.
    private(set) var dryRun: Bool

    /// Ring buffer of recent command display strings (for the Logs UI).
    private let logLock = NSLock()
    private var commandLog: [String] = []
    private let maxLogLines = 200

    /// Optional sink for live log lines (wired to the app callback by RoutingService).
    var onLog: ((String) -> Void)?

    init(dryRun: Bool) {
        self.dryRun = dryRun
    }

    func setDryRun(_ value: Bool) {
        dryRun = value
    }

    // MARK: - Logging

    private func record(_ line: String) {
        logLock.lock()
        commandLog.append(line)
        if commandLog.count > maxLogLines {
            commandLog.removeFirst(commandLog.count - maxLogLines)
        }
        logLock.unlock()
        onLog?(line)
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    func recentCommands() -> [String] {
        logLock.lock(); defer { logLock.unlock() }
        return commandLog
    }

    // MARK: - Execution

    /// Run a command. Mutating commands are suppressed (recorded only) when dry-run is on.
    @discardableResult
    func run(_ command: Command) -> Result {
        let display = command.displayString

        if command.mutates && dryRun {
            let line = "[DRY-RUN] would run: \(display)"
            record(line)
            return Result(command: display, exitCode: 0, stdout: "", stderr: "",
                          skippedForDryRun: true)
        }

        record((command.mutates ? "[MUTATE] " : "[read] ") + display)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            let msg = "failed to launch \(display): \(error.localizedDescription)"
            record("[error] " + msg)
            return Result(command: display, exitCode: -1, stdout: "", stderr: msg,
                          skippedForDryRun: false)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Result(
            command: display,
            exitCode: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self),
            skippedForDryRun: false
        )
    }

    // MARK: - Convenience factories (all known executables in one place)

    static let routeBin = "/sbin/route"
    static let ifconfigBin = "/sbin/ifconfig"
    static let netstatBin = "/usr/sbin/netstat"
    static let scutilBin = "/usr/sbin/scutil"

    /// `route -n get default` (read-only).
    func routeGetDefault() -> Result {
        run(Command(executable: Self.routeBin, arguments: ["-n", "get", "default"], mutates: false))
    }

    /// `route -n get <ip>` (read-only) — used to find the physical gateway/iface.
    func routeGet(_ ip: String) -> Result {
        run(Command(executable: Self.routeBin, arguments: ["-n", "get", ip], mutates: false))
    }

    /// `route -n get -ifscope <iface> default` (read-only). Interface-scoped lookup
    /// returns the physical interface's own default gateway even when a VPN owns the
    /// global default route — the key to finding the en0 gateway while a tunnel is up.
    func routeGetDefaultScoped(iface: String) -> Result {
        run(Command(executable: Self.routeBin,
                    arguments: ["-n", "get", "-ifscope", iface, "default"], mutates: false))
    }

    /// `ifconfig -l` (read-only) — space-separated list of interface names.
    func ifconfigList() -> Result {
        run(Command(executable: Self.ifconfigBin, arguments: ["-l"], mutates: false))
    }

    /// `route add -host <ip> <gateway>` (MUTATES).
    func routeAddHost(ip: String, gateway: String) -> Result {
        run(Command(executable: Self.routeBin,
                    arguments: ["add", "-host", ip, gateway], mutates: true))
    }

    /// `route delete -host <ip>` (MUTATES).
    func routeDeleteHost(ip: String) -> Result {
        run(Command(executable: Self.routeBin,
                    arguments: ["delete", "-host", ip], mutates: true))
    }

    /// `route add -host <ip> 127.0.0.1` blackhole to loopback (MUTATES).
    func routeBlackhole(ip: String) -> Result {
        run(Command(executable: Self.routeBin,
                    arguments: ["add", "-host", ip, "127.0.0.1"], mutates: true))
    }

    /// `route delete -host <ip>` used to lift a blackhole (MUTATES).
    func routeUnblackhole(ip: String) -> Result {
        run(Command(executable: Self.routeBin,
                    arguments: ["delete", "-host", ip], mutates: true))
    }

    /// `ifconfig <iface>` (read-only).
    func ifconfig(_ iface: String) -> Result {
        run(Command(executable: Self.ifconfigBin, arguments: [iface], mutates: false))
    }
}
