import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

private let appTitle = "GH Workflow Clean"
private let appSupportDir = NSString(string: "~/Library/Application Support/GH Workflow Clean").expandingTildeInPath
private let lastSessionFile = (appSupportDir as NSString).appendingPathComponent("last-session.env")
private let defaultSearchPaths = [
  "/opt/homebrew/bin",
  "/usr/local/bin",
  "/usr/bin",
  "/bin",
  "/usr/sbin",
  "/sbin"
]

struct AuthHostConfig {
  let host: String
  let activeUser: String?
  let users: [String]
}

struct CommandResult {
  let status: Int32
  let output: String
}

enum StatusKind {
  case ready
  case warning
  case error
  case running

  var tint: Color {
    switch self {
    case .ready: return Color(red: 0.16, green: 0.74, blue: 0.49)
    case .warning: return Color(red: 0.93, green: 0.63, blue: 0.18)
    case .error: return Color(red: 0.88, green: 0.25, blue: 0.24)
    case .running: return Color(red: 0.17, green: 0.56, blue: 0.92)
    }
  }

  var icon: String {
    switch self {
    case .ready: return "checkmark.shield"
    case .warning: return "exclamationmark.triangle"
    case .error: return "xmark.octagon"
    case .running: return "waveform.path.ecg"
    }
  }
}

@MainActor
final class CleanupViewModel: ObservableObject {
  @Published var host = "github.com" {
    didSet {
      if host != oldValue {
        reloadAccountChoices()
        refreshAuthStatus()
        if host != oldValue {
          safetyArmEnabled = false
        }
      }
    }
  }
  @Published var account = ""
  @Published var repoTarget = "" {
    didSet {
      if repoTarget != oldValue {
        safetyArmEnabled = false
      }
    }
  }
  @Published var fullCleanup = true
  @Published var disableWorkflows = true
  @Published var deleteRuns = true
  @Published var deleteArtifacts = true
  @Published var deleteCaches = true
  @Published var dryRun = false
  @Published var runTarget = ""
  @Published var runFilter = ""
  @Published var safetyArmEnabled = false

  @Published var availableHosts: [String] = []
  @Published var availableAccounts: [String] = []
  @Published var logText = "W.T.L. GUI ready.\n"
  @Published var statusTitle = "Checking GitHub CLI"
  @Published var statusDetail = "Loading local GitHub configuration."
  @Published var statusKind: StatusKind = .running
  @Published var isRunning = false
  @Published var isAuthenticated = false
  @Published var isLoggingOut = false

  private var hostConfigs: [AuthHostConfig] = []
  private var runningProcess: Process?
  private let processQueue = DispatchQueue(label: "com.waynetechlab.ghworkflowclean.process", qos: .userInitiated)

  init() {
    bootstrap()
  }

  var cliPath: String? {
    if let bundled = Bundle.main.resourceURL?.appendingPathComponent("gh-actions-cleanup").path,
       FileManager.default.isExecutableFile(atPath: bundled) {
      return bundled
    }

    for base in defaultSearchPaths {
      let candidate = (base as NSString).appendingPathComponent("gh-actions-cleanup")
      if FileManager.default.isExecutableFile(atPath: candidate) {
        return candidate
      }
    }

    return nil
  }

  var ghPath: String? {
    for base in defaultSearchPaths {
      let candidate = (base as NSString).appendingPathComponent("gh")
      if FileManager.default.isExecutableFile(atPath: candidate) {
        return candidate
      }
    }

    return nil
  }

