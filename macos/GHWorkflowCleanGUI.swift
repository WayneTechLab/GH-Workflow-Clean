import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

private let appTitle = "GH Workflow Clean"
private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.7"
private let companyName = "Wayne Tech Lab LLC"
private let companyWebsite = "www.WayneTechLab.com"
private let companyWebsiteURL = "https://www.WayneTechLab.com"
private let appSupportDir = NSString(string: "~/Library/Application Support/GH Workflow Clean").expandingTildeInPath
private let lastSessionFile = (appSupportDir as NSString).appendingPathComponent("last-session.env")
private let legacyAppSupportDir = NSString(string: "~/Library/Application Support/GitHub Action Clean-Up Tool").expandingTildeInPath
private let legacyLastSessionFile = (legacyAppSupportDir as NSString).appendingPathComponent("last-session.env")
private let bundledHelpDirectory = "Help"
private let defaultSearchPaths = [
  "/opt/homebrew/bin",
  "/usr/local/bin",
  "/usr/bin",
  "/bin",
  "/usr/sbin",
  "/sbin"
]
private let defaultTermsOfServiceText = """
GH Workflow Clean
Provided by Wayne Tech Lab LLC
www.WayneTechLab.com

Warning! This is a deletion tool. Use at your own risk.

By accepting and using this product, you acknowledge and agree that:

1. This tool is intended only for authorized, professional GitHub Actions cleanup work.
2. This tool can permanently delete workflow runs, artifacts, caches, and workflow configurations.
3. You are solely responsible for verifying the GitHub host, account, repository, and cleanup scope before execution.
4. You will use this software only on repositories, organizations, and accounts you are authorized to manage.
5. You accept full responsibility for data loss, workflow interruption, billing changes, repository impact, and any other outcome caused by use or misuse of this tool.
6. This software is provided as-is, without warranties, guarantees, or assurances of fitness for any purpose.
7. Wayne Tech Lab LLC, its operators, authors, affiliates, and contributors are not liable for damages, losses, claims, or operational impact resulting from use of this software.

If you do not accept these terms, do not use this product.
"""

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
    case .ready: return Color(red: 79 / 255, green: 169 / 255, blue: 139 / 255)
    case .warning: return Color(red: 209 / 255, green: 165 / 255, blue: 82 / 255)
    case .error: return Color(red: 196 / 255, green: 98 / 255, blue: 141 / 255)
    case .running: return Color(red: 121 / 255, green: 180 / 255, blue: 245 / 255)
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

private enum AppDestination: String, CaseIterable, Identifiable {
  case controlCenter
  case settings
  case helpCenter
  case terms
  case security
  case brandSystem
  case macOSNotes
  case projectInfo
  case about

  var id: String { rawValue }

  var title: String {
    switch self {
    case .controlCenter: return "Control Center"
    case .settings: return "Settings"
    case .helpCenter: return "Help Center"
    case .terms: return "Terms of Service"
    case .security: return "Security Notes"
    case .brandSystem: return "Brand System"
    case .macOSNotes: return "macOS App Notes"
    case .projectInfo: return "Project Info"
    case .about: return "About"
    }
  }

  var subtitle: String {
    switch self {
    case .controlCenter:
      return "Primary cleanup workspace for GitHub auth, repository targeting, safety, and execution."
    case .settings:
      return "GitHub host, account, login state, and session controls."
    case .helpCenter:
      return "Operational guidance, safety model, target selection rules, and first-run workflow."
    case .terms:
      return "Every-launch responsibility, risk acceptance, and authorized-use conditions."
    case .security:
      return "Secret handling, token safety, stored-data scope, and review notes."
    case .brandSystem:
      return "Official logo, icon, color, and artwork usage requirements for production consistency."
    case .macOSNotes:
      return "Native app packaging, icon, installer, and macOS integration guidance."
    case .projectInfo:
      return "Bundle metadata, resource map, product identity, and project-level implementation notes."
    case .about:
      return "Product identity, company details, bundle state, install details, and local app storage."
    }
  }

  var icon: String {
    switch self {
    case .controlCenter: return "switch.2"
    case .settings: return "gearshape"
    case .helpCenter: return "questionmark.circle"
    case .terms: return "checklist"
    case .security: return "lock.shield"
    case .brandSystem: return "paintpalette"
    case .macOSNotes: return "laptopcomputer"
    case .projectInfo: return "shippingbox"
    case .about: return "info.circle"
    }
  }

  var tint: Color {
    switch self {
    case .controlCenter: return DashboardTheme.accent
    case .settings: return DashboardTheme.warning
    case .helpCenter: return DashboardTheme.success
    case .terms: return DashboardTheme.warning
    case .security: return DashboardTheme.deepBlue
    case .brandSystem: return DashboardTheme.brightPink
    case .macOSNotes: return DashboardTheme.accentPink
    case .projectInfo: return DashboardTheme.success
    case .about: return DashboardTheme.link
    }
  }

  var bundleDocumentName: String? {
    switch self {
    case .settings:
      return nil
    case .helpCenter: return "Help-Center.md"
    case .terms: return "TERMS-OF-SERVICE.md"
    case .security: return "SECURITY.md"
    case .brandSystem: return "Brand-System.md"
    case .macOSNotes: return "macOS-App-Notes.md"
    case .projectInfo: return "PROJECT-INFO.md"
    case .controlCenter, .about: return nil
    }
  }

  var fallbackDocumentText: String {
    switch self {
    case .terms:
      return bundledTermsOfServiceText()
    case .about:
      return ""
    default:
      return "This bundled document is not currently available in the app package."
    }
  }
}

