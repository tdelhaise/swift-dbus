// Tests/SwiftDBusTests/ErrorsAndRAIITests.swift
import XCTest
import CDbus
@testable import SwiftDBus

final class ErrorsAndRAIITests: XCTestCase {

    func testWithDBusError_NoError() throws {
        // Aucun set d'erreur -> ne doit pas throw
        let result: Int = try withDBusError { _ in
            // no-op C calls; just return a value
            return 42
        }
        XCTAssertEqual(result, 42)
    }

    func testWithDBusError_ForcedError() {
        // Forcer une erreur avec dbus_set_error
        do {
            _ = try withDBusError { err in
                // DBUS_ERROR_FAILED est une string well-known
                "org.freedesktop.DBus.Error.Failed".withCString { namePtr in
                    "forced".withCString { msgPtr in
                        dbus_set_error(err, namePtr, msgPtr)
                    }
                }
                return 0
            }
            XCTFail("Expected throw")
        } catch let e as DBusErrorSwift {
            XCTAssertEqual(e.name, "org.freedesktop.DBus.Error.Failed")
            XCTAssertEqual(e.message, "forced")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testDBusMessageRef_UnrefOnDeinit() throws {
        // Crée un message DBus et vérifie qu'on peut le wrapper
        let msg = try DBusMessageRef.wrapOrThrow({
            dbus_message_new_method_call(
                // bus name, object path, interface, method
                nil, "/org/freedesktop/DBus", "org.freedesktop.DBus", "Hello"
            )
        }(), "dbus_message_new_method_call failed")
        // rien à faire : si on arrive ici, la création a réussi et unref se fera dans deinit
        XCTAssertNotNil(msg)
    }
}