  var bundledIcon: NSImage? {
    guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") else {
      return NSWorkspace.shared.icon(for: .application)
    }
    return NSImage(contentsOf: iconURL)
  }

  var canRunCleanup: Bool {
    !isRunning &&
      cliPath != nil &&
      ghPath != nil &&
      isAuthenticated &&
      !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !repoTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      (fullCleanup || disableWorkflows || deleteRuns || deleteArtifacts || deleteCaches) &&
      safetyArmEnabled &&
      statusKind != .error
  }

  var selectedHostConfig: AuthHostConfig? {
    hostConfigs.first(where: { $0.host == host.trimmingCharacters(in: .whitespacesAndNewlines) })
  }

  var authHeadline: String {
    let selectedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "github.com" : host.trimmingCharacters(in: .whitespacesAndNewlines)
    if isAuthenticated {
      return "GH TOKEN LOGGED IN @ \(selectedHost)"
    }
    return "GH TOKEN NOT LOGGED IN @ \(selectedHost)"
  }

  var authSummary: String {
    let resolvedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
    if isAuthenticated && !resolvedAccount.isEmpty {
      return "User \(resolvedAccount) on account \(resolvedAccount) ready."
    }
    return "No authenticated GitHub account is ready for cleanup."
  }

  var authActionHint: String {
    if isAuthenticated {
      return "Selected account is ready. You can refresh, log out, or continue to repository cleanup."
    }
    return "Log in with GitHub CLI first, then select the account you want to use."
  }

  var lastSessionSummary: String? {
    let session = loadLastSession()
    guard !session.isEmpty else { return nil }

    let hostValue = session["HOST"] ?? "github.com"
    let accountValue = session["ACCOUNT"] ?? "unknown"
    let repoValue = session["REPO"]?.replacingOccurrences(of: "\(hostValue)/", with: "") ?? "not set"
    return "Last session: \(accountValue) on \(hostValue) -> \(repoValue)"
  }

  func bootstrap() {
    let session = loadLastSession()
    if let savedHost = session["HOST"], !savedHost.isEmpty {
      host = savedHost
    }
    if let savedAccount = session["ACCOUNT"], !savedAccount.isEmpty {
      account = savedAccount
    }
    if let savedRepo = session["REPO"], !savedRepo.isEmpty {
      if savedRepo.hasPrefix("\(host)/") {
        repoTarget = String(savedRepo.dropFirst(host.count + 1))
      } else {
        repoTarget = savedRepo
      }
    }

    reloadAuthInventory()
    refreshAuthStatus()
  }

  func reloadAuthInventory() {
    hostConfigs = parseGitHubConfig()
    availableHosts = hostConfigs.map(\.host)

    if !availableHosts.isEmpty {
      if availableHosts.contains(host) == false {
        host = availableHosts.first ?? "github.com"
      }
    } else if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      host = "github.com"
    }

    reloadAccountChoices()
  }

  func reloadAccountChoices() {
    let currentHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
    let hostConfig = hostConfigs.first(where: { $0.host == currentHost })
    var accounts = hostConfig?.users ?? []

    if accounts.isEmpty, let activeUser = hostConfig?.activeUser, !activeUser.isEmpty {
      accounts = [activeUser]
    }

    availableAccounts = accounts

    if let existing = hostConfig?.users.first(where: { $0 == account }) {
      account = existing
      return
    }

    if let lastAccount = loadLastSession()["ACCOUNT"], accounts.contains(lastAccount) {
      account = lastAccount
    } else if let active = hostConfig?.activeUser, !active.isEmpty {
      account = active
    } else if let first = accounts.first {
      account = first
    } else if currentHost != host {
      account = ""
    } else if availableAccounts.isEmpty {
      account = ""
    }
  }

  func refreshAuthStatus() {
    guard let ghPath else {
      isAuthenticated = false
      statusKind = .error
      statusTitle = "GitHub CLI Missing"
      statusDetail = "Install GitHub CLI first. The GUI and CLI both depend on gh."
      return
    }

    let selectedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !selectedHost.isEmpty else {
      isAuthenticated = false
      statusKind = .warning
      statusTitle = "GitHub Host Required"
      statusDetail = "Enter a GitHub host, then refresh login status."
      return
    }

    statusKind = .running
    statusTitle = "Checking Login Status"
    statusDetail = "Validating GitHub CLI authentication for \(selectedHost)."

    let environment = baseEnvironment()
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }
      let result = Self.runCommand(
        executable: ghPath,
        arguments: ["auth", "status", "--hostname", selectedHost],
        environment: environment
      )

      DispatchQueue.main.async {
        self.reloadAuthInventory()
        let cleaned = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAccount = self.account.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.status == 0 {
          self.isAuthenticated = !resolvedAccount.isEmpty || self.selectedHostConfig?.activeUser != nil
          self.statusKind = .ready
          self.statusTitle = "GH TOKEN LOGGED IN @ \(selectedHost)"
          self.statusDetail = cleaned.isEmpty
            ? "User \(resolvedAccount.isEmpty ? (self.selectedHostConfig?.activeUser ?? "Unknown") : resolvedAccount) on account \(resolvedAccount.isEmpty ? (self.selectedHostConfig?.activeUser ?? "Unknown") : resolvedAccount) ready."
            : "User \(resolvedAccount.isEmpty ? (self.selectedHostConfig?.activeUser ?? "Unknown") : resolvedAccount) on account \(resolvedAccount.isEmpty ? (self.selectedHostConfig?.activeUser ?? "Unknown") : resolvedAccount) ready.\n\(cleaned)"
        } else {
          self.isAuthenticated = false
          self.statusKind = .warning
          self.statusTitle = "GH TOKEN NOT LOGGED IN @ \(selectedHost)"
          self.statusDetail = cleaned.isEmpty
            ? "Run gh auth login -h \(selectedHost) before cleanup."
            : cleaned
        }
      }
    }
  }

  func openGitHubLogin() {
    guard let ghPath else {
      appendLog("[gui] GitHub CLI was not found.\n")
      statusKind = .error
      statusTitle = "GitHub CLI Missing"
      statusDetail = "Install GitHub CLI first, then try login again."
      return
    }

    let selectedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
    let command = [
      "export PATH=\(shellQuote(defaultSearchPaths.joined(separator: ":")))",
      "\(shellQuote(ghPath)) auth login -h \(shellQuote(selectedHost.isEmpty ? "github.com" : selectedHost))",
      "EXIT_CODE=$?",
      "printf '\\n'",
      "if [ $EXIT_CODE -eq 0 ]; then echo 'GitHub login finished.'; else echo \"GitHub login exited with code $EXIT_CODE.\"; fi",
      "echo",
      "read -r -p 'Press Enter to close this window...' _"
    ].joined(separator: "; ")

    openTerminalCommand(command)
  }

  func openCLIInTerminal() {
    guard let cliPath else {
      appendLog("[gui] Bundled CLI was not found.\n")
      return
    }

    let command = [
      "export PATH=\(shellQuote(defaultSearchPaths.joined(separator: ":")))",
      "\(shellQuote(cliPath))",
      "EXIT_CODE=$?",
      "printf '\\n'",
      "if [ $EXIT_CODE -eq 0 ]; then echo 'GH Workflow Clean finished.'; else echo \"GH Workflow Clean exited with code $EXIT_CODE.\"; fi",
      "echo",
      "read -r -p 'Press Enter to close this window...' _"
    ].joined(separator: "; ")

    openTerminalCommand(command)
  }

  func cancelRun() {
    runningProcess?.terminate()
  }

  func logoutSelectedAccount() {
    guard let ghPath else {
      statusKind = .error
      statusTitle = "GitHub CLI Missing"
      statusDetail = "Install GitHub CLI first."
      return
    }

    let selectedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
    let selectedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !selectedHost.isEmpty, !selectedAccount.isEmpty else {
      statusKind = .warning
      statusTitle = "No Account Selected"
      statusDetail = "Choose an authenticated account before logging out."
      return
    }

    isLoggingOut = true
    appendLog("[gui] Logging out \(selectedAccount) on \(selectedHost)\n")

    let environment = baseEnvironment()
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }
      let result = Self.runCommand(
        executable: ghPath,
        arguments: ["auth", "logout", "--hostname", selectedHost, "--user", selectedAccount],
        environment: environment,
        stdin: "y\n"
      )

      DispatchQueue.main.async {
        self.isLoggingOut = false
        let cleaned = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
          self.appendLog(cleaned + "\n")
        }
        self.safetyArmEnabled = false
        self.reloadAuthInventory()
        self.refreshAuthStatus()
      }
    }
  }

  func runCleanup() {
    guard let cliPath else {
      statusKind = .error
      statusTitle = "CLI Engine Missing"
      statusDetail = "The bundled gh-actions-cleanup script was not found."
      return
    }

    guard ghPath != nil else {
      statusKind = .error
      statusTitle = "GitHub CLI Missing"
      statusDetail = "Install GitHub CLI first."
      return
    }

    let resolvedHost = repoHostOverride(from: repoTarget) ?? host.trimmingCharacters(in: .whitespacesAndNewlines)
    if resolvedHost != host, !resolvedHost.isEmpty {
      host = resolvedHost
      reloadAuthInventory()
    }

    let selectedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
    let selectedRepo = repoTarget.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !resolvedHost.isEmpty else {
      statusKind = .error
      statusTitle = "GitHub Host Required"
      statusDetail = "Select or enter a GitHub host before running cleanup."
      return
    }

    guard !selectedAccount.isEmpty else {
      statusKind = .warning
      statusTitle = "GitHub Account Required"
      statusDetail = "Login first, then choose which authenticated account should run cleanup."
      return
    }

    guard !selectedRepo.isEmpty else {
      statusKind = .warning
      statusTitle = "Repository Required"
      statusDetail = "Enter OWNER/REPO, HOST/OWNER/REPO, or a full GitHub repo URL."
      return
    }

    if !fullCleanup && !(disableWorkflows || deleteRuns || deleteArtifacts || deleteCaches) {
      statusKind = .warning
      statusTitle = "Cleanup Action Required"
      statusDetail = "Choose at least one cleanup action or enable full cleanup."
      return
    }

    guard safetyArmEnabled else {
      statusKind = .warning
      statusTitle = "Safety Lock Enabled"
      statusDetail = "Turn on the permanent delete confirmation switch before running cleanup."
      return
    }

    statusKind = .running
    statusTitle = dryRun ? "Running Dry Run" : "Running Cleanup"
    statusDetail = "\(selectedAccount) -> \(selectedRepo)"
    logText = "[gui] Starting cleanup for \(selectedRepo) on \(resolvedHost) with \(selectedAccount)\n"

    var arguments = [
      "--host", resolvedHost,
      "--account", selectedAccount,
      "--repo", selectedRepo,
      "--yes"
    ]

    if fullCleanup {
      arguments.append("--all")
    } else {
      if disableWorkflows { arguments.append("--disable-workflows") }
      if deleteRuns { arguments.append("--delete-runs") }
      if deleteArtifacts { arguments.append("--delete-artifacts") }
      if deleteCaches { arguments.append("--delete-caches") }
    }

    if !runTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      arguments.append(contentsOf: ["--run", runTarget.trimmingCharacters(in: .whitespacesAndNewlines)])
    }

    if !runFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      arguments.append(contentsOf: ["--run-filter", runFilter.trimmingCharacters(in: .whitespacesAndNewlines)])
    }

    if dryRun {
      arguments.append("--dry-run")
    }

    isRunning = true
    let environment = baseEnvironment()
    let pipe = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: cliPath)
    process.arguments = arguments
    process.environment = environment
    process.standardOutput = pipe
    process.standardError = pipe
    runningProcess = process

    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard data.isEmpty == false,
            let chunk = String(data: data, encoding: .utf8),
            chunk.isEmpty == false else {
        return
      }

      DispatchQueue.main.async {
        self?.appendLog(chunk)
      }
    }

    process.terminationHandler = { [weak self] terminated in
      let tail = pipe.fileHandleForReading.readDataToEndOfFile()
      pipe.fileHandleForReading.readabilityHandler = nil
      let tailText = String(data: tail, encoding: .utf8) ?? ""

      DispatchQueue.main.async {
        guard let self else { return }
        if !tailText.isEmpty {
          self.appendLog(tailText)
        }
        self.isRunning = false
        self.runningProcess = nil

        if terminated.terminationStatus == 0 {
          self.safetyArmEnabled = false
          self.statusKind = .ready
          self.statusTitle = self.dryRun ? "Dry Run Finished" : "Cleanup Finished"
          self.statusDetail = "The CLI completed successfully."
          self.reloadAuthInventory()
        } else {
          self.safetyArmEnabled = false
          self.statusKind = .error
          self.statusTitle = "Cleanup Failed"
          self.statusDetail = "The CLI exited with code \(terminated.terminationStatus). Review the log output."
        }
      }
    }

    processQueue.async {
      do {
        try process.run()
      } catch {
        DispatchQueue.main.async {
          self.isRunning = false
          self.runningProcess = nil
          self.statusKind = .error
          self.statusTitle = "Failed to Launch Cleanup"
          self.statusDetail = error.localizedDescription
          self.appendLog("[gui] Failed to launch cleanup: \(error.localizedDescription)\n")
        }
      }
    }
  }

  private func appendLog(_ text: String) {
    logText += text
  }

  private func loadLastSession() -> [String: String] {
    guard let contents = try? String(contentsOfFile: lastSessionFile, encoding: .utf8) else {
      return [:]
    }

    var values: [String: String] = [:]
    for line in contents.split(separator: "\n") {
      let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
      if parts.count == 2 {
        values[parts[0]] = parts[1]
      }
    }
    return values
  }

  private func parseGitHubConfig() -> [AuthHostConfig] {
    let configHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
      ?? (NSString(string: "~/.config").expandingTildeInPath)
    let hostsPath = (configHome as NSString).appendingPathComponent("gh/hosts.yml")

    guard let contents = try? String(contentsOfFile: hostsPath, encoding: .utf8) else {
      return []
    }

    var configs: [AuthHostConfig] = []
    var currentHost: String?
    var activeUser: String?
    var users: [String] = []
    var inUsers = false

    func flushCurrent() {
      guard let currentHost else { return }
      let uniqueUsers = Array(NSOrderedSet(array: users)) as? [String] ?? users
      configs.append(AuthHostConfig(host: currentHost, activeUser: activeUser, users: uniqueUsers))
    }

    for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(rawLine)

      if line.hasPrefix(" ") == false, line.hasSuffix(":") {
        flushCurrent()
        currentHost = String(line.dropLast())
        activeUser = nil
        users = []
        inUsers = false
        continue
      }

      if line.hasPrefix("    user: ") {
        activeUser = String(line.dropFirst("    user: ".count))
        continue
      }

      if line == "    users:" {
        inUsers = true
        continue
      }

      if inUsers, line.hasPrefix("        "), line.hasSuffix(":") {
        var user = String(line.dropFirst(8))
        user.removeLast()
        users.append(user)
        continue
      }

      if line.hasPrefix("    "), line != "    users:" {
        inUsers = false
      }
    }

    flushCurrent()
    return configs
  }

  private func repoHostOverride(from target: String) -> String? {
    let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else {
      return nil
    }

    if let url = URL(string: trimmed),
       let host = url.host,
       url.pathComponents.count >= 3 {
      return host
    }

    let components = trimmed.split(separator: "/")
    if components.count == 3 {
      return String(components[0])
    }

    return nil
  }

  private func baseEnvironment() -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = defaultSearchPaths.joined(separator: ":")
    return environment
  }

  private func openTerminalCommand(_ command: String) {
    let appleScript = """
    tell application "Terminal"
      activate
      do script \(quotedAppleScript(commandLine: "/bin/bash -lc " + shellQuote(command)))
    end tell
    """

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", appleScript]
    process.environment = baseEnvironment()

    do {
      try process.run()
    } catch {
      appendLog("[gui] Failed to open Terminal command: \(error.localizedDescription)\n")
    }
  }

  private nonisolated static func runCommand(executable: String, arguments: [String], environment: [String: String], stdin: String? = nil) -> CommandResult {
    let process = Process()
    let pipe = Pipe()
    let stdinPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = environment
    process.standardOutput = pipe
    process.standardError = pipe
    process.standardInput = stdinPipe

    do {
      try process.run()
    } catch {
      return CommandResult(status: 1, output: error.localizedDescription)
    }

    if let stdin {
      if let data = stdin.data(using: .utf8) {
        stdinPipe.fileHandleForWriting.write(data)
      }
    }
    stdinPipe.fileHandleForWriting.closeFile()

    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return CommandResult(status: process.terminationStatus, output: output)
  }
}

