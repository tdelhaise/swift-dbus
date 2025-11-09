import XCTest

@testable import SwiftDBus

final class DecodeHelpersTests: XCTestCase {

    func testTupleDecodingConsumesValues() throws {
        var decoder = DBusDecoder(values: [.string("foo"), .int32(42)])
        let tuple = try DBusTuple2<String, Int32>(from: &decoder)
        XCTAssertTrue(decoder.isAtEnd, "Tuple decoding should consume all values")
        XCTAssertEqual(tuple.value.0, "foo")
        XCTAssertEqual(tuple.value.1, 42)
    }

    func testTupleSupportsNestedReturnTypes() throws {
        struct Compound: DBusReturnDecodable, Equatable {
            let names: [String]
            let flag: Bool

            init(from decoder: inout DBusDecoder) throws {
                let tuple = try decoder.decode(DBusTuple2<[String], Bool>.self)
                self.names = tuple.first
                self.flag = tuple.second
            }

            init(names: [String], flag: Bool) {
                self.names = names
                self.flag = flag
            }
        }

        var decoder = DBusDecoder(values: [.stringArray(["a", "b"]), .bool(true)])
        let value = try Compound(from: &decoder)
        XCTAssertEqual(value, Compound(names: ["a", "b"], flag: true))
    }
}
