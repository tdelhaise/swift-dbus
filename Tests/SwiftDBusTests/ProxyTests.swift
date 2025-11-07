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
            arguments: [
                .string(tempName),
                .uint32(0)
            ]
        )
        XCTAssertNotEqual(requestStatus, 0, "request name should succeed")

        let releaseStatus: UInt32 = try proxy.callExpectingSingle(
            "ReleaseName",
            arguments: [.string(tempName)]
        )
        XCTAssertNotEqual(releaseStatus, 0, "release name should succeed")
    }

    func testProxySignalsTypedDecoding() async throws {
        let connection = try DBusConnection(bus: .session)
        let proxy = makeBusProxy(connection)
        let tempName = makeTemporaryBusName(prefix: "org.swiftdbus.proxy.signal")

        let stream = try proxy.signals(member: "NameOwnerChanged", arg0: tempName) { decoder in
            let name: String = try decoder.next()
            let oldOwner: String = try decoder.next()
            let newOwner: String = try decoder.next()
            return (name, oldOwner, newOwner)
        }

        let expectation = XCTestExpectation(description: "typed signal received")

        let consumer = Task {
            for await (name, _, newOwner) in stream where name == tempName {
                XCTAssertTrue(newOwner.hasPrefix(":"), "new owner should be unique name")
                expectation.fulfill()
                break
            }
        }

        let _: UInt32 = try proxy.callExpectingSingle(
            "RequestName",
            arguments: [.string(tempName), .uint32(0)]
        )
        await fulfillment(of: [expectation], timeout: 3.0)
        let _: UInt32 = try proxy.callExpectingSingle(
            "ReleaseName",
            arguments: [.string(tempName)]
        )

        consumer.cancel()
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    func testProxyTypedPropertyAccess() throws {
        let connection = try DBusConnection(bus: .session)
        let proxy = makeBusProxy(connection)

        let features: [String] = try proxy.getProperty("Features")
        XCTAssertFalse(features.isEmpty)
    }

    func testProxyGetAllPropertiesContainsFeatures() throws {
        let connection = try DBusConnection(bus: .session)
        let proxy = makeBusProxy(connection)

        let properties = try proxy.getAllProperties()
        guard case .stringArray(let features)? = properties["Features"] else {
            XCTFail("Expected Features entry in GetAll result")
            return
        }
        XCTAssertFalse(features.isEmpty)
    }
}
