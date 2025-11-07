import XCTest

@testable import SwiftDBus

final class MarshalAndCallWithArgsTests: XCTestCase {
    func testGetNameOwner() throws {
        let connection = try DBusConnection(bus: .session)
        let ownerUniqueName = try connection.getNameOwner("org.freedesktop.DBus")

        // Diagnostic utile pour CI
        print("Owner(org.freedesktop.DBus) -> \(ownerUniqueName)")

        // Sur la plupart des bus: nom unique (":…")
        // Sur quelques environnements de test très minimalistes: le nom bien-connu peut être renvoyé.
        let looksLikeUnique = ownerUniqueName.hasPrefix(":")
        let isWellKnownEcho = (ownerUniqueName == "org.freedesktop.DBus")

        XCTAssertTrue(
            looksLikeUnique || isWellKnownEcho,
            "Expected unique name (starts with ':') or well-known echo; got \(ownerUniqueName)"
        )
    }
}
