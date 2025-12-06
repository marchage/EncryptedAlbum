import XCTest
@testable import EncryptedAlbum

final class ColorContrastTests: XCTestCase {
    func testYellowChoosesBlack() {
        let textColor = Color.yellow.idealTextColorAgainstBackground()
        XCTAssertEqual(textColor, Color.black)
    }

    func testWhiteChoosesBlack() {
        let textColor = Color.white.idealTextColorAgainstBackground()
        XCTAssertEqual(textColor, Color.black)
    }

    func testBlackChoosesWhite() {
        let textColor = Color.black.idealTextColorAgainstBackground()
        XCTAssertEqual(textColor, Color.white)
    }

    func testBlueChoosesWhite() {
        let textColor = Color.blue.idealTextColorAgainstBackground()
        XCTAssertEqual(textColor, Color.white)
    }
}