private func shellQuote(_ value: String) -> String {
  "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}

private func quotedAppleScript(commandLine: String) -> String {
  let escaped = commandLine
    .replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")
  return "\"\(escaped)\""
}

private enum DashboardTheme {
  static let canvasTop = Color(red: 0.03, green: 0.05, blue: 0.09)
  static let canvasBottom = Color(red: 0.06, green: 0.09, blue: 0.14)
  static let panel = Color(red: 0.07, green: 0.10, blue: 0.15)
  static let panelAlt = Color(red: 0.09, green: 0.13, blue: 0.19)
  static let panelStrong = Color(red: 0.05, green: 0.08, blue: 0.12)
  static let field = Color(red: 0.10, green: 0.14, blue: 0.20)
  static let border = Color.white.opacity(0.10)
  static let text = Color(red: 0.95, green: 0.97, blue: 0.99)
  static let muted = Color(red: 0.72, green: 0.78, blue: 0.86)
  static let subtle = Color(red: 0.53, green: 0.60, blue: 0.69)
  static let accent = Color(red: 0.29, green: 0.78, blue: 1.0)
  static let success = Color(red: 0.18, green: 0.82, blue: 0.54)
  static let warning = Color(red: 0.98, green: 0.73, blue: 0.23)
  static let danger = Color(red: 0.94, green: 0.33, blue: 0.28)
  static let cautionPanel = Color(red: 0.24, green: 0.15, blue: 0.08)
}

private extension View {
  func dashboardFieldStyle() -> some View {
    self
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(DashboardTheme.field)
          .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .stroke(DashboardTheme.border, lineWidth: 1)
          )
      )
  }
}