private let workspaceDestinations: [AppDestination] = [.controlCenter, .settings, .about]
private let knowledgeDestinations: [AppDestination] = [.helpCenter, .terms, .security, .brandSystem, .macOSNotes, .projectInfo]

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
  @Published var logText = "[gui] GH Workflow Clean ready.\n"
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

  var bundledBrandMark: NSImage? {
    if let appIconURL = bundledResourceURL(named: "appicon-512x512@2x.png", subdirectory: "AppIcon.appiconset"),
       let appIconImage = NSImage(contentsOf: appIconURL) {
      return appIconImage
    }
    return bundledImage(named: "icon-1024.png") ?? bundledImage(named: "logo-card-square.png")
  }

  var bundledLockup: NSImage? {
    bundledImage(named: "logo-horizontal-lockup.png")
  }

  var bundledHero: NSImage? {
    bundledImage(named: "hero-2560x1600.png")
  }

  var bundleIdentitySummary: String {
    "\(Bundle.main.bundleIdentifier ?? "com.waynetechlab.ghworkflowclean") · Version \(appVersion)"
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
    let resolvedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
    if isAuthenticated && !resolvedAccount.isEmpty {
      return "User \(resolvedAccount) on account \(resolvedAccount) ready on \(resolvedHost)."
    }
    return "No authenticated GitHub account is ready for cleanup."
  }

  var authActionHint: String {
    if isAuthenticated {
      return "Selected account is ready. You can refresh, log out, or continue to repository cleanup."
    }
    return "Log in with GitHub CLI first, then select the account you want to use."
  }

  var sessionCompactLabel: String {
    let resolvedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "github.com" : host.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
    let accountValue = resolvedAccount.isEmpty ? (selectedHostConfig?.activeUser ?? "no account") : resolvedAccount
    return isAuthenticated ? "\(accountValue) @ \(resolvedHost) ready" : "Login required @ \(resolvedHost)"
  }

  var selectionCompactLabel: String {
    let count = cleanupTargets.count
    if count == 0 {
      return "No targets selected"
    }
    if count == 1, let target = cleanupTargets.first {
      return target
    }
    return "\(count) targets selected"
  }

  var statusCompactLabel: String {
    let trimmedTitle = statusTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedTitle.isEmpty {
      return "Idle"
    }
    return trimmedTitle
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
        let sanitizedCleaned = redactSensitiveText(cleaned)
        let resolvedAccount = self.account.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.status == 0 {
          self.isAuthenticated = !resolvedAccount.isEmpty || self.selectedHostConfig?.activeUser != nil
          if self.repoOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.repoOwner = resolvedAccount.isEmpty ? (self.selectedHostConfig?.activeUser ?? "") : resolvedAccount
          }
          self.statusKind = .ready
          self.statusTitle = "GH TOKEN LOGGED IN @ \(selectedHost)"
          self.statusDetail = sanitizedCleaned.isEmpty
            ? "User \(resolvedAccount.isEmpty ? (self.selectedHostConfig?.activeUser ?? "Unknown") : resolvedAccount) on account \(resolvedAccount.isEmpty ? (self.selectedHostConfig?.activeUser ?? "Unknown") : resolvedAccount) ready."
            : "User \(resolvedAccount.isEmpty ? (self.selectedHostConfig?.activeUser ?? "Unknown") : resolvedAccount) on account \(resolvedAccount.isEmpty ? (self.selectedHostConfig?.activeUser ?? "Unknown") : resolvedAccount) ready.\n\(sanitizedCleaned)"
          self.fetchAvailableRepos()
        } else {
          self.isAuthenticated = false
          self.clearRepoCatalog(resetOwner: false)
          self.statusKind = .warning
          self.statusTitle = "GH TOKEN NOT LOGGED IN @ \(selectedHost)"
          self.statusDetail = sanitizedCleaned.isEmpty
            ? "Run gh auth login -h \(selectedHost) before cleanup."
            : sanitizedCleaned
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

  func openBundledHelpDocument(_ fileName: String) {
    guard let url = bundledResourceURL(named: fileName, subdirectory: bundledHelpDirectory) else {
      appendLog("[gui] Help document not found: \(fileName)\n")
      return
    }

    NSWorkspace.shared.open(url)
  }

  func openCompanyWebsite() {
    guard let url = URL(string: companyWebsiteURL) else {
      appendLog("[gui] Company website URL is invalid.\n")
      return
    }

    NSWorkspace.shared.open(url)
  }

  func revealSessionStorage() {
    let supportURL = URL(fileURLWithPath: appSupportDir, isDirectory: true)
    try? FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
    NSWorkspace.shared.activateFileViewerSelecting([supportURL])
  }

  func revealBundledHelpDirectory() {
    guard let helpURL = bundledResourceURL(named: bundledHelpDirectory) else {
      appendLog("[gui] Bundled help directory was not found.\n")
      return
    }

    NSWorkspace.shared.activateFileViewerSelecting([helpURL])
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
        let sanitizedCleaned = redactSensitiveText(cleaned)

        guard result.status == 0 else {
          self.availableRepos = []
          self.selectedRepos.removeAll()
          self.repoCatalogStatus = sanitizedCleaned.isEmpty
            ? "Failed to load repositories for \(targetOwner)."
            : sanitizedCleaned
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
    logText += redactSensitiveText(text)
  }

  private func loadLastSession() -> [String: String] {
    let sessionPath: String

    if FileManager.default.fileExists(atPath: lastSessionFile) {
      sessionPath = lastSessionFile
    } else if FileManager.default.fileExists(atPath: legacyLastSessionFile) {
      sessionPath = legacyLastSessionFile
    } else {
      return [:]
    }

    guard let contents = try? String(contentsOfFile: sessionPath, encoding: .utf8) else {
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

private func bundledTermsOfServiceText() -> String {
  guard let url = Bundle.main.url(forResource: "TERMS-OF-SERVICE", withExtension: "md"),
        let contents = try? String(contentsOf: url, encoding: .utf8),
        contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
    return defaultTermsOfServiceText
  }

  return contents
}

private func bundledResourceURL(named name: String, subdirectory: String? = nil) -> URL? {
  let resourceRoot = Bundle.main.resourceURL

  if let subdirectory {
    let url = resourceRoot?.appendingPathComponent(subdirectory).appendingPathComponent(name)
    if let url, FileManager.default.fileExists(atPath: url.path) {
      return url
    }
  }

  let directURL = resourceRoot?.appendingPathComponent(name)
  if let directURL, FileManager.default.fileExists(atPath: directURL.path) {
    return directURL
  }

  return nil
}

private func bundledImage(named name: String) -> NSImage? {
  guard let url = bundledResourceURL(named: name) else {
    return nil
  }
  return NSImage(contentsOf: url)
}

private func bundledDocumentText(named name: String, fallback: String = "") -> String {
  if let helpURL = bundledResourceURL(named: name, subdirectory: bundledHelpDirectory),
     let contents = try? String(contentsOf: helpURL, encoding: .utf8),
     contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
    return contents
  }

  if let directURL = bundledResourceURL(named: name),
     let contents = try? String(contentsOf: directURL, encoding: .utf8),
     contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
    return contents
  }

  return fallback
}

private func attributedMarkdown(_ markdown: String) -> AttributedString {
  if let parsed = try? AttributedString(
    markdown: markdown,
    options: AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .full,
      failurePolicy: .returnPartiallyParsedIfPossible
    )
  ) {
    return parsed
  }

  return AttributedString(markdown)
}

