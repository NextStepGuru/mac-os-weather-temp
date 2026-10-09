import Foundation
import Testing
@testable import WeatherBar

struct UpdateInstallScriptTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeatherBarInstallTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The script waits for this PID to exit; a freshly-exited process satisfies
    /// `kill -0` failing immediately.
    private func exitedProcessIdentifier() throws -> pid_t {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        return process.processIdentifier
    }

    @discardableResult
    private func runScript(
        _ script: String,
        pid: pid_t,
        target: URL,
        source: URL,
        staging: URL
    ) throws -> Int32 {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeatherBarInstallTests-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path, String(pid), target.path, source.path, staging.path]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    @Test func scriptSwapsAppBundleAndCleansUp() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let staging = root.appendingPathComponent("staging", isDirectory: true)
        let source = staging.appendingPathComponent("WeatherBar.app", isDirectory: true)
        let target = root.appendingPathComponent("WeatherBar.app", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try "new".write(to: source.appendingPathComponent("version"), atomically: true, encoding: .utf8)
        try "old".write(to: target.appendingPathComponent("version"), atomically: true, encoding: .utf8)

        let pid = try exitedProcessIdentifier()
        let status = try runScript(
            UpdateInstallScript.body(openCommand: "/usr/bin/true"),
            pid: pid,
            target: target,
            source: source,
            staging: staging
        )

        #expect(status == 0)
        let version = try String(contentsOf: target.appendingPathComponent("version"), encoding: .utf8)
        #expect(version == "new")
        #expect(!FileManager.default.fileExists(atPath: staging.path))

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0 != "WeatherBar.app" }
        #expect(leftovers.isEmpty)
    }

    @Test func scriptKeepsInstalledAppWhenSourceIsMissing() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let staging = root.appendingPathComponent("staging", isDirectory: true)
        let source = staging.appendingPathComponent("WeatherBar.app", isDirectory: true)
        let target = root.appendingPathComponent("WeatherBar.app", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try "old".write(to: target.appendingPathComponent("version"), atomically: true, encoding: .utf8)

        let pid = try exitedProcessIdentifier()
        let status = try runScript(
            UpdateInstallScript.body(openCommand: "/usr/bin/true"),
            pid: pid,
            target: target,
            source: source,
            staging: staging
        )

        #expect(status == 1)
        let version = try String(contentsOf: target.appendingPathComponent("version"), encoding: .utf8)
        #expect(version == "old")
        #expect(!FileManager.default.fileExists(atPath: staging.path))
    }
}