struct PanelCard<Content: View>: View {
  let title: String
  let subtitle: String
  let compact: Bool
  @ViewBuilder let content: Content

  init(title: String, subtitle: String, compact: Bool = false, @ViewBuilder content: () -> Content) {
    self.title = title
    self.subtitle = subtitle
    self.compact = compact
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 14 : 18) {
      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.system(size: compact ? 16 : 18, weight: .bold, design: .rounded))
          .foregroundStyle(DashboardTheme.text)
        Text(subtitle)
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .foregroundStyle(DashboardTheme.muted)
          .lineSpacing(2)
      }

      content
    }
    .padding(compact ? 18 : 22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(DashboardTheme.panel)
        .overlay(
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(DashboardTheme.border, lineWidth: 1)
        )
    )
  }
}

struct PillBadge: View {
  let text: String
  let tint: Color

  var body: some View {
    Text(text)
      .font(.system(size: 11, weight: .semibold, design: .rounded))
      .foregroundStyle(DashboardTheme.text)
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .background(tint.opacity(0.22))
      .overlay(
        Capsule()
          .stroke(tint.opacity(0.45), lineWidth: 1)
      )
      .clipShape(Capsule())
  }
}

struct BannerCard: View {
  let title: String
  let detail: String
  let kind: StatusKind

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: kind.icon)
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(DashboardTheme.text)
        .frame(width: 36, height: 36)
        .background(kind.tint.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.system(size: 17, weight: .bold, design: .rounded))
          .foregroundStyle(DashboardTheme.text)
        Text(detail)
          .font(.system(size: 13, weight: .medium, design: .rounded))
          .foregroundStyle(DashboardTheme.muted)
          .lineSpacing(3)
      }

      Spacer(minLength: 0)
    }
    .padding(18)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(kind.tint.opacity(0.12))
        .overlay(
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(kind.tint.opacity(0.34), lineWidth: 1)
        )
    )
  }
}

