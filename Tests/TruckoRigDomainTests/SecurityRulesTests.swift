import XCTest
@testable import TruckoRigDomain

final class SecurityRulesTests: XCTestCase {
    func testShareFileRulesAcceptKnownTypesAndRefuseMismatches() {
        let pdf = Data("%PDF-1.7\n".utf8)
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertEqual(ShareFileRules.storedExtension(pathExtension: "pdf", header: pdf), "pdf")
        XCTAssertEqual(ShareFileRules.storedExtension(pathExtension: "jpeg", header: jpeg), "jpg")
        XCTAssertEqual(ShareFileRules.storedExtension(pathExtension: "PNG", header: png), "png")
        XCTAssertEqual(ShareFileRules.storedExtension(pathExtension: "", header: pdf), "pdf")
        XCTAssertNil(ShareFileRules.storedExtension(pathExtension: "pdf", header: jpeg))
        XCTAssertNil(ShareFileRules.storedExtension(pathExtension: "exe", header: pdf))
        XCTAssertNil(ShareFileRules.storedExtension(pathExtension: "txt", header: Data("hello".utf8)))
        XCTAssertEqual(ShareFileRules.maxBytes, 20 * 1024 * 1024)
        XCTAssertEqual(ShareFileRules.maxPages, 30)
    }

    func testMediaPathsStayInsideTheRoot() throws {
        let root = URL(fileURLWithPath: "/tmp/truckorig-media", isDirectory: true)
        XCTAssertEqual(MediaPathRules.fileName("a.jpg"), "a.jpg")
        XCTAssertNil(MediaPathRules.fileName("../a.jpg"))
        XCTAssertNil(MediaPathRules.fileName("photos/a.jpg"))
        XCTAssertNil(MediaPathRules.fileName("/tmp/a.jpg"))
        let nested = try XCTUnwrap(MediaPathRules.url(relative: "photos/a.jpg", under: root))
        XCTAssertTrue(nested.path.hasPrefix(root.path))
        XCTAssertNil(MediaPathRules.url(relative: "../secret", under: root))
        XCTAssertNil(MediaPathRules.url(relative: "/etc/passwd", under: root))
        XCTAssertNil(MediaPathRules.url(relative: "photos/../../secret", under: root))
    }

    func testInboxSweepRemovesStaleRowsAndOrphanFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = ShareImportInbox(root: root.appendingPathComponent("inbox", isDirectory: true))
        let source = root.appendingPathComponent("page.pdf")
        try Data("%PDF-1.4".utf8).write(to: source)
        let fields = ShareLoadFields(
            tripId: "NW-1",
            broker: "Northwind",
            origin: "Dallas, TX",
            destination: "Atlanta, GA",
            pickupDate: nil,
            deliveryDate: nil,
            rate: 1000,
            miles: 100,
            missing: [],
            score: 80
        )
        var record = ShareImportRecord(sourceText: "demo", originalFileName: "page.pdf", load: fields)
        record.createdAt = Date().addingTimeInterval(-(ShareFileRules.staleInterval + 60))
        let stored = try inbox.enqueue(record, file: source)
        let files = inbox.root.appendingPathComponent("files", isDirectory: true)
        let orphan = files.appendingPathComponent("orphan.bin")
        try Data("leftover".utf8).write(to: orphan)
        inbox.sweep()
        XCTAssertTrue(try inbox.pending().isEmpty)
        XCTAssertNil(inbox.fileURL(for: stored))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }
}
