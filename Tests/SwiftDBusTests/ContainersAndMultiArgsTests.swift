import XCTest

@testable import SwiftDBus

final class ContainersAndMultiArgsTests: XCTestCase {
    func testListNamesReturnsArrayOfStrings() throws {
        let connection = try DBusConnection(bus: .session)
        let names = try connection.listNames()
        XCTAssertFalse(names.isEmpty, "ListNames() should return at least one name")
        XCTAssertTrue(
            names.contains("org.freedesktop.DBus"),
            "ListNames() should contain well-known 'org.freedesktop.DBus'"
        )
    }

    func testMultiArgumentBuilderAppendsTwoArgs() throws {
        // Construction multi-arguments (sans envoi).
        let message = try DBusMessageBuilder.methodCall(
            destination: "org.freedesktop.DBus",
            path: "/org/freedesktop/DBus",
            interface: "org.freedesktop.DBus",
            method: "GetNameOwner"
        ) { writer in
            try writer.appendString("org.freedesktop.DBus")
            try writer.appendInt32(123)  // argument additionnel pour valider l’API d’append
        }

        XCTAssertNotNil(message.raw)
    }
}
