import CDbus
// Tests/SwiftDBusTests/ErrorsAndRAIITests.swift
import XCTest

@testable import SwiftDBus

final class ErrorsAndRAIITests: XCTestCase {

    func testWithDBusError_NoError() throws {
        // Aucun set d'erreur -> ne doit pas throw
        let result: Int = try withDBusError { _ in
            // no-op C calls; just return a value
            42
        }
        XCTAssertEqual(result, 42)
    }

    func testDBusMessageRef_UnrefOnDeinit() throws {
        // Crée un message DBus et vérifie qu'on peut le wrapper
        let msg = try DBusMessageRef.wrapOrThrow(
            dbus_message_new_method_call(nil, "/org/freedesktop/DBus", "org.freedesktop.DBus", "Hello"),
            "dbus_message_new_method_call failed")
        XCTAssertNotNil(msg)
    }

    func testWithDBusError_ForcedError() {
        // C strings statiques (durée de vie globale au process)
        // pour être compatibles avec dbus_set_error_const.
        struct CStr {
            static let name: [CChar] = Array("org.freedesktop.DBus.Error.Failed".utf8CString)
            static let msg: [CChar] = Array("forced".utf8CString)
        }

        do {
            _ = try withDBusError { err in
                CStr.name.withUnsafeBufferPointer { nameBuf in
                    CStr.msg.withUnsafeBufferPointer { msgBuf in
                        dbus_set_error_const(err, nameBuf.baseAddress, msgBuf.baseAddress)
                    }
                }
                return 0
            }
            XCTFail("Expected throw")
        } catch let dbusError as DBusErrorSwift {
            XCTAssertEqual(dbusError.name, "org.freedesktop.DBus.Error.Failed")
            XCTAssertEqual(dbusError.message, "forced")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

}
