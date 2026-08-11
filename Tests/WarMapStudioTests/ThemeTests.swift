import SwiftUI
import XCTest
@testable import WarMapStudio

final class ThemeTests: XCTestCase {

    func testHexStringParsesSixDigitColour() {
        XCTAssertNotNil(Color(hexString: "#C9A227"))
        XCTAssertNotNil(Color(hexString: "C9A227"))
    }

    func testHexStringParsesEightDigitColourWithAlpha() {
        XCTAssertNotNil(Color(hexString: "C9A22780"))
    }

    func testHexStringRejectsMalformedInput() {
        XCTAssertNil(Color(hexString: "C9A2"))
        XCTAssertNil(Color(hexString: "not-a-colour"))
        XCTAssertNil(Color(hexString: ""))
    }
}