private func redactSensitiveText(_ text: String) -> String {
  let replacements: [(pattern: String, replacement: String)] = [
    ("ghp_[A-Za-z0-9]{20,}", "[REDACTED_GITHUB_TOKEN]"),
    ("github_pat_[A-Za-z0-9_]{20,}", "[REDACTED_GITHUB_TOKEN]"),
    ("gho_[A-Za-z0-9]{20,}", "[REDACTED_GITHUB_TOKEN]"),
    ("AKIA[0-9A-Z]{16}", "[REDACTED_AWS_KEY]"),
    ("AIza[0-9A-Za-z\\-_]{20,}", "[REDACTED_API_KEY]"),
    ("(?i)authorization:\\s*bearer\\s+[A-Za-z0-9._\\-]+", "Authorization: Bearer [REDACTED]"),
    ("(?i)(gh_token|github_token|access_token|client_secret|api_key)\\s*[:=]\\s*[^\\s\\n]+", "$1=[REDACTED]")
  ]

  var sanitized = text
  for item in replacements {
    guard let regex = try? NSRegularExpression(pattern: item.pattern, options: []) else {
      continue
    }
    let range = NSRange(sanitized.startIndex..., in: sanitized)
    sanitized = regex.stringByReplacingMatches(in: sanitized, options: [], range: range, withTemplate: item.replacement)
  }

  return sanitized
}

private enum DashboardTheme {
  static let navyOutline = Color(red: 31 / 255, green: 77 / 255, blue: 134 / 255)
  static let deepBlue = Color(red: 21 / 255, green: 80 / 255, blue: 143 / 255)
  static let brightPink = Color(red: 246 / 255, green: 95 / 255, blue: 165 / 255)
  static let accentPink = Color(red: 217 / 255, green: 44 / 255, blue: 123 / 255)
  static let coolWhite = Color(red: 247 / 255, green: 248 / 255, blue: 250 / 255)
  static let gridGray = Color(red: 216 / 255, green: 221 / 255, blue: 227 / 255)

  static let canvasTop = Color(red: 15 / 255, green: 23 / 255, blue: 32 / 255)
  static let canvasBottom = Color(red: 17 / 255, green: 25 / 255, blue: 35 / 255)
  static let panel = Color(red: 24 / 255, green: 32 / 255, blue: 43 / 255)
  static let panelAlt = Color(red: 27 / 255, green: 37 / 255, blue: 49 / 255)
  static let panelStrong = Color(red: 20 / 255, green: 28 / 255, blue: 38 / 255)
  static let field = Color(red: 30 / 255, green: 40 / 255, blue: 53 / 255)
  static let border = Color.white.opacity(0.08)
  static let text = coolWhite
  static let muted = Color(red: 211 / 255, green: 219 / 255, blue: 230 / 255)
  static let subtle = Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255)
  static let accent = Color(red: 125 / 255, green: 178 / 255, blue: 239 / 255)
  static let success = Color(red: 42 / 255, green: 110 / 255, blue: 88 / 255)
  static let warning = Color(red: 209 / 255, green: 165 / 255, blue: 82 / 255)
  static let danger = Color(red: 133 / 255, green: 49 / 255, blue: 94 / 255)
  static let link = Color(red: 141 / 255, green: 198 / 255, blue: 255 / 255)
  static let warningSurface = Color(red: 250 / 255, green: 239 / 255, blue: 219 / 255)
  static let warningText = Color(red: 74 / 255, green: 54 / 255, blue: 24 / 255)
  static let warningSubtle = Color(red: 107 / 255, green: 83 / 255, blue: 46 / 255)
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
          .font(.system(size: compact ? 15 : 17, weight: .bold, design: .rounded))
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
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(DashboardTheme.panelAlt)
        .overlay(
          RoundedRectangle(cornerRadius: 20, style: .continuous)
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
      .background(DashboardTheme.field)
      .overlay(
        Capsule()
          .stroke(tint.opacity(0.38), lineWidth: 1)
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
        .foregroundStyle(kind.tint)
        .frame(width: 36, height: 36)
        .background(DashboardTheme.panelStrong)
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
        .fill(DashboardTheme.field)
        .overlay(
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(kind.tint.opacity(0.30), lineWidth: 1)
        )
    )
  }
}

struct BrandMarkSquareView: View {
  let image: NSImage?
  let size: CGFloat
  let cornerRadius: CGFloat

