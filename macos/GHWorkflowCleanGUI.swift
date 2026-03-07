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
      }
    }
  }
  @Published var account = ""
  @Published var repoTarget = ""
  @Published var fullCleanup = true
  @Published var disableWorkflows = true
  @Published var deleteRuns = true
  @Published var deleteArtifacts = true
  @Published var deleteCaches = true
  @Published var dryRun = false
  @Published var runTarget = ""
  @Published var runFilter = ""

  @Published var availableHosts: [String] = []
  @Published var availableAccounts: [String] = []
  @Published var logText = "W.T.L. GUI ready.\n"
  @Published var statusTitle = "Checking GitHub CLI"
  @Published var statusDetail = "Loading local GitHub configuration."
  @Published var statusKind: StatusKind = .running
  @Published var isRunning = false

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
      !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !repoTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      (fullCleanup || disableWorkflows || deleteRuns || deleteArtifacts || deleteCaches) &&
      statusKind != .error
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
      statusKind = .error
      statusTitle = "GitHub CLI Missing"
      statusDetail = "Install GitHub CLI first. The GUI and CLI both depend on gh."
      return
    }

    let selectedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !selectedHost.isEmpty else {
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
        if result.status == 0 {
          self.statusKind = .ready
          self.statusTitle = "GitHub Login Ready"
          self.statusDetail = cleaned.isEmpty
            ? "Authenticated for \(selectedHost)."
            : cleaned
        } else {
          self.statusKind = .warning
          self.statusTitle = "Login Required"
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
          self.statusKind = .ready
          self.statusTitle = self.dryRun ? "Dry Run Finished" : "Cleanup Finished"
          self.statusDetail = "The CLI completed successfully."
          self.reloadAuthInventory()
        } else {
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

  private nonisolated static func runCommand(executable: String, arguments: [String], environment: [String: String]) -> CommandResult {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = environment
    process.standardOutput = pipe
    process.standardError = pipe

    do {
      try process.run()
    } catch {
      return CommandResult(status: 1, output: error.localizedDescription)
    }

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

struct HeroCard: View {
  let icon: NSImage?
  let lastSessionSummary: String?

  var body: some View {
    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .fill(
          LinearGradient(
            colors: [
              Color(red: 0.03, green: 0.08, blue: 0.16),
              Color(red: 0.04, green: 0.20, blue: 0.33)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .overlay(
          RoundedRectangle(cornerRadius: 28, style: .continuous)
            .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )

      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .center, spacing: 16) {
          if let icon {
            Image(nsImage: icon)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 84, height: 84)
              .shadow(color: .black.opacity(0.18), radius: 16, y: 10)
          }

          VStack(alignment: .leading, spacing: 8) {
            Text("W.T.L.")
              .font(.system(size: 14, weight: .semibold, design: .rounded))
              .tracking(2.2)
              .foregroundStyle(Color(red: 0.52, green: 0.91, blue: 1.0))

            Text(appTitle)
              .font(.system(size: 34, weight: .bold, design: .rounded))
              .foregroundStyle(.white)

            Text("Native macOS control room for GitHub Actions cleanup.")
              .font(.system(size: 15, weight: .medium, design: .rounded))
              .foregroundStyle(Color.white.opacity(0.78))
          }
        }

        HStack(spacing: 10) {
          Badge(text: "Native GUI")
          Badge(text: "CLI Engine")
          Badge(text: "No Token Storage")
        }

        if let lastSessionSummary {
          Text(lastSessionSummary)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.72))
        }
      }
      .padding(28)
    }
    .frame(minHeight: 220)
  }
}

struct Badge: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(size: 12, weight: .semibold, design: .rounded))
      .foregroundStyle(Color.white)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(Color.white.opacity(0.12))
      .clipShape(Capsule())
  }
}

struct StatusCard: View {
  let title: String
  let detail: String
  let kind: StatusKind

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: kind.icon)
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(kind.tint)
        .frame(width: 30, height: 30)
        .background(kind.tint.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.system(size: 16, weight: .bold, design: .rounded))

        Text(detail)
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)
    }
    .padding(18)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(kind.tint.opacity(0.08))
        .overlay(
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(kind.tint.opacity(0.24), lineWidth: 1)
        )
    )
  }
}

struct SectionCard<Content: View>: View {
  let title: String
  let subtitle: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 18, weight: .bold, design: .rounded))
        Text(subtitle)
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .foregroundStyle(.secondary)
      }

      content
    }
    .padding(22)
    .background(
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(Color(nsColor: .windowBackgroundColor))
        .shadow(color: .black.opacity(0.05), radius: 18, y: 8)
    )
  }
}

struct ContentView: View {
  @StateObject private var model = CleanupViewModel()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HeroCard(icon: model.bundledIcon, lastSessionSummary: model.lastSessionSummary)
        StatusCard(title: model.statusTitle, detail: model.statusDetail, kind: model.statusKind)