struct HeaderPanel: View {
  let icon: NSImage?
  let lastSessionSummary: String?
  let statusTitle: String
  let statusKind: StatusKind

  var body: some View {
    HStack(alignment: .center, spacing: 22) {
      if let icon {
        Image(nsImage: icon)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 92, height: 92)
          .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
      }

      VStack(alignment: .leading, spacing: 10) {
        Text("W.T.L.")
          .font(.system(size: 14, weight: .semibold, design: .rounded))
          .tracking(2.4)
          .foregroundStyle(DashboardTheme.accent)

        Text(appTitle)
          .font(.system(size: 34, weight: .bold, design: .rounded))
          .foregroundStyle(DashboardTheme.text)

        Text("Native macOS SwiftUI control panel for GitHub Actions cleanup.")
          .font(.system(size: 14, weight: .medium, design: .rounded))
          .foregroundStyle(DashboardTheme.muted)
      }

      Spacer(minLength: 20)

      VStack(alignment: .trailing, spacing: 12) {
        HStack(spacing: 10) {
          PillBadge(text: "Native SwiftUI", tint: DashboardTheme.accent)
          PillBadge(text: "CLI Engine", tint: DashboardTheme.success)
          PillBadge(text: "Version 0.0.4", tint: DashboardTheme.warning)
        }

        Text(statusTitle)
          .font(.system(size: 13, weight: .bold, design: .rounded))
          .foregroundStyle(statusKind.tint)

        if let lastSessionSummary {
          Text(lastSessionSummary)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(DashboardTheme.subtle)
        }
      }
    }
    .padding(24)
    .background(
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .fill(
          LinearGradient(
            colors: [DashboardTheme.panelStrong, DashboardTheme.panelAlt],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .overlay(
          RoundedRectangle(cornerRadius: 28, style: .continuous)
            .stroke(DashboardTheme.border, lineWidth: 1)
        )
    )
  }
}

struct FieldLabel: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(size: 12, weight: .semibold, design: .rounded))
      .foregroundStyle(DashboardTheme.muted)
  }
}