  init(image: NSImage?, size: CGFloat, cornerRadius: CGFloat = 24) {
    self.image = image
    self.size = size
    self.cornerRadius = cornerRadius
  }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(DashboardTheme.panelStrong)
        .overlay(
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(DashboardTheme.border, lineWidth: 1)
        )

      if let image {
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
          .frame(width: size, height: size)
          .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      } else {
        Image(systemName: "app.dashed")
          .font(.system(size: size * 0.24, weight: .semibold))
          .foregroundStyle(DashboardTheme.subtle)
      }
    }
    .frame(width: size, height: size)
  }
}

struct HeaderPanel: View {
  let brandMark: NSImage?
  let compact: Bool

  var body: some View {
    ZStack(alignment: .topTrailing) {
      HStack(spacing: 0) {
        Color.clear
          .frame(width: compact ? 120 : 200, height: 1)

        VStack(alignment: .center, spacing: compact ? 8 : 10) {
          Text(appTitle)
            .font(.system(size: compact ? 28 : 34, weight: .bold, design: .rounded))
            .foregroundStyle(DashboardTheme.text)
            .multilineTextAlignment(.center)
            .lineLimit(2)

          Text("Provided by: \(companyName) · \(companyWebsite)")
            .font(.system(size: compact ? 12 : 13, weight: .semibold, design: .rounded))
            .foregroundStyle(DashboardTheme.muted)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)

        BrandMarkSquareView(
          image: brandMark,
          size: compact ? 120 : 200,
          cornerRadius: compact ? 20 : 26
        )
      }
    }
    .padding(.horizontal, 24)
    .padding(.vertical, compact ? 18 : 20)
    .frame(minHeight: compact ? 132 : 164)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(DashboardTheme.panel)
        .overlay(
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(DashboardTheme.border, lineWidth: 1)
        )
    )
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
    .padding(18)
    .background(
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(DashboardTheme.panel)
        .overlay(
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(DashboardTheme.border, lineWidth: 1)
        )
    )
    .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
  }
}

private struct MenuSectionHeader: View {
  let text: String

  var body: some View {
    Text(text.uppercased())
      .font(.system(size: 11, weight: .bold, design: .rounded))
      .foregroundStyle(DashboardTheme.subtle)
  }
}

private struct DestinationMenuButton: View {
  let destination: AppDestination
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: destination.icon)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(isSelected ? DashboardTheme.text : destination.tint)
          .frame(width: 20)

        Text(destination.title)
          .font(.system(size: 13, weight: .bold, design: .rounded))
          .foregroundStyle(DashboardTheme.text)
          .lineLimit(1)

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 11)
      .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(isSelected ? destination.tint.opacity(0.42) : DashboardTheme.field)
          .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .stroke(isSelected ? destination.tint.opacity(0.65) : DashboardTheme.border, lineWidth: 1)
          )
      )
    }
    .buttonStyle(.plain)
  }
}

private struct WorkspaceToolbarStrip: View {
  let destination: AppDestination
  let menuVisible: Bool
  let usesSidebar: Bool
  let toggleMenu: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Button(menuVisible ? "Hide Menu" : "Show Menu") {
        toggleMenu()
      }
      .buttonStyle(DashboardButtonStyle(tint: DashboardTheme.accent, bordered: true))

      PillBadge(text: destination.title, tint: destination.tint)

      Spacer(minLength: 0)

      Text(menuVisible ? (usesSidebar ? "Sidebar menu" : "Top menu") : "Focus mode")
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(DashboardTheme.muted)
        .lineLimit(1)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(DashboardTheme.panelAlt)
        .overlay(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(DashboardTheme.border, lineWidth: 1)
        )
    )
  }
}

private struct StatusBarActionButton: View {
  let title: String
  let systemImage: String
  let tint: Color
  let isDisabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: systemImage)
          .font(.system(size: 11, weight: .bold))
        Text(title)
          .font(.system(size: 11, weight: .bold, design: .rounded))
      }
      .foregroundStyle(DashboardTheme.text)
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(
        Capsule()
          .fill(DashboardTheme.field)
          .overlay(
            Capsule()
              .stroke(tint.opacity(0.55), lineWidth: 1)
          )
      )
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
    .opacity(isDisabled ? 0.55 : 1.0)
  }
}

private struct BottomStatusBar: View {
  let kind: StatusKind
  let status: String
  let session: String
  let selection: String
  let destination: AppDestination
  let compact: Bool
  let isAuthenticated: Bool
  let isLoggingOut: Bool
  let refreshAction: () -> Void
  let loginAction: () -> Void
  let logoutAction: () -> Void
  let settingsAction: () -> Void

  private var statusLine: some View {
    HStack(spacing: 10) {
      Image(systemName: kind.icon)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(kind.tint)

      Text(status)
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(DashboardTheme.text)
        .lineLimit(1)
        .minimumScaleFactor(0.85)

      Text("•")
        .foregroundStyle(DashboardTheme.subtle)

      Text(session)
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(DashboardTheme.muted)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .truncationMode(.middle)

      Text("•")
        .foregroundStyle(DashboardTheme.subtle)

      Text(selection)
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(DashboardTheme.muted)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .truncationMode(.middle)

      Spacer(minLength: 0)

      PillBadge(text: destination.title, tint: destination.tint)
    }
  }

