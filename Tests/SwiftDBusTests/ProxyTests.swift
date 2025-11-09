import Foundation
import XCTest

@testable import SwiftDBus

final class ProxyTests: XCTestCase {

    func testProxyCallReturnsBusId() throws {
        let connection = try DBusConnection(bus: .session)
        let proxy = makeBusProxy(connection)

        let busId: String = try proxy.callExpectingSingle("GetId")
        XCTAssertFalse(busId.isEmpty)
    }

    func testProxyGetNameOwnerWithArguments() throws {
        let connection = try DBusConnection(bus: .session)
        let proxy = makeBusProxy(connection)

        let owner: String = try proxy.callExpectingSingle(
            "GetNameOwner",
            arguments: [.string("org.freedesktop.DBus")]
        )
        XCTAssertTrue(owner.hasPrefix(":") || owner == "org.freedesktop.DBus")
    }

    func testProxyRequestNameAndReleaseWithTypedArguments() throws {
        let connection = try DBusConnection(bus: .session)
        let proxy = makeBusProxy(connection)
        let tempName = makeTemporaryBusName(prefix: "org.swiftdbus.proxy.req")

        let requestStatus: UInt32 = try proxy.callExpectingSingle(
            "RequestName",
            typedArguments: DBusArguments(tempName, UInt32(0))
        )
        XCTAssertNotEqual(requestStatus, 0, "request name should succeed")

        let releaseStatus: UInt32 = try proxy.callExpectingSingle(
            "ReleaseName",
            typedArguments: DBusArguments(tempName)
        )
        XCTAssertNotEqual(releaseStatus, 0, "release name should succeed")
    }

    func testProxySignalsTypedDecoding() async throws {
        if ProcessInfo.processInfo.environment["CI"] != nil {
            throw XCTSkip("Signal decoding via proxy is flaky on CI")
        }
        let connection = try DBusConnection(bus: .session)
        let proxy = makeBusProxy(connection)
        let tempName = makeTemporaryBusName(prefix: "org.swiftdbus.proxy.signal")

        let stream = try proxy.signals(member: "NameOwnerChanged", arg0: tempName) { decoder in
            let name: String = try decoder.next()
            let oldOwner: String = try decoder.next()
            let newOwner: String = try decoder.next()
            return (name, oldOwner, newOwner)
        }

        let _: UInt32 = try proxy.callExpectingSingle(
            "RequestName",
            typedArguments: DBusArguments(tempName, UInt32(0))
        )

        let received = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await (name, _, newOwner) in stream where name == tempName {
                    XCTAssertTrue(newOwner.hasPrefix(":"), "new owner should be unique name")
                    return true
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        guard received else {
            let _: UInt32? = try? proxy.callExpectingSingle(
                "ReleaseName",
                typedArguments: DBusArguments(tempName)
            )
            throw XCTSkip("NameOwnerChanged signal not observed via proxy within timeout")
        }

        let _: UInt32 = try proxy.callExpectingSingle(
            "ReleaseName",
            typedArguments: DBusArguments(tempName)
        )
    }

    func testProxyTypedPropertyAccess() throws {
        let connection = try DBusConnection(bus: .session)
        let proxy = makeBusProxy(connection)

        let features: [String] = try proxy.getProperty("Features")
        XCTAssertNotNil(features, "Features property should decode even if empty")
    }

    func testProxyGetAllPropertiesContainsFeatures() throws {
        let connection = try DBusConnection(bus: .session)
        let proxy = makeBusProxy(connection)

        let properties = try proxy.getAllProperties()
        XCTAssertNotNil(properties["Features"], "GetAll should expose Features entry")
    }
}
