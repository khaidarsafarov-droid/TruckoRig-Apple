import XCTest
@testable import TruckoRigDomain

final class OfficeXMLTextTests: XCTestCase {

    func testWordRunsBecomeLines() {
        let xml = """
        <w:document><w:t>Trip ID: T-1</w:t><w:t>Total Rate: 100</w:t></w:document>
        """
        XCTAssertEqual(OfficeXMLText.plainText(xml: xml), "Trip ID: T-1\nTotal Rate: 100")
    }

    func testExcelSharedStringsAreDecoded() {
        let xml = #"<sst><si><t>Garner &amp; Co</t></si></sst>"#
        XCTAssertEqual(OfficeXMLText.plainText(xml: xml), "Garner & Co")
    }
}
