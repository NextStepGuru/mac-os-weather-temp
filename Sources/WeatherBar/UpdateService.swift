import Foundation

struct ReleaseInfo: Equatable, Sendable {
    let tag: String
    let zipURL: URL
}

enum VersionComparator {
    static func normalized(_ version: String) -> String {
        version.hasPrefix("v") ? String(version.dropFirst()) : version
    }

    static func isNewer(latest: String, than current: String) -> Bool {
        let latestParts = parse(normalized(latest))
        let currentParts = parse(normalized(current))

        guard !latestParts.isEmpty, !currentParts.isEmpty else { return false }

        let maxCount = max(latestParts.count, currentParts.count)
        for index in 0..<maxCount {
            let latestValue = index < latestParts.count ? latestParts[index] : 0
            let currentValue = index < currentParts.count ? currentParts[index] : 0
            if latestValue != currentValue {
                return latestValue > currentValue
            }
        }

        return false
    }

    private static func parse(_ version: String) -> [Int] {
        version
            .split(separator: ".", omittingEmptySubsequences: false)
            .prefix(3)
            .compactMap { Int($0) }
    }
}

enum ReleaseParser {
    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    static func parseLatestRelease(from data: Data) -> ReleaseInfo? {
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            return nil
        }

        guard let zipAsset = release.assets.first(where: { $0.browserDownloadURL.pathExtension == "zip" }) else {
            return nil
        }

        return ReleaseInfo(tag: release.tagName, zipURL: zipAsset.browserDownloadURL)
    }
}

enum UpdateSettings {
    static let lastUpdateCheckKey = "lastUpdateCheck"
    static let automaticUpdatesKey = "automaticUpdatesEnabled"
    static let defaultCheckInterval: TimeInterval = 24 * 60 * 60
}

final class UpdateService: @unchecked Sendable {
    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/NextStepGuru/mac-os-weather-temp/releases/latest"
    )!
    private static let userAgent = "WeatherBar/1.0 (com.weatherbar.app)"

    private let session: URLSession
    private let bundle: Bundle
    private let userDefaults: UserDefaults
    private let fileManager: FileManager

    init(
        session: URLSession = .configured,
        bundle: Bundle = .main,
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.session = session
        self.bundle = bundle
        self.userDefaults = userDefaults
        self.fileManager = fileManager
    }

    func setAutomaticUpdatesEnabled(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: UpdateSettings.automaticUpdatesKey)
    }

    var isAutomaticUpdatesEnabled: Bool {
        if userDefaults.object(forKey: UpdateSettings.automaticUpdatesKey) == nil {
            return true
        }
        return userDefaults.bool(forKey: UpdateSettings.automaticUpdatesKey)
    }

    func shouldCheckForUpdate(
        throttleInterval: TimeInterval = UpdateSettings.defaultCheckInterval,
        now: Date = Date()
    ) -> Bool {
        guard let lastCheck = userDefaults.object(forKey: UpdateSettings.lastUpdateCheckKey) as? Date else {
            return true
        }
        return now.timeIntervalSince(lastCheck) >= throttleInterval
    }

    func recordUpdateCheck(at date: Date = Date()) {
        userDefaults.set(date, forKey: UpdateSettings.lastUpdateCheckKey)
    }

    func currentVersion() -> String? {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    func canSelfInstall() -> Bool {
        let bundlePath = bundle.bundlePath
        guard bundlePath.hasSuffix(".app") else { return false }
        let parentDirectory = (bundlePath as NSString).deletingLastPathComponent
        return fileManager.isWritableFile(atPath: parentDirectory)
    }

    func checkForUpdate() async throws -> ReleaseInfo? {
        let data = try await request(url: Self.latestReleaseURL)
        guard let release = ReleaseParser.parseLatestRelease(from: data) else {
            throw URLError(.cannotParseResponse)
        }

        guard let current = currentVersion() else {
            return release
        }

        guard VersionComparator.isNewer(latest: release.tag, than: current) else {
            return nil
        }

        return release
    }

    func downloadAndInstall(_ release: ReleaseInfo) async throws {
        guard canSelfInstall() else {
            throw UpdateError.cannotSelfInstall
        }

        let bundlePath = bundle.bundlePath
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(
            "WeatherBarUpdate-\(UUID().uuidString)",
            isDirectory: true
        )
        let zipURL = tempRoot.appendingPathComponent("WeatherBar.zip")
        let extractURL = tempRoot.appendingPathComponent("extracted", isDirectory: true)

        defer {
            try? fileManager.removeItem(at: tempRoot)
        }

        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: extractURL, withIntermediateDirectories: true)

        AppLogger.shared.log("Downloading update \(release.tag)")
        let zipData = try await download(url: release.zipURL)
        try zipData.write(to: zipURL, options: .atomic)

        AppLogger.shared.log("Extracting update archive")
        try runProcess(executable: "/usr/bin/ditto", arguments: ["-x", "-k", zipURL.path, extractURL.path])

        let extractedAppURL = try locateAppBundle(in: extractURL)
        try runProcess(
            executable: "/usr/bin/xattr",
            arguments: ["-dr", "com.apple.quarantine", extractedAppURL.path]
        )

        AppLogger.shared.log("Scheduling install of \(release.tag)")
        try scheduleInstallAndRelaunch(sourceAppURL: extractedAppURL, targetAppPath: bundlePath)
    }

    private func request(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            AppLogger.shared.log(
                "Update check failed: HTTP \(httpResponse.statusCode)",
                level: .error
            )
            throw URLError(.badServerResponse)
        }

        return data
    }

    private func download(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            AppLogger.shared.log(
                "Update download failed: HTTP \(httpResponse.statusCode)",
                level: .error
            )
            throw URLError(.badServerResponse)
        }

        return data
    }

    private func locateAppBundle(in directory: URL) throws -> URL {
        if directory.pathExtension == "app" {
            return directory
        }

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        if let appURL = contents.first(where: { $0.pathExtension == "app" }) {
            return appURL
        }

        for item in contents {
            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

            if let nestedApp = try? locateAppBundle(in: item) {
                return nestedApp
            }
        }

        throw UpdateError.appBundleNotFound
    }

    private func scheduleInstallAndRelaunch(sourceAppURL: URL, targetAppPath: String) throws {
        let scriptURL = fileManager.temporaryDirectory.appendingPathComponent(
            "WeatherBarInstall-\(UUID().uuidString).sh"
        )

        let script = """
        #!/bin/bash
        set -euo pipefail
        PID="$1"
        TARGET="$2"
        SOURCE="$3"
        while kill -0 "$PID" 2>/dev/null; do
          sleep 0.2
        done
        rm -rf "$TARGET"
        /usr/bin/ditto "$SOURCE" "$TARGET"
        /usr/bin/open "$TARGET"
        rm -f "$0"
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            scriptURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            targetAppPath,
            sourceAppURL.path
        ]
        try process.run()
    }

    private func runProcess(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw UpdateError.commandFailed(executable: executable, status: process.terminationStatus)
        }
    }
}

enum UpdateError: LocalizedError {
    case cannotSelfInstall
    case appBundleNotFound
    case commandFailed(executable: String, status: Int32)

    var errorDescription: String? {
        switch self {
        case .cannotSelfInstall:
            return "WeatherBar cannot replace itself from this location."
        case .appBundleNotFound:
            return "The downloaded update did not contain WeatherBar.app."
        case .commandFailed(let executable, let status):
            return "Command failed (\(executable), exit \(status))."
        }
    }
}
