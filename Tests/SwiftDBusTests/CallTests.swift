// Tests/SwiftDBusTests/CallTests.swift
import XCTest

@testable import SwiftDBus

final class CallTests: XCTestCase {

    func testGetBusIdReturnsString() throws {
        let conn = try DBusConnection(bus: .session)
        let id = try conn.getBusId()
        XCTAssertFalse(id.isEmpty, "Bus ID should be non-empty")
        // Bus ID ressemble à une UUID en hex/dashes; ne figeons pas le format, juste non-vide.
    }

    func testPeerPing() throws {
        let conn = try DBusConnection(bus: .session)
        XCTAssertNoThrow(try conn.pingPeer())
    }
}
