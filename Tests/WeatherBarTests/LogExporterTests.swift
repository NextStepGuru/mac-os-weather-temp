import Foundation
import Testing
@testable import WeatherBar

struct LogExporterTests {
    @Test func fileNameIncludesDateAndLogExtension() {
        let name = LogExporter.fileName(date: Date())
        #expect(name.hasPrefix("weatherbar-"))
        #expect(name.hasSuffix(".log"))

        let datePart = name.dropFirst("weatherbar-".count).dropLast(".log".count)
        #expect(datePart.count == 10)
        #expect(datePart.filter { $0 == "-" }.count == 2)
    }

    @Test func writePersistsContents() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeatherBarLogExportTests-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }

        try LogExporter.write("[INFO] test entry", to: url)

        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents == "[INFO] test entry")
    }
}
