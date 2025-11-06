import XCTest

@testable import SwiftDBus

final class SwiftDBusTests: XCTestCase {
    func testVersionNonZero() throws {
        let (ma, mi, mc) = DBus.version()
        // The real libdbus has major >= 1 these days.
        XCTAssertGreaterThanOrEqual(ma, 1)
        XCTAssertGreaterThanOrEqual(mi, 0)
        XCTAssertGreaterThanOrEqual(mc, 0)
    }
}