  private var actionLine: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        StatusBarActionButton(title: "Refresh", systemImage: "arrow.clockwise", tint: DashboardTheme.accent, isDisabled: false, action: refreshAction)
        StatusBarActionButton(title: isAuthenticated ? "Re-Login" : "Login", systemImage: "person.crop.circle.badge.checkmark", tint: DashboardTheme.success, isDisabled: false, action: loginAction)
        StatusBarActionButton(title: "Logout", systemImage: "rectangle.portrait.and.arrow.right", tint: DashboardTheme.warning, isDisabled: !isAuthenticated || isLoggingOut, action: logoutAction)
        StatusBarActionButton(title: "Settings", systemImage: "gearshape", tint: DashboardTheme.link, isDisabled: false, action: settingsAction)
      }
      .padding(.horizontal, 2)
    }
    .frame(maxWidth: compact ? .infinity : 430, alignment: .trailing)
  }

  var body: some View {
    Group {
      if compact {
        VStack(alignment: .leading, spacing: 10) {
          statusLine
          actionLine
        }
      } else {
        HStack(spacing: 12) {
          statusLine
          actionLine
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(DashboardTheme.panelAlt)
        .overlay(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(DashboardTheme.border, lineWidth: 1)
        )
    )
  }
}

private struct CompactDestinationBar: View {
  let selection: AppDestination
  let onSelect: (AppDestination) -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(AppDestination.allCases) { destination in
          Button(action: { onSelect(destination) }) {
            HStack(spacing: 8) {
              Image(systemName: destination.icon)
                .font(.system(size: 12, weight: .bold))
              Text(destination.title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(selection == destination ? DashboardTheme.text : DashboardTheme.muted)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
              Capsule()
                .fill(selection == destination ? destination.tint.opacity(0.42) : DashboardTheme.field)
                .overlay(
                  Capsule()
                    .stroke(selection == destination ? destination.tint.opacity(0.65) : DashboardTheme.border, lineWidth: 1)
                )
            )
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 4)
    }
  }
}

private struct AppSidebarMenu: View {
  let selection: AppDestination
  let onSelect: (AppDestination) -> Void

  var body: some View {
    PanelCard(title: "App Menu", subtitle: "Move between the cleanup workspace and bundled in-app reference pages.", compact: true) {
      VStack(alignment: .leading, spacing: 12) {
        MenuSectionHeader(text: "Workspace")
        ForEach(workspaceDestinations) { destination in
          DestinationMenuButton(destination: destination, isSelected: selection == destination) {
            onSelect(destination)
          }
        }

        Divider().overlay(DashboardTheme.border)

        MenuSectionHeader(text: "Knowledge Base")
        ForEach(knowledgeDestinations) { destination in
          DestinationMenuButton(destination: destination, isSelected: selection == destination) {
            onSelect(destination)
          }
        }
      }
    }
  }
}

private struct DocumentReaderCard: View {
  let destination: AppDestination
  let markdown: String

  var body: some View {
    PanelCard(title: destination.title, subtitle: destination.subtitle) {
      BannerCard(
        title: destination.title,
        detail: "This page is bundled inside the native app and stays available without leaving the interface.",
        kind: .ready
      )

      Text(attributedMarkdown(markdown))
        .font(.system(size: 14, weight: .medium, design: .rounded))
        .foregroundStyle(DashboardTheme.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .lineSpacing(4)
        .padding(18)
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

private struct DestinationShortcutTile: View {
  let destination: AppDestination
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Image(systemName: destination.icon)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(isSelected ? DashboardTheme.text : destination.tint)
          Spacer(minLength: 0)
          if isSelected {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 14, weight: .bold))
              .foregroundStyle(destination.tint)
          }
        }

        Text(destination.title)
          .font(.system(size: 14, weight: .bold, design: .rounded))
          .foregroundStyle(DashboardTheme.text)
          .multilineTextAlignment(.leading)

        Text(destination.subtitle)
          .font(.system(size: 11, weight: .medium, design: .rounded))
          .foregroundStyle(DashboardTheme.muted)
          .lineLimit(3)
          .multilineTextAlignment(.leading)
      }
      .padding(14)
      .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
      .background(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(isSelected ? destination.tint.opacity(0.18) : DashboardTheme.field)
          .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .stroke(isSelected ? destination.tint.opacity(0.55) : DashboardTheme.border, lineWidth: 1)
          )
      )
    }
    .buttonStyle(.plain)
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
      .foregroundStyle(DashboardTheme.text)
      .padding(.horizontal, 16)
      .padding(.vertical, 11)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(
            bordered
              ? DashboardTheme.panelStrong.opacity(configuration.isPressed ? 0.88 : 1.0)
              : tint.opacity(configuration.isPressed ? 0.82 : 1.0)
          )
      )
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(bordered ? tint.opacity(0.72) : tint.opacity(0.95), lineWidth: 1)
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
          .foregroundStyle(DashboardTheme.warningSurface)
          .frame(width: 40, height: 40)
          .background(DashboardTheme.warningText)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        VStack(alignment: .leading, spacing: 6) {
          Text("Warning: Permanent Delete")
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(DashboardTheme.warningText)

          Text(dryRun ? "Dry run is enabled, but this app is built for destructive cleanup. Confirm the repo and account before you continue." : "This will permanently delete GitHub Actions data. Workflow runs, artifacts, caches, and disabled workflows cannot be restored.")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(DashboardTheme.warningSubtle)
            .lineSpacing(3)
        }
      }

      Toggle(isOn: $isArmed) {
        Text("Arm destructive cleanup")
          .font(.system(size: 14, weight: .bold, design: .rounded))
          .foregroundStyle(DashboardTheme.warningText)
      }
      .toggleStyle(.switch)
      .tint(DashboardTheme.deepBlue)

      Text(isArmed ? "Safety lock is OFF. Cleanup buttons are unlocked." : "Safety lock is ON. Turn this switch on before cleanup can run.")
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(isArmed ? DashboardTheme.warningText : DashboardTheme.warningSubtle)
    }
    .padding(20)
    .background(
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(DashboardTheme.warningSurface)
        .overlay(
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(DashboardTheme.warning.opacity(0.65), lineWidth: 1)
        )
    )
  }
}

struct LaunchWarningSheet: View {
  @Binding var acceptedRisk: Bool
  @Binding var acceptedPurpose: Bool
  let brandMark: NSImage?
  let continueAction: () -> Void
  let quitAction: () -> Void

