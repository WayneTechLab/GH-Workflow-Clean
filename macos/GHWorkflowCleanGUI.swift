import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

private let appTitle = "GH Workflow Clean"
private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.8"
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

struct RepoCatalogEntry: Identifiable, Hashable, Decodable {
  let nameWithOwner: String
  let visibility: String?
  let isPrivate: Bool?
  let updatedAt: String?
  let url: String?

  var id: String { nameWithOwner }

  var shortName: String {
    nameWithOwner.split(separator: "/").last.map(String.init) ?? nameWithOwner
  }

  var owner: String {
    nameWithOwner.split(separator: "/").dropLast().first.map(String.init) ?? ""
  }

  var visibilityLabel: String {
    if let visibility, !visibility.isEmpty {
      return visibility.uppercased()
    }
    return isPrivate == true ? "PRIVATE" : "PUBLIC"
  }

  var updatedLabel: String {
    guard let updatedAt, updatedAt.count >= 10 else {
      return "Updated: unknown"
    }
    return "Updated: \(String(updatedAt.prefix(10)))"
  }
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
        isAuthenticated = false
        clearRepoCatalog(resetOwner: false)
        reloadAccountChoices()
        refreshAuthStatus()
        if host != oldValue {
          safetyArmEnabled = false
        }
      }
    }
  }
  @Published var account = "" {
    didSet {
      if account != oldValue {
        if repoOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || repoOwner == oldValue {
          repoOwner = account
        }
        clearRepoCatalog(resetOwner: false)
        if isAuthenticated && !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          fetchAvailableRepos()
        }
      }
    }
  }
  @Published var repoTarget = "" {
    didSet {
      if repoTarget != oldValue {
        safetyArmEnabled = false
      }
    }
  }
  @Published var repoOwner = "" {
    didSet {
      if repoOwner != oldValue {
        clearRepoCatalog(resetOwner: false)
      }
    }
  }
  @Published var repoSearch = ""
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
  @Published var availableRepos: [RepoCatalogEntry] = []
  @Published var selectedRepos: Set<String> = [] {
    didSet {
      if selectedRepos != oldValue {
        safetyArmEnabled = false
      }
    }
  }
  @Published var repoCatalogStatus = "Load repositories for the selected GitHub account or owner."
  @Published var logText = "W.T.L. GUI ready.\n"
  @Published var statusTitle = "Checking GitHub CLI"
  @Published var statusDetail = "Loading local GitHub configuration."
  @Published var statusKind: StatusKind = .running
  @Published var isRunning = false
  @Published var isAuthenticated = false
  @Published var isLoggingOut = false
  @Published var isLoadingRepos = false

  private var hostConfigs: [AuthHostConfig] = []
  private var runningProcess: Process?
  private var pendingRepoTargets: [String] = []
  private var completedRepoTargets: [String] = []
  private var failedRepoTargets: [String] = []
  private var activeRepoTarget = ""
  private var totalRepoTargets = 0
  private var cancellationRequested = false
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
      !cleanupTargets.isEmpty &&
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

  var filteredRepos: [RepoCatalogEntry] {
    let query = repoSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !query.isEmpty else {
      return availableRepos
    }

    return availableRepos.filter { repo in
      repo.nameWithOwner.lowercased().contains(query) ||
      repo.shortName.lowercased().contains(query) ||
      repo.owner.lowercased().contains(query) ||
      (repo.visibility?.lowercased().contains(query) ?? false)
    }
  }

  var cleanupTargets: [String] {
    if !selectedRepos.isEmpty {
      return selectedRepos.sorted()
    }

    let manualTarget = repoTarget.trimmingCharacters(in: .whitespacesAndNewlines)
    return manualTarget.isEmpty ? [] : [manualTarget]
  }

  var areAllLoadedReposSelected: Bool {
    !availableRepos.isEmpty && selectedRepos.count == availableRepos.count
  }

  var selectedRepoSummary: String {
    if !selectedRepos.isEmpty {
      if selectedRepos.count == 1, let only = selectedRepos.first {
        return "1 repository selected: \(only)"
      }
      return "\(selectedRepos.count) repositories selected"
    }

    let manualTarget = repoTarget.trimmingCharacters(in: .whitespacesAndNewlines)
    if !manualTarget.isEmpty {
      return "Manual target: \(manualTarget)"
    }

    return "No repository selected yet"
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
      let components = repoTarget.split(separator: "/")
      if components.count >= 2 {
        repoOwner = String(components[0])
      }
    }

    if repoOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      repoOwner = account
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

  func clearRepoCatalog(resetOwner: Bool) {
    availableRepos = []
    selectedRepos = []
    repoSearch = ""
    repoCatalogStatus = "Load repositories for the selected GitHub account or owner."

    if resetOwner {
      repoOwner = ""
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
          if self.repoOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.repoOwner = resolvedAccount.isEmpty ? (self.selectedHostConfig?.activeUser ?? "") : resolvedAccount
          }
          self.statusKind = .ready
          self.statusTitle = "GH TOKEN LOGGED IN @ \(selectedHost)"
          self.statusDetail = cleaned.isEmpty
            ? "User \(resolvedAccount.isEmpty ? (self.selectedHostConfig?.activeUser ?? "Unknown") : resolvedAccount) on account \(resolvedAccount.isEmpty ? (self.selectedHostConfig?.activeUser ?? "Unknown") : resolvedAccount) ready."
            : "User \(resolvedAccount.isEmpty ? (self.selectedHostConfig?.activeUser ?? "Unknown") : resolvedAccount) on account \(resolvedAccount.isEmpty ? (self.selectedHostConfig?.activeUser ?? "Unknown") : resolvedAccount) ready.\n\(cleaned)"
          self.fetchAvailableRepos()
        } else {
          self.isAuthenticated = false
          self.clearRepoCatalog(resetOwner: false)
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
    cancellationRequested = true
    pendingRepoTargets.removeAll()
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
        self.clearRepoCatalog(resetOwner: false)
        self.reloadAuthInventory()
        self.refreshAuthStatus()
      }
    }
  }

  func setAllLoadedReposSelected(_ enabled: Bool) {
    if enabled {
      selectedRepos = Set(availableRepos.map(\.nameWithOwner))
    } else {
      selectedRepos.removeAll()
    }
  }

  func toggleRepoSelection(_ repo: RepoCatalogEntry) {
    if selectedRepos.contains(repo.nameWithOwner) {
      selectedRepos.remove(repo.nameWithOwner)
    } else {
      selectedRepos.insert(repo.nameWithOwner)
    }
  }

  func fetchAvailableRepos() {
    guard let ghPath else {
      repoCatalogStatus = "GitHub CLI was not found."
      return
    }

    let selectedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
    let targetOwner = repoOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? account.trimmingCharacters(in: .whitespacesAndNewlines)
      : repoOwner.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !selectedHost.isEmpty else {
      repoCatalogStatus = "Enter a GitHub host first."
      return
    }

    guard isAuthenticated else {
      repoCatalogStatus = "Log into GitHub CLI first, then load repositories."
      return
    }

    guard !targetOwner.isEmpty else {
      repoCatalogStatus = "Enter an owner or org to list repositories."
      return
    }

    isLoadingRepos = true
    repoCatalogStatus = "Loading repositories for \(targetOwner) on \(selectedHost)..."
    appendLog("[gui] Loading repositories for \(targetOwner) on \(selectedHost)\n")

    var environment = baseEnvironment()
    environment["GH_HOST"] = selectedHost

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }
      let result = Self.runCommand(
        executable: ghPath,
        arguments: [
          "repo", "list", targetOwner,
          "--limit", "1000",
          "--json", "nameWithOwner,visibility,isPrivate,updatedAt,url"
        ],
        environment: environment
      )

      DispatchQueue.main.async {
        self.isLoadingRepos = false
        let cleaned = result.output.trimmingCharacters(in: .whitespacesAndNewlines)

        guard result.status == 0 else {
          self.availableRepos = []
          self.selectedRepos.removeAll()
          self.repoCatalogStatus = cleaned.isEmpty
            ? "Failed to load repositories for \(targetOwner)."
            : cleaned
          return
        }

        let data = Data(result.output.utf8)
        do {
          let decoded = try JSONDecoder().decode([RepoCatalogEntry].self, from: data)
          self.availableRepos = decoded.sorted { $0.nameWithOwner.localizedCaseInsensitiveCompare($1.nameWithOwner) == .orderedAscending }
          self.selectedRepos = self.selectedRepos.intersection(Set(self.availableRepos.map(\.nameWithOwner)))
          if self.availableRepos.isEmpty {
            self.repoCatalogStatus = "No repositories found for \(targetOwner) on \(selectedHost)."
          } else {
            self.repoCatalogStatus = "Loaded \(self.availableRepos.count) repositories for \(targetOwner)."
          }
        } catch {
          self.availableRepos = []
          self.selectedRepos.removeAll()
          self.repoCatalogStatus = "Failed to decode repository list: \(error.localizedDescription)"
        }
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

    let selectedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
    let selectedTargets = cleanupTargets

    guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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

    guard !selectedTargets.isEmpty else {
      statusKind = .warning
      statusTitle = "Repository Required"
      statusDetail = "Enter a manual repo target or check one or more repositories from the repo browser."
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

    pendingRepoTargets = selectedTargets
    completedRepoTargets = []
    failedRepoTargets = []
    activeRepoTarget = ""
    totalRepoTargets = selectedTargets.count
    cancellationRequested = false
    statusKind = .running
    statusTitle = dryRun ? "Running Dry Run" : "Running Cleanup"
    statusDetail = "\(selectedAccount) -> \(selectedTargets.count) target(s)"
    logText = "[gui] Starting cleanup across \(selectedTargets.count) target(s) with \(selectedAccount)\n"
    isRunning = true
    launchCleanup(for: pendingRepoTargets.removeFirst(), using: cliPath, account: selectedAccount)
  }

  private func launchCleanup(for repoTarget: String, using cliPath: String, account selectedAccount: String) {
    let resolvedHost = repoHostOverride(from: repoTarget) ?? host.trimmingCharacters(in: .whitespacesAndNewlines)
    activeRepoTarget = repoTarget
    let currentIndex = completedRepoTargets.count + failedRepoTargets.count + 1

    statusKind = .running
    statusTitle = dryRun ? "Running Dry Run" : "Running Cleanup"
    statusDetail = totalRepoTargets > 1
      ? "\(selectedAccount) -> \(currentIndex)/\(totalRepoTargets): \(repoTarget)"
      : "\(selectedAccount) -> \(repoTarget)"
    appendLog("[gui] [\(currentIndex)/\(totalRepoTargets)] Starting cleanup for \(repoTarget) on \(resolvedHost) with \(selectedAccount)\n")

    var arguments = [
      "--host", resolvedHost,
      "--account", selectedAccount,
      "--repo", repoTarget,
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
        self.runningProcess = nil

        if self.cancellationRequested {
          self.finishCleanupQueue(cancelled: true)
          return
        }

        if terminated.terminationStatus == 0 {
          self.completedRepoTargets.append(repoTarget)
        } else {
          self.failedRepoTargets.append(repoTarget)
          self.appendLog("[gui] Cleanup failed for \(repoTarget) with exit code \(terminated.terminationStatus)\n")
        }

        if let nextTarget = self.pendingRepoTargets.first {
          self.pendingRepoTargets.removeFirst()
          self.launchCleanup(for: nextTarget, using: cliPath, account: selectedAccount)
        } else {
          self.finishCleanupQueue(cancelled: false)
        }
      }
    }

    processQueue.async {
      do {
        try process.run()
      } catch {
        DispatchQueue.main.async {
          self.failedRepoTargets.append(repoTarget)
          self.appendLog("[gui] Failed to launch cleanup: \(error.localizedDescription)\n")
          if let nextTarget = self.pendingRepoTargets.first {
            self.pendingRepoTargets.removeFirst()
            self.launchCleanup(for: nextTarget, using: cliPath, account: selectedAccount)
          } else {
            self.finishCleanupQueue(cancelled: false)
          }
        }
      }
    }
  }

  private func finishCleanupQueue(cancelled: Bool) {
    isRunning = false
    runningProcess = nil
    safetyArmEnabled = false
    let completedCount = completedRepoTargets.count
    let failedCount = failedRepoTargets.count
    let summary = "Completed \(completedCount) of \(totalRepoTargets). Failed: \(failedCount)."

    if cancelled {
      statusKind = .warning
      statusTitle = "Cleanup Cancelled"
      statusDetail = summary
      appendLog("[gui] Cleanup cancelled by user.\n")
    } else if failedCount == 0 {
      statusKind = .ready
      statusTitle = dryRun ? "Dry Run Finished" : "Cleanup Finished"
      statusDetail = summary
    } else {
      statusKind = .error
      statusTitle = "Cleanup Finished With Errors"
      statusDetail = summary
    }

    pendingRepoTargets.removeAll()
    activeRepoTarget = ""
    totalRepoTargets = 0
    cancellationRequested = false
    reloadAuthInventory()
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
  let compact: Bool

  var body: some View {
    Group {
      if compact {
        VStack(alignment: .leading, spacing: 18) {
          titleBlock
          statusBlock(alignment: .leading)
        }
      } else {
        HStack(alignment: .center, spacing: 22) {
          titleBlock
          Spacer(minLength: 20)
          statusBlock(alignment: .trailing)
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

  @ViewBuilder
  private var titleBlock: some View {
    HStack(alignment: .center, spacing: 22) {
      if let icon {
        Image(nsImage: icon)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: compact ? 74 : 92, height: compact ? 74 : 92)
          .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
      }

      VStack(alignment: .leading, spacing: 10) {
        Text("W.T.L.")
          .font(.system(size: 14, weight: .semibold, design: .rounded))
          .tracking(2.4)
          .foregroundStyle(DashboardTheme.accent)

        Text(appTitle)
          .font(.system(size: compact ? 28 : 34, weight: .bold, design: .rounded))
          .foregroundStyle(DashboardTheme.text)
          .lineLimit(2)

        Text("Native macOS SwiftUI control panel for GitHub Actions cleanup.")
          .font(.system(size: 14, weight: .medium, design: .rounded))
          .foregroundStyle(DashboardTheme.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder
  private func statusBlock(alignment: HorizontalAlignment) -> some View {
    VStack(alignment: alignment, spacing: 12) {
      HStack(spacing: 10) {
        PillBadge(text: "Native SwiftUI", tint: DashboardTheme.accent)
        PillBadge(text: "CLI Engine", tint: DashboardTheme.success)
        PillBadge(text: "Version \(appVersion)", tint: DashboardTheme.warning)
      }

      Text(statusTitle)
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .foregroundStyle(statusKind.tint)
        .multilineTextAlignment(alignment == .leading ? .leading : .trailing)

      if let lastSessionSummary {
        Text(lastSessionSummary)
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .foregroundStyle(DashboardTheme.subtle)
          .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
      }
    }
  }
}

struct DashboardShell<Content: View>: View {
  @ViewBuilder let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      content
    }
    .padding(20)
    .background(
      RoundedRectangle(cornerRadius: 30, style: .continuous)
        .fill(
          LinearGradient(
            colors: [DashboardTheme.panel.opacity(0.94), DashboardTheme.panelAlt.opacity(0.92)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .overlay(
          RoundedRectangle(cornerRadius: 30, style: .continuous)
            .stroke(DashboardTheme.border, lineWidth: 1)
        )
    )
    .shadow(color: .black.opacity(0.22), radius: 30, y: 20)
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

struct RepoSelectionRow: View {
  let repo: RepoCatalogEntry
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: .center, spacing: 12) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(isSelected ? DashboardTheme.success : DashboardTheme.subtle)

        VStack(alignment: .leading, spacing: 4) {
          Text(repo.shortName)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(DashboardTheme.text)
            .lineLimit(1)

          Text(repo.nameWithOwner)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(DashboardTheme.muted)
            .lineLimit(1)
        }

        Spacer(minLength: 12)

        VStack(alignment: .trailing, spacing: 4) {
          Text(repo.visibilityLabel)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(repo.isPrivate == true ? DashboardTheme.warning : DashboardTheme.accent)

          Text(repo.updatedLabel)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(DashboardTheme.subtle)
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(isSelected ? DashboardTheme.field.opacity(1.0) : DashboardTheme.panelStrong)
          .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .stroke(isSelected ? DashboardTheme.success.opacity(0.45) : DashboardTheme.border, lineWidth: 1)
          )
      )
    }
    .buttonStyle(.plain)
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
      let contentWidth = max(geometry.size.width - 32, 640)

      ZStack {
        LinearGradient(
          colors: [DashboardTheme.canvasTop, DashboardTheme.canvasBottom],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        ScrollView {
          VStack(spacing: 18) {
            DashboardShell {
              HeaderPanel(
                icon: model.bundledIcon,
                lastSessionSummary: model.lastSessionSummary,
                statusTitle: model.statusTitle,
                statusKind: model.statusKind,
                compact: contentWidth < 1280
              )

              dashboardLayout(for: contentWidth)
            }
          }
          .padding(16)
          .frame(maxWidth: 1720)
          .frame(maxWidth: .infinity)
        }
      }
    }
    .frame(minWidth: 960, minHeight: 760)
    .preferredColorScheme(.dark)
  }

  @ViewBuilder
  private func dashboardLayout(for width: CGFloat) -> some View {
    if width >= 1560 {
      HStack(alignment: .top, spacing: 18) {
        VStack(alignment: .leading, spacing: 18) {
          authPanel
          repositoryPanel
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)

        VStack(alignment: .leading, spacing: 18) {
          cleanupPanel
          executionPanel
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)

        logPanel(minHeight: 720)
          .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    } else if width >= 1160 {
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .top, spacing: 18) {
          authPanel
            .frame(maxWidth: .infinity, alignment: .topLeading)

          VStack(alignment: .leading, spacing: 18) {
            cleanupPanel
            executionPanel
          }
          .frame(maxWidth: .infinity, alignment: .topLeading)
        }

        repositoryPanel
        logPanel(minHeight: 440)
      }
    } else {
      VStack(alignment: .leading, spacing: 18) {
        authPanel
        repositoryPanel
        cleanupPanel
        executionPanel
        logPanel(minHeight: 320)
      }
    }
  }

  private var authPanel: some View {
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
  }

  private var repositoryPanel: some View {
    PanelCard(title: "Repository Targets", subtitle: "Browse repositories for the selected account or owner, then check one, many, or all.") {
      VStack(alignment: .leading, spacing: 6) {
        FieldLabel(text: "Owner or Org to List")
        TextField("Defaults to the selected GitHub account", text: $model.repoOwner)
          .textFieldStyle(.plain)
          .foregroundStyle(DashboardTheme.text)
          .dashboardFieldStyle()
      }

      HStack(spacing: 10) {
        Button(model.isLoadingRepos ? "Loading..." : "Load Repositories") {
          model.fetchAvailableRepos()
        }
        .buttonStyle(DashboardButtonStyle(tint: DashboardTheme.accent, bordered: true))
        .disabled(model.isLoadingRepos || !model.isAuthenticated)

        Button("Clear Checked") {
          model.selectedRepos.removeAll()
        }
        .buttonStyle(DashboardButtonStyle(tint: DashboardTheme.warning, bordered: true))
        .disabled(model.selectedRepos.isEmpty)
      }

      Toggle(
        "Select all loaded repositories (\(model.availableRepos.count))",
        isOn: Binding(
          get: { model.areAllLoadedReposSelected },
          set: { model.setAllLoadedReposSelected($0) }
        )
      )
      .toggleStyle(.switch)
      .tint(DashboardTheme.success)
      .foregroundStyle(DashboardTheme.text)
      .disabled(model.availableRepos.isEmpty)

      VStack(alignment: .leading, spacing: 6) {
        FieldLabel(text: "Search Loaded Repositories")
        TextField("Filter by owner, repo name, or visibility", text: $model.repoSearch)
          .textFieldStyle(.plain)
          .foregroundStyle(DashboardTheme.text)
          .dashboardFieldStyle()
          .disabled(model.availableRepos.isEmpty)
      }

      BannerCard(
        title: model.selectedRepoSummary,
        detail: model.repoCatalogStatus,
        kind: model.cleanupTargets.isEmpty ? .warning : .ready
      )

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 10) {
          if model.filteredRepos.isEmpty {
            Text(model.availableRepos.isEmpty ? "No repositories loaded yet." : "No repositories match the current search.")
              .font(.system(size: 13, weight: .medium, design: .rounded))
              .foregroundStyle(DashboardTheme.muted)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.top, 4)
          } else {
            ForEach(model.filteredRepos) { repo in
              RepoSelectionRow(
                repo: repo,
                isSelected: model.selectedRepos.contains(repo.nameWithOwner)
              ) {
                model.toggleRepoSelection(repo)
              }
            }
          }
        }
      }
      .frame(minHeight: 180, idealHeight: 260, maxHeight: 320)

      Divider().overlay(DashboardTheme.border)

      VStack(alignment: .leading, spacing: 6) {
        FieldLabel(text: "Manual Repository or URL Fallback")
        TextField("OWNER/REPO or https://github.com/OWNER/REPO", text: $model.repoTarget)
          .textFieldStyle(.plain)
          .foregroundStyle(DashboardTheme.text)
          .dashboardFieldStyle()
      }

      Text("If one or more repositories are checked above, the manual field is ignored. Use the manual field only when you want a one-off target that is not in the loaded list.")
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(DashboardTheme.muted)
        .lineSpacing(2)
    }
  }

  private var cleanupPanel: some View {
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
  }

  private var executionPanel: some View {
    VStack(alignment: .leading, spacing: 18) {
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
    }
  }

  private func logPanel(minHeight: CGFloat) -> some View {
    PanelCard(title: "Live Output", subtitle: "Readable, high-contrast CLI output streamed into the native app.") {
      LogConsoleView(text: model.logText)
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight)
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

    DispatchQueue.main.async {
      for window in NSApp.windows {
        self.configure(window)
      }
    }
  }

  private func configure(_ window: NSWindow) {
    window.minSize = NSSize(width: 960, height: 760)
    window.setContentSize(NSSize(width: 1320, height: 860))
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.toolbarStyle = .unified
    window.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.10, alpha: 1)
    window.isMovableByWindowBackground = false
    window.center()
  }
}