struct FixedValueRow: View {
  let label: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      FieldLabel(text: label)

      Text(value)
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .foregroundStyle(DashboardTheme.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardFieldStyle()
    }
  }
}

struct DashboardButtonStyle: ButtonStyle {
  let tint: Color
  let bordered: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .bold, design: .rounded))
      .foregroundStyle(bordered ? DashboardTheme.text : DashboardTheme.panelStrong)
      .padding(.horizontal, 16)
      .padding(.vertical, 11)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(bordered ? tint.opacity(configuration.isPressed ? 0.55 : 0.82) : tint.opacity(configuration.isPressed ? 0.70 : 1.0))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(bordered ? tint.opacity(0.45) : tint.opacity(0.90), lineWidth: 1)
      )
      .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
  }
}

struct SafetyCard: View {
  @Binding var isArmed: Bool
  let dryRun: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 20, weight: .bold))
          .foregroundStyle(DashboardTheme.text)
          .frame(width: 40, height: 40)
          .background(DashboardTheme.danger)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        VStack(alignment: .leading, spacing: 6) {
          Text("Warning: Permanent Delete")
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(DashboardTheme.text)

          Text(dryRun ? "Dry run is enabled, but this app is built for destructive cleanup. Confirm the repo and account before you continue." : "This will permanently delete GitHub Actions data. Workflow runs, artifacts, caches, and disabled workflows cannot be restored.")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(DashboardTheme.muted)
            .lineSpacing(3)
        }
      }

      Toggle(isOn: $isArmed) {
        Text("Arm destructive cleanup")
          .font(.system(size: 14, weight: .bold, design: .rounded))
          .foregroundStyle(DashboardTheme.text)
      }
      .toggleStyle(.switch)
      .tint(DashboardTheme.danger)

      Text(isArmed ? "Safety lock is OFF. Cleanup buttons are unlocked." : "Safety lock is ON. Turn this switch on before cleanup can run.")
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(isArmed ? DashboardTheme.success : DashboardTheme.warning)
    }
    .padding(20)
    .background(
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(DashboardTheme.cautionPanel)
        .overlay(
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(DashboardTheme.danger.opacity(0.45), lineWidth: 1)
        )
    )
  }
}

struct LogConsoleView: NSViewRepresentable {
  let text: String

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder

    let textView = NSTextView()
    textView.isEditable = false
    textView.isSelectable = true
    textView.drawsBackground = true
    textView.backgroundColor = NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.13, alpha: 1)
    textView.textColor = NSColor(calibratedRed: 0.94, green: 0.97, blue: 0.99, alpha: 1)
    textView.insertionPointColor = .clear
    textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    textView.textContainerInset = NSSize(width: 12, height: 12)
    textView.isRichText = false
    textView.string = text

    scrollView.documentView = textView
    return scrollView
  }

  func updateNSView(_ nsView: NSScrollView, context: Context) {
    guard let textView = nsView.documentView as? NSTextView else { return }
    textView.string = text
    textView.backgroundColor = NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.13, alpha: 1)
    textView.textColor = NSColor(calibratedRed: 0.94, green: 0.97, blue: 0.99, alpha: 1)
    textView.scrollToEndOfDocument(nil)
  }
}

struct ContentView: View {
  @StateObject private var model = CleanupViewModel()

  private var actionToggleTint: Color { DashboardTheme.accent }

  var body: some View {
    GeometryReader { geometry in
      let leftWidth = max(330.0, min(380.0, geometry.size.width * 0.28))
      let middleWidth = max(360.0, min(430.0, geometry.size.width * 0.31))

      ZStack {
        LinearGradient(
          colors: [DashboardTheme.canvasTop, DashboardTheme.canvasBottom],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack(spacing: 18) {
          HeaderPanel(
            icon: model.bundledIcon,
            lastSessionSummary: model.lastSessionSummary,
            statusTitle: model.statusTitle,
            statusKind: model.statusKind
          )

          HStack(alignment: .top, spacing: 18) {
            leftRail
              .frame(width: leftWidth)

            middleRail
              .frame(width: middleWidth)

            rightRail
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
          .frame(maxHeight: .infinity)
        }
        .padding(20)
      }
    }
    .frame(minWidth: 1380, minHeight: 880)
    .preferredColorScheme(.dark)
  }

  private var leftRail: some View {
    VStack(alignment: .leading, spacing: 18) {
      PanelCard(title: "GitHub Auth", subtitle: "Clear account state, login controls, and fixed-value handling.") {
        BannerCard(
          title: model.authHeadline,
          detail: "\(model.authSummary)\n\(model.authActionHint)",
          kind: model.isAuthenticated ? .ready : .warning
        )

        if model.availableHosts.count > 1 {
          VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: "Detected GitHub Hosts")
            Picker("", selection: $model.host) {
              ForEach(model.availableHosts, id: \.self) { host in
                Text(host).tag(host)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .foregroundStyle(DashboardTheme.text)
            .dashboardFieldStyle()
          }
        } else if let onlyHost = model.availableHosts.first {
          FixedValueRow(label: "Detected GitHub Host", value: onlyHost)
        }

        VStack(alignment: .leading, spacing: 6) {
          FieldLabel(text: "GitHub Host")
          TextField("github.com", text: $model.host)
            .textFieldStyle(.plain)
            .foregroundStyle(DashboardTheme.text)
            .dashboardFieldStyle()
        }

        if model.availableAccounts.count > 1 {
          VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: "Authenticated Account")
            Picker("", selection: $model.account) {
              ForEach(model.availableAccounts, id: \.self) { account in
                Text(account).tag(account)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .foregroundStyle(DashboardTheme.text)
            .dashboardFieldStyle()
          }
        } else if let onlyAccount = model.availableAccounts.first {
          FixedValueRow(label: "Authenticated Account", value: onlyAccount)
        } else {
          FixedValueRow(label: "Authenticated Account", value: "No logged-in account found for this host")
        }

        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 10) {
            Button("Refresh") {
              model.refreshAuthStatus()
            }
            .buttonStyle(DashboardButtonStyle(tint: DashboardTheme.accent, bordered: true))

            Button(model.isAuthenticated ? "Re-Login" : "Login") {
              model.openGitHubLogin()
            }
            .buttonStyle(DashboardButtonStyle(tint: DashboardTheme.success, bordered: false))
          }

          Button("Logout Selected Account") {
            model.logoutSelectedAccount()
          }
          .buttonStyle(DashboardButtonStyle(tint: DashboardTheme.warning, bordered: true))
          .disabled(!model.isAuthenticated || model.isLoggingOut || model.account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }

      PanelCard(title: "Repository Target", subtitle: "Paste OWNER/REPO, HOST/OWNER/REPO, or a full GitHub repo URL.") {
        VStack(alignment: .leading, spacing: 6) {
          FieldLabel(text: "Repository or URL")
          TextField("OWNER/REPO or https://github.com/OWNER/REPO", text: $model.repoTarget)
            .textFieldStyle(.plain)
            .foregroundStyle(DashboardTheme.text)
            .dashboardFieldStyle()
        }

        Text("The GUI passes this directly to the CLI engine. Repo URLs and custom GitHub hosts are supported.")
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .foregroundStyle(DashboardTheme.muted)
          .lineSpacing(2)
      }

      Spacer(minLength: 0)
    }
  }

  private var middleRail: some View {
    VStack(alignment: .leading, spacing: 18) {
      PanelCard(title: "Cleanup Scope", subtitle: "Single control panel for actions, filters, and destructive state.") {
        Toggle("Full cleanup", isOn: $model.fullCleanup)
          .toggleStyle(.switch)
          .tint(actionToggleTint)
          .foregroundStyle(DashboardTheme.text)

        Divider().overlay(DashboardTheme.border)

        Toggle("Disable workflows", isOn: $model.disableWorkflows)
          .toggleStyle(.switch)
          .tint(actionToggleTint)
          .foregroundStyle(DashboardTheme.text)
          .disabled(model.fullCleanup)

        Toggle("Delete workflow runs", isOn: $model.deleteRuns)
          .toggleStyle(.switch)
          .tint(actionToggleTint)
          .foregroundStyle(DashboardTheme.text)
          .disabled(model.fullCleanup)

        Toggle("Delete artifacts", isOn: $model.deleteArtifacts)
          .toggleStyle(.switch)
          .tint(actionToggleTint)
          .foregroundStyle(DashboardTheme.text)
          .disabled(model.fullCleanup)

        Toggle("Delete caches", isOn: $model.deleteCaches)
          .toggleStyle(.switch)
          .tint(actionToggleTint)
          .foregroundStyle(DashboardTheme.text)
          .disabled(model.fullCleanup)

        Divider().overlay(DashboardTheme.border)

        Toggle("Dry run only", isOn: $model.dryRun)
          .toggleStyle(.switch)
          .tint(DashboardTheme.warning)
          .foregroundStyle(DashboardTheme.text)

        VStack(alignment: .leading, spacing: 6) {
          FieldLabel(text: "Specific Run ID or Run URL")
          TextField("Optional exact run target", text: $model.runTarget)
            .textFieldStyle(.plain)
            .foregroundStyle(DashboardTheme.text)
            .dashboardFieldStyle()
        }

        VStack(alignment: .leading, spacing: 6) {
          FieldLabel(text: "Run Filter")
          TextField("Optional run name filter", text: $model.runFilter)
            .textFieldStyle(.plain)
            .foregroundStyle(DashboardTheme.text)
            .dashboardFieldStyle()
        }
      }

      SafetyCard(isArmed: $model.safetyArmEnabled, dryRun: model.dryRun)

      PanelCard(title: "Execution", subtitle: "The native app runs the bundled CLI engine and keeps the raw terminal fallback available.", compact: true) {
        HStack(spacing: 10) {
          Button(model.dryRun ? "Preview Cleanup" : "Execute Cleanup") {
            model.runCleanup()
          }
          .buttonStyle(DashboardButtonStyle(tint: DashboardTheme.danger, bordered: false))
          .disabled(!model.canRunCleanup)

          Button("Open CLI") {
            model.openCLIInTerminal()
          }
          .buttonStyle(DashboardButtonStyle(tint: DashboardTheme.accent, bordered: true))

          Button("Clear Log") {
            model.logText = "W.T.L. GUI ready.\n"
          }
          .buttonStyle(DashboardButtonStyle(tint: DashboardTheme.success, bordered: true))
        }

        if model.isRunning {
          Button("Cancel Active Run") {
            model.cancelRun()
          }
          .buttonStyle(DashboardButtonStyle(tint: DashboardTheme.warning, bordered: true))
        }

        Text(model.safetyArmEnabled ? "Safety arm is ON. Cleanup is unlocked for the selected target." : "Safety arm is OFF. Turn on the destructive cleanup switch before execution.")
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .foregroundStyle(model.safetyArmEnabled ? DashboardTheme.success : DashboardTheme.warning)
      }

      Spacer(minLength: 0)
    }
  }

  private var rightRail: some View {
    PanelCard(title: "Live Output", subtitle: "Readable, high-contrast CLI output streamed into the native app.") {
      LogConsoleView(text: model.logText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(DashboardTheme.panelStrong)
            .overlay(
              RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DashboardTheme.border, lineWidth: 1)
            )
        )
    }
  }
}

@main
struct GHWorkflowCleanGUIApp: App {
  @NSApplicationDelegateAdaptor(GHWorkflowCleanAppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup(appTitle) {
      ContentView()
    }
    .commands {
      CommandGroup(replacing: .newItem) { }
    }
  }
}

final class GHWorkflowCleanAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)

    if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
       let iconImage = NSImage(contentsOf: iconURL) {
      NSApplication.shared.applicationIconImage = iconImage
    }
  }
}
