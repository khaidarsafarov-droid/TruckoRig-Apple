import XCTest
@testable import TruckoRig

/// Page cap, text cap, a text-layer PDF, and a file whose header is not an allowed image.
final class SharePayloadReaderTests: XCTestCase {

    func testTextLayerPDFIsReadAsText() async throws {
        let bytes = try fixture("text-layer.pdf")
        let pdf = await SharePayloadReader.pdfText(bytes)
        XCTAssertEqual(pdf.pages, 1)
        XCTAssertGreaterThanOrEqual(pdf.text.count, 40)
        XCTAssertTrue(pdf.text.contains("Garner"))
        XCTAssertTrue(pdf.text.contains("2500"))
    }

    func testPDFTextStopsAtThePageCap() async throws {
        let bytes = try fixture("thirty-one-pages.pdf")
        let pdf = await SharePayloadReader.pdfText(bytes)
        XCTAssertEqual(pdf.pages, ShareFileRules.maxPages)
        XCTAssertEqual(pdf.pages, 30)
        XCTAssertTrue(pdf.text.contains("PAGE01"))
        XCTAssertFalse(pdf.text.contains("PAGE31ONLY"))
    }

    func testPDFTextHonorsTheTextLimit() async throws {
        let bytes = try fixture("long-text.pdf")
        let pdf = await SharePayloadReader.pdfText(bytes)
        XCTAssertEqual(SharePayloadReader.textLimit, ShareFileRules.maxText)
        XCTAssertEqual(pdf.text.count, SharePayloadReader.textLimit)
        XCTAssertFalse(pdf.text.contains("ENDMARKER"))
    }

    func testRejectedImageIsRefused() throws {
        let url = try fixtureURL("rejected.jpg")
        XCTAssertThrowsError(try SharePayloadReader.storedFile(at: url)) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .fileReadCorruptFile)
        }
    }

    func testJPEGHeaderIsAccepted() throws {
        let url = try fixtureURL("pixel.jpg")
        let file = try SharePayloadReader.storedFile(at: url)
        XCTAssertEqual(file.name, "pixel.jpg")
        XCTAssertTrue(file.bytes.starts(with: Data([0xFF, 0xD8, 0xFF])))
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: fixtureURL(name))
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let bundle = Bundle(for: SharePayloadReaderTests.self)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        return try XCTUnwrap(bundle.url(forResource: base, withExtension: ext))
    }
}