        HStack(alignment: .top, spacing: 22) {
          VStack(alignment: .leading, spacing: 22) {
            SectionCard(title: "Connection", subtitle: "Select the GitHub host and authenticated account.") {
              VStack(alignment: .leading, spacing: 14) {
                Text("GitHub Host")
                  .font(.system(size: 12, weight: .semibold, design: .rounded))
                  .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                  Picker("Host", selection: $model.host) {
                    ForEach(model.availableHosts, id: \.self) { host in
                      Text(host).tag(host)
                    }
                    if model.availableHosts.contains(model.host) == false {
                      Text(model.host).tag(model.host)
                    }
                  }
                  .pickerStyle(.menu)
                  .frame(width: 220)

                  TextField("github.com", text: $model.host)
                    .textFieldStyle(.roundedBorder)
                }

                Text("Account")
                  .font(.system(size: 12, weight: .semibold, design: .rounded))
                  .foregroundStyle(.secondary)

                if model.availableAccounts.isEmpty {
                  TextField("Authenticated account", text: $model.account)
                    .textFieldStyle(.roundedBorder)
                } else {
                  Picker("Account", selection: $model.account) {
                    ForEach(model.availableAccounts, id: \.self) { account in
                      Text(account).tag(account)
                    }
                    if model.availableAccounts.contains(model.account) == false, !model.account.isEmpty {
                      Text(model.account).tag(model.account)
                    }
                  }
                  .pickerStyle(.menu)
                  .frame(width: 260)
                }

                HStack(spacing: 10) {
                  Button("Refresh Login Status") {
                    model.refreshAuthStatus()
                  }

                  Button("Login in Terminal") {
                    model.openGitHubLogin()
                  }
                }
              }
            }

            SectionCard(title: "Target", subtitle: "Enter OWNER/REPO, HOST/OWNER/REPO, or a full GitHub repo URL.") {
              TextField("OWNER/REPO or https://github.com/OWNER/REPO", text: $model.repoTarget)
                .textFieldStyle(.roundedBorder)

              if !model.repoTarget.isEmpty {
                Text("The GUI accepts a repo URL and will hand it to the CLI exactly as entered.")
                  .font(.system(size: 11, weight: .medium, design: .rounded))
                  .foregroundStyle(.secondary)
              }
            }

            SectionCard(title: "Actions", subtitle: "Choose one exact run, a filtered run series, or a full repository cleanup.") {
              VStack(alignment: .leading, spacing: 12) {
                Toggle("Full cleanup", isOn: $model.fullCleanup)
                  .toggleStyle(.switch)

                Toggle("Disable workflows", isOn: $model.disableWorkflows)
                  .disabled(model.fullCleanup)

                Toggle("Delete workflow runs", isOn: $model.deleteRuns)
                  .disabled(model.fullCleanup)

                Toggle("Delete artifacts", isOn: $model.deleteArtifacts)
                  .disabled(model.fullCleanup)

                Toggle("Delete caches", isOn: $model.deleteCaches)
                  .disabled(model.fullCleanup)

                Divider()

                Toggle("Dry run only", isOn: $model.dryRun)
                  .toggleStyle(.switch)

                TextField("Specific run ID or GitHub Actions run URL (optional)", text: $model.runTarget)
                  .textFieldStyle(.roundedBorder)

                TextField("Run filter text (optional)", text: $model.runFilter)
                  .textFieldStyle(.roundedBorder)
              }
            }
          }

          VStack(alignment: .leading, spacing: 22) {
            SectionCard(title: "Run", subtitle: "Launch the CLI engine from the GUI or open the raw terminal flow.") {
              VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                  Button(model.dryRun ? "Preview Cleanup" : "Run Cleanup") {
                    model.runCleanup()
                  }
                  .disabled(!model.canRunCleanup)

                  Button("Open CLI in Terminal") {
                    model.openCLIInTerminal()
                  }

                  if model.isRunning {
                    Button("Cancel") {
                      model.cancelRun()
                    }
                  }
                }

                Text("The GUI keeps `gh-actions-cleanup` as the execution engine, so CLI and GUI behavior stay aligned.")
                  .font(.system(size: 11, weight: .medium, design: .rounded))
                  .foregroundStyle(.secondary)
              }
            }

            SectionCard(title: "Output", subtitle: "Live CLI stdout and stderr.") {
              TextEditor(text: Binding(
                get: { model.logText },
                set: { _ in }
              ))
              .font(.system(size: 12, weight: .regular, design: .monospaced))
              .frame(minHeight: 380)
            }
          }
          .frame(minWidth: 420, maxWidth: .infinity)
        }
      }
      .padding(28)
    }
    .frame(minWidth: 1100, minHeight: 760)
    .background(
      LinearGradient(
        colors: [
          Color(red: 0.97, green: 0.98, blue: 1.0),
          Color(red: 0.92, green: 0.95, blue: 0.99)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()
    )
  }
}

@main
struct GHWorkflowCleanGUIApp: App {
  var body: some Scene {
    WindowGroup(appTitle) {
      ContentView()
    }
    .commands {
      CommandGroup(replacing: .newItem) { }
    }
  }
}