  private let termsText = bundledTermsOfServiceText()

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [DashboardTheme.canvasTop, DashboardTheme.canvasBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          HStack(alignment: .top, spacing: 18) {
            BrandMarkSquareView(image: brandMark, size: 92, cornerRadius: 20)

            VStack(alignment: .leading, spacing: 8) {
              Text("Warning!")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(DashboardTheme.text)

              Text("This is a deletion tool. Use at your own risk.")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(DashboardTheme.warning)

              Text("\(appTitle) is a professional clean-up tool provided by \(companyName). Review the terms below every time before using the product.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(DashboardTheme.muted)
                .lineSpacing(3)

              Link(companyWebsite, destination: URL(string: companyWebsiteURL)!)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tint(DashboardTheme.link)
            }
          }

          PanelCard(title: "Terms of Service", subtitle: "You must accept responsibility and intended-use conditions before the tool unlocks.") {
            ScrollView {
              Text(termsText)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(DashboardTheme.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 280, maxHeight: 320)
            .padding(2)
            .background(
              RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DashboardTheme.panelStrong)
                .overlay(
                  RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(DashboardTheme.border, lineWidth: 1)
                )
            )

            Toggle("I understand this tool can permanently delete GitHub Actions data and I accept full responsibility for its use.", isOn: $acceptedRisk)
              .toggleStyle(.switch)
              .tint(DashboardTheme.danger)
              .foregroundStyle(DashboardTheme.text)

            Toggle("I will use this product only for its intended professional clean-up purpose and only where I am authorized to make these changes.", isOn: $acceptedPurpose)
              .toggleStyle(.switch)
              .tint(DashboardTheme.accent)
              .foregroundStyle(DashboardTheme.text)
          }

          HStack(spacing: 12) {
            Button("Quit App") {
              quitAction()
            }
            .buttonStyle(DashboardButtonStyle(tint: DashboardTheme.warning, bordered: true))

            Button("Accept and Continue") {
              continueAction()
            }
            .buttonStyle(DashboardButtonStyle(tint: DashboardTheme.deepBlue, bordered: false))
            .disabled(!(acceptedRisk && acceptedPurpose))
          }

          Text("Acceptance is required every time the app is opened.")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(DashboardTheme.subtle)
        }
        .padding(24)
        .frame(maxWidth: 980)
        .frame(maxWidth: .infinity)
      }
    }
    .frame(minWidth: 920, minHeight: 760)
    .preferredColorScheme(.dark)
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
    textView.backgroundColor = NSColor(calibratedRed: 20 / 255, green: 28 / 255, blue: 38 / 255, alpha: 1)
    textView.textColor = NSColor(calibratedRed: 247 / 255, green: 248 / 255, blue: 250 / 255, alpha: 1)
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
    textView.backgroundColor = NSColor(calibratedRed: 20 / 255, green: 28 / 255, blue: 38 / 255, alpha: 1)
    textView.textColor = NSColor(calibratedRed: 247 / 255, green: 248 / 255, blue: 250 / 255, alpha: 1)
    textView.scrollToEndOfDocument(nil)
  }
}

struct ContentView: View {
  @StateObject private var model = CleanupViewModel()
  @State private var selectedDestination: AppDestination = .controlCenter
  @State private var isMenuVisible = true
  @State private var showLaunchWarning = true
  @State private var acceptedRisk = false
  @State private var acceptedPurpose = false

  private var actionToggleTint: Color { DashboardTheme.accent }

