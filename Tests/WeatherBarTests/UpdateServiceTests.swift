import Foundation
import Testing
@testable import WeatherBar

struct UpdateServiceTests {
    @Test func versionComparatorDetectsNewerRelease() {
        #expect(VersionComparator.isNewer(latest: "1.2.0", than: "1.1.9"))
        #expect(VersionComparator.isNewer(latest: "v1.10.0", than: "1.2.0"))
        #expect(VersionComparator.isNewer(latest: "2.0.0", than: "1.9.9"))
    }

    @Test func versionComparatorRejectsEqualOrOlder() {
        #expect(!VersionComparator.isNewer(latest: "1.2.0", than: "1.2.0"))
        #expect(!VersionComparator.isNewer(latest: "v1.2.0", than: "1.2.0"))
        #expect(!VersionComparator.isNewer(latest: "1.1.0", than: "1.2.0"))
        #expect(!VersionComparator.isNewer(latest: "not-a-version", than: "1.0.0"))
    }

    @Test func releaseParserSelectsZipAsset() throws {
        let data = Data(Fixtures.githubLatestRelease.utf8)
        let release = try #require(ReleaseParser.parseLatestRelease(from: data))

        #expect(release.tag == "v1.2.0")
        #expect(
            release.zipURL.absoluteString ==
                "https://github.com/NextStepGuru/mac-os-weather-temp/releases/download/v1.2.0/WeatherBar-v1.2.0.zip"
        )
    }

    @Test func releaseParserReturnsNilWithoutZipAsset() {
        let body = """
        {
            "tag_name": "v1.2.0",
            "assets": [
                {
                    "browser_download_url": "https://example.com/notes.txt"
                }
            ]
        }
        """
        let release = ReleaseParser.parseLatestRelease(from: Data(body.utf8))
        #expect(release == nil)
    }

    @Test func shouldCheckForUpdateRespectsThrottle() throws {
        let defaults = try makeUserDefaults()
        let service = UpdateService(userDefaults: defaults)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        defaults.set(now.addingTimeInterval(-25 * 60 * 60), forKey: UpdateSettings.lastUpdateCheckKey)
        #expect(service.shouldCheckForUpdate(now: now))

        defaults.set(now.addingTimeInterval(-2 * 60 * 60), forKey: UpdateSettings.lastUpdateCheckKey)
        #expect(!service.shouldCheckForUpdate(now: now))
    }

    @Test func checkForUpdateReturnsNilWhenCurrentVersionMatches() async throws {
        let bundle = try makeTestBundle(shortVersion: "1.2.0")
        let session = MockURLProtocol.makeSession { _ in
            MockURLProtocol.jsonResponse(body: Fixtures.githubLatestRelease)
        }
        let service = UpdateService(session: session, bundle: bundle)

        let release = try await service.checkForUpdate()
        #expect(release == nil)
    }

    @Test func checkForUpdateReturnsReleaseWhenNewer() async throws {
        let bundle = try makeTestBundle(shortVersion: "1.0.0")
        let session = MockURLProtocol.makeSession { _ in
            MockURLProtocol.jsonResponse(body: Fixtures.githubLatestRelease)
        }
        let service = UpdateService(session: session, bundle: bundle)

        let release = try await service.checkForUpdate()
        let expected = try #require(release)

        #expect(expected.tag == "v1.2.0")
        #expect(expected.zipURL.pathExtension == "zip")
    }

    @Test func checkForUpdateThrowsOnHttpError() async throws {
        let bundle = try makeTestBundle(shortVersion: "1.0.0")
        let session = MockURLProtocol.makeSession { _ in
            MockURLProtocol.jsonResponse(statusCode: 503, body: "{}")
        }
        let service = UpdateService(session: session, bundle: bundle)

        await #expect(throws: URLError.self) {
            try await service.checkForUpdate()
        }
    }

    private func makeUserDefaults() throws -> UserDefaults {
        let suiteName = "WeatherBarTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(domain: "WeatherBarTests", code: 1)
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeTestBundle(shortVersion: String) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeatherBarTest-\(UUID().uuidString).bundle", isDirectory: true)
        let contents = root.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)

        let plistURL = contents.appendingPathComponent("Info.plist")
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleShortVersionString</key>
            <string>\(shortVersion)</string>
        </dict>
        </plist>
        """
        try plist.write(to: plistURL, atomically: true, encoding: .utf8)

        guard let bundle = Bundle(url: root) else {
            throw NSError(domain: "WeatherBarTests", code: 2)
        }

        return bundle
    }
}
