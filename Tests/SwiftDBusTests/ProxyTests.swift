import XCTest

@testable import SwiftDBus

final class ProxyTests: XCTestCase {

    func testProxyCallReturnsBusId() throws {
        let connection = try DBusConnection(bus: .session)
        let proxy = DBusProxy(
            connection: connection,
            destination: "org.freedesktop.DBus",
            path: "/org/freedesktop/DBus",
            interface: "org.freedesktop.DBus"
        )

        let busId = try proxy.callExpectingFirstString("GetId")
        XCTAssertFalse(busId.isEmpty)
    }

    func testProxyGetNameOwnerWithArguments() throws {
        let connection = try DBusConnection(bus: .session)
        let proxy = DBusProxy(
            connection: connection,
            destination: "org.freedesktop.DBus",
            path: "/org/freedesktop/DBus",
            interface: "org.freedesktop.DBus"
        )

        let owner = try proxy.callExpectingFirstString(
            "GetNameOwner",
            arguments: [.string("org.freedesktop.DBus")]
        )
        XCTAssertTrue(owner.hasPrefix("org.freedesktop.DBus") || owner.hasPrefix(":"))
    }

    func testProxySignalsForwarded() async throws {
        let connection = try DBusConnection(bus: .session)
        let proxy = DBusProxy(
            connection: connection,
            destination: "org.freedesktop.DBus",
            path: "/org/freedesktop/DBus",
            interface: "org.freedesktop.DBus"
        )

        let tempName = makeTemporaryBusName(prefix: "org.swiftdbus.proxytest")
        let stream = try proxy.signals(member: "NameOwnerChanged", arg0: tempName)

        let expectation = XCTestExpectation(description: "proxy signal delivered")
        let consumer = Task {
            for await signal in stream {
                guard signal.member == "NameOwnerChanged" else { continue }
                if case .string(let name)? = signal.args.first, name == tempName {
                    expectation.fulfill()
                    break
                }
            }
        }

        _ = try connection.requestName(tempName)
        await fulfillment(of: [expectation], timeout: 3.0)
        _ = try connection.releaseName(tempName)

        consumer.cancel()
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    func testProxyGetPropertyFeatures() throws {
        let connection = try DBusConnection(bus: .session)
        let proxy = DBusProxy(
            connection: connection,
            destination: "org.freedesktop.DBus",
            path: "/org/freedesktop/DBus",
            interface: "org.freedesktop.DBus"
        )

        let value = try proxy.getProperty("Features")
        guard case .stringArray(let features) = value else {
            XCTFail("Expected string array for Features property")
            return
        }
        XCTAssertFalse(features.isEmpty)
    }

    func testProxyGetAllPropertiesContainsFeatures() throws {
        let connection = try DBusConnection(bus: .session)
        let proxy = DBusProxy(
            connection: connection,
            destination: "org.freedesktop.DBus",
            path: "/org/freedesktop/DBus",
            interface: "org.freedesktop.DBus"
        )

        let properties = try proxy.getAllProperties()
        guard case .stringArray(let features)? = properties["Features"] else {
            XCTFail("Expected Features property in GetAll")
            return
        }
        XCTAssertFalse(features.isEmpty)
    }
}