  var body: some View {
    GeometryReader { geometry in
      let canUseSidebarMenu = geometry.size.width >= 1440
      let showSidebarMenu = canUseSidebarMenu && isMenuVisible
      let showCompactMenu = !canUseSidebarMenu && isMenuVisible
      let detailWidth = max(geometry.size.width - (showSidebarMenu ? 360 : 32), 640)

      ZStack {
        LinearGradient(
          colors: [DashboardTheme.canvasTop, DashboardTheme.canvasBottom],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack(spacing: 12) {
          Group {
            if showSidebarMenu {
              HStack(alignment: .top, spacing: 18) {
                AppSidebarMenu(selection: selectedDestination) { destination in
                  selectedDestination = destination
                }
                .frame(width: 320)

                pageContainer(for: detailWidth, usesSidebar: canUseSidebarMenu)
                  .frame(maxWidth: .infinity, alignment: .topLeading)
              }
            }
            else {
              VStack(spacing: 12) {
                if showCompactMenu {
                  CompactDestinationBar(selection: selectedDestination) { destination in
                    selectedDestination = destination
                  }
                }

                pageContainer(for: detailWidth, usesSidebar: canUseSidebarMenu)
                  .frame(maxWidth: .infinity, alignment: .topLeading)
              }
            }
          }

          BottomStatusBar(
            kind: model.statusKind,
            status: model.statusCompactLabel,
            session: model.sessionCompactLabel,
            selection: model.selectionCompactLabel,
            destination: selectedDestination,
            compact: geometry.size.width < 1880,
            isAuthenticated: model.isAuthenticated,
            isLoggingOut: model.isLoggingOut,
            refreshAction: {
              model.refreshAuthStatus()
            },
            loginAction: {
              model.openGitHubLogin()
            },
            logoutAction: {
              model.logoutSelectedAccount()
            },
            settingsAction: {
              selectedDestination = .settings
            }
          )
        }
        .padding(16)
      }
    }
    .frame(minWidth: 760, minHeight: 640)
    .preferredColorScheme(.dark)
    .tint(DashboardTheme.link)
    .sheet(isPresented: $showLaunchWarning) {
      LaunchWarningSheet(
        acceptedRisk: $acceptedRisk,
        acceptedPurpose: $acceptedPurpose,
        brandMark: model.bundledBrandMark,
        continueAction: {
          showLaunchWarning = false
        },
        quitAction: {
          NSApp.terminate(nil)
        }
      )
      .interactiveDismissDisabled(true)
    }
  }

  @ViewBuilder
  private func pageContainer(for width: CGFloat, usesSidebar: Bool) -> some View {
    ScrollView {
      VStack(spacing: 18) {
        switch selectedDestination {
        case .controlCenter:
          controlCenterPage(for: width, usesSidebar: usesSidebar)
        case .settings:
          settingsPage(for: width, usesSidebar: usesSidebar)
        case .about:
          aboutPage(usesSidebar: usesSidebar)
        case .helpCenter, .terms, .security, .brandSystem, .macOSNotes, .projectInfo:
          documentPage(for: selectedDestination, usesSidebar: usesSidebar)
        }
      }
      .frame(maxWidth: 3200)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
  }

  private func controlCenterPage(for width: CGFloat, usesSidebar: Bool) -> some View {
    DashboardShell {
      HeaderPanel(
        brandMark: model.bundledBrandMark,
        compact: width < 1280
      )

      WorkspaceToolbarStrip(
        destination: selectedDestination,
        menuVisible: isMenuVisible,
        usesSidebar: usesSidebar
      ) {
        isMenuVisible.toggle()
      }

      dashboardLayout(for: width)
    }
  }

  private func settingsPage(for width: CGFloat, usesSidebar: Bool) -> some View {
    DashboardShell {
      HeaderPanel(
        brandMark: model.bundledBrandMark,
        compact: width < 1280
      )

      WorkspaceToolbarStrip(
        destination: .settings,
        menuVisible: isMenuVisible,
        usesSidebar: usesSidebar
      ) {
        isMenuVisible.toggle()
      }

      settingsLayout(for: width)
    }
  }

  private func documentPage(for destination: AppDestination, usesSidebar: Bool) -> some View {
    let markdown = bundledDocumentText(
      named: destination.bundleDocumentName ?? "",
      fallback: destination.fallbackDocumentText
    )

    return DashboardShell {
      HeaderPanel(
        brandMark: model.bundledBrandMark,
        compact: false
      )

      WorkspaceToolbarStrip(
        destination: destination,
        menuVisible: isMenuVisible,
        usesSidebar: usesSidebar
      ) {
        isMenuVisible.toggle()
      }

      DocumentReaderCard(destination: destination, markdown: markdown)
    }
  }

  private func aboutPage(usesSidebar: Bool) -> some View {
    DashboardShell {
      HeaderPanel(
        brandMark: model.bundledBrandMark,
        compact: false
      )

      WorkspaceToolbarStrip(
        destination: .about,
        menuVisible: isMenuVisible,
        usesSidebar: usesSidebar
      ) {
        isMenuVisible.toggle()
      }

      PanelCard(title: "About GH Workflow Clean", subtitle: "Product identity, bundle metadata, local storage path, and utility actions without leaving the app shell.") {
        BannerCard(
          title: "Native macOS Cleanup Console",
          detail: "\(model.bundleIdentitySummary)\nProvided by \(companyName) · \(companyWebsite)",
          kind: .ready
        )

        if let brandMark = model.bundledBrandMark {
          HStack(alignment: .center, spacing: 16) {
            BrandMarkSquareView(image: brandMark, size: 120, cornerRadius: 24)

            VStack(alignment: .leading, spacing: 8) {
              Text("Official press-kit artwork loaded")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(DashboardTheme.text)

              Text("This screen stays inside the native app. Use the app menu to move between Control Center, Settings, Help, Terms, Security, Brand, and project pages without external file popups.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(DashboardTheme.muted)
                .lineSpacing(3)
            }

            Spacer(minLength: 0)
          }
          .padding(16)
          .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .fill(DashboardTheme.panelStrong)
              .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                  .stroke(DashboardTheme.border, lineWidth: 1)
              )
          )
        }

        FixedValueRow(label: "App Version", value: appVersion)
        FixedValueRow(label: "Bundle ID", value: Bundle.main.bundleIdentifier ?? "com.waynetechlab.ghworkflowclean")
        FixedValueRow(label: "Company", value: companyName)
        FixedValueRow(label: "Website", value: companyWebsite)
        FixedValueRow(label: "Local Session Storage", value: appSupportDir)

        HStack(spacing: 10) {
          Button("Open Website") {
            model.openCompanyWebsite()
          }
          .buttonStyle(DashboardButtonStyle(tint: DashboardTheme.deepBlue, bordered: true))

          Button("Reveal Session Storage") {
            model.revealSessionStorage()
          }
          .buttonStyle(DashboardButtonStyle(tint: DashboardTheme.warning, bordered: true))
        }
      }
    }
  }

  @ViewBuilder
  private func dashboardLayout(for width: CGFloat) -> some View {
    if width >= 2100 {
      HStack(alignment: .top, spacing: 18) {
        repositoryPanel
          .frame(maxWidth: .infinity, alignment: .topLeading)

        cleanupPanel
        .frame(maxWidth: .infinity, alignment: .topLeading)

        VStack(alignment: .leading, spacing: 18) {
          executionPanel
          libraryPanel
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)

        logPanel(minHeight: 760)
          .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    } else if width >= 1560 {
      HStack(alignment: .top, spacing: 18) {
        repositoryPanel
          .frame(maxWidth: .infinity, alignment: .topLeading)

        VStack(alignment: .leading, spacing: 18) {
          cleanupPanel
          executionPanel
          libraryPanel
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)

        logPanel(minHeight: 720)
          .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    } else if width >= 1160 {
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .top, spacing: 18) {
          repositoryPanel
            .frame(maxWidth: .infinity, alignment: .topLeading)

          VStack(alignment: .leading, spacing: 18) {
            cleanupPanel
            executionPanel
            libraryPanel
          }
          .frame(maxWidth: .infinity, alignment: .topLeading)
        }

        logPanel(minHeight: 440)
      }
    } else {
      VStack(alignment: .leading, spacing: 18) {
        repositoryPanel
        cleanupPanel
        executionPanel
        libraryPanel
        logPanel(minHeight: 320)
      }
    }
  }

  @ViewBuilder
  private func settingsLayout(for width: CGFloat) -> some View {
    if width >= 1880 {
      HStack(alignment: .top, spacing: 18) {
        settingsPanel
          .frame(maxWidth: .infinity, alignment: .topLeading)

        settingsInfoPanel
          .frame(maxWidth: .infinity, alignment: .topLeading)

        libraryPanel
          .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    } else if width >= 1320 {
      HStack(alignment: .top, spacing: 18) {
        settingsPanel
          .frame(maxWidth: .infinity, alignment: .topLeading)

        VStack(alignment: .leading, spacing: 18) {
          settingsInfoPanel
          libraryPanel
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    } else {
      VStack(alignment: .leading, spacing: 18) {
        settingsPanel
        settingsInfoPanel
        libraryPanel
      }
    }
  }

  private var settingsPanel: some View {
    PanelCard(title: "GitHub Settings", subtitle: "Host, account, and session controls now live here instead of on the home dashboard.") {
      BannerCard(
        title: model.authHeadline,
        detail: model.authSummary,
        kind: model.isAuthenticated ? .ready : .warning
      )

      FixedValueRow(label: "Current GitHub Session", value: model.sessionCompactLabel)

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

      Text(model.authActionHint)
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(DashboardTheme.muted)
        .lineSpacing(2)

      if !model.statusDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(model.statusDetail)
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .foregroundStyle(DashboardTheme.subtle)
          .lineSpacing(2)
          .frame(maxWidth: .infinity, alignment: .leading)
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

  private var settingsInfoPanel: some View {
    PanelCard(title: "Session and Tooling", subtitle: "Operational details, stored session state, and direct utility actions for the native app.") {
      FixedValueRow(label: "Current Status", value: model.statusCompactLabel)

      if let lastSessionSummary = model.lastSessionSummary {
        FixedValueRow(label: "Last Session", value: lastSessionSummary)
      }

      FixedValueRow(label: "Bundled CLI Engine", value: model.cliPath ?? "Bundled CLI not found")
      FixedValueRow(label: "GitHub CLI", value: model.ghPath ?? "GitHub CLI not found")
      FixedValueRow(label: "Local Session Storage", value: appSupportDir)

      Text("Quick login controls are always available from the bottom status bar. Use this page for full host and account management without crowding the Control Center.")
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(DashboardTheme.muted)
        .lineSpacing(2)

      HStack(spacing: 10) {
        Button("Open CLI") {
          model.openCLIInTerminal()
        }
        .buttonStyle(DashboardButtonStyle(tint: DashboardTheme.accent, bordered: true))

        Button("Reveal Session Storage") {
          model.revealSessionStorage()
        }
        .buttonStyle(DashboardButtonStyle(tint: DashboardTheme.warning, bordered: true))

        Button("Open Website") {
          model.openCompanyWebsite()
        }
        .buttonStyle(DashboardButtonStyle(tint: DashboardTheme.deepBlue, bordered: true))
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
            model.logText = "[gui] \(appTitle) ready.\n"
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

  private var libraryPanel: some View {
    PanelCard(title: "In-App Pages", subtitle: "Navigate to Settings, Help, Terms, Security, Brand, project notes, and About without leaving the app window.") {
      BannerCard(
        title: selectedDestination == .controlCenter ? "Control Center Active" : "\(selectedDestination.title) Active",
        detail: "Use the app menu to move between bundled pages. Documentation and product info now live inside the native interface instead of opening external markdown windows.",
        kind: .ready
      )

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
        ForEach([.settings] + knowledgeDestinations + [.about]) { destination in
          DestinationShortcutTile(
            destination: destination,
            isSelected: selectedDestination == destination
          ) {
            selectedDestination = destination
          }
        }
      }

      Text("The app now uses a native multi-page menu system. Help, legal, security, brand, and project pages stay inside the product instead of opening external document windows.")
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(DashboardTheme.muted)
        .lineSpacing(2)
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
    let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame
      ?? NSRect(x: 0, y: 0, width: 1600, height: 920)
    let targetSize = idealWindowSize(for: visibleFrame.size)
    let targetOrigin = NSPoint(
      x: visibleFrame.origin.x + ((visibleFrame.width - targetSize.width) / 2),
      y: visibleFrame.origin.y + ((visibleFrame.height - targetSize.height) / 2)
    )

    window.minSize = NSSize(width: 760, height: 640)
    window.setFrame(NSRect(origin: targetOrigin, size: targetSize), display: true)
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.toolbarStyle = .unified
    window.backgroundColor = NSColor(calibratedRed: 9 / 255, green: 21 / 255, blue: 38 / 255, alpha: 1)
    window.isMovableByWindowBackground = false
    window.tabbingMode = .disallowed
  }

  private func idealWindowSize(for screenSize: NSSize) -> NSSize {
    let widthRatio: CGFloat
    let heightRatio: CGFloat

    switch screenSize.width {
    case ..<900:
      widthRatio = 0.98
      heightRatio = 0.94
    case ..<1280:
      widthRatio = 0.96
      heightRatio = 0.92
    case ..<1800:
      widthRatio = 0.92
      heightRatio = 0.90
    case ..<2600:
      widthRatio = 0.90
      heightRatio = 0.90
    default:
      widthRatio = 0.88
      heightRatio = 0.90
    }

    let width = min(max(screenSize.width * widthRatio, 760), 3200)
    let height = min(max(screenSize.height * heightRatio, 640), 1440)
    return NSSize(width: width, height: height)
  }
}
