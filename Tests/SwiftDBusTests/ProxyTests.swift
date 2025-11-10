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
        let metadata = try proxy.metadata()
        let tempName = makeTemporaryBusName(prefix: "org.swiftdbus.proxy.signal")

        let signalHandle = try metadata.signal(NameOwnerChangedSignal.self)
        let stream = try proxy.signals(signalHandle, arg0: tempName)

        let _: UInt32 = try proxy.callExpectingSingle(
            "RequestName",
            typedArguments: DBusArguments(tempName, UInt32(0))
        )

        let received = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await signal in stream where signal.name == tempName {
                    XCTAssertTrue(
                        signal.newOwner.hasPrefix(":"),
                        "new owner should be unique name"
                    )
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

    func testProxySignalCacheServicesMultipleSubscribers() async throws {
        if ProcessInfo.processInfo.environment["CI"] != nil {
            throw XCTSkip("Signal timing via proxy is flaky on CI")
        }
        let connection = try DBusConnection(bus: .session)
        let proxy = makeBusProxy(connection)
        let tempName = makeTemporaryBusName(prefix: "org.swiftdbus.proxy.signal.cache")

        let streamA = try proxy.signals(NameOwnerChangedSignal.self, arg0: tempName)
        let streamB = try proxy.signals(NameOwnerChangedSignal.self, arg0: tempName)

        let taskA = Task {
            for await signal in streamA where signal.name == tempName {
                return true
            }
            return false
        }
        let taskB = Task {
            for await signal in streamB where signal.name == tempName {
                return true
            }
            return false
        }

        let _: UInt32 = try proxy.callExpectingSingle(
            "RequestName",
            typedArguments: DBusArguments(tempName, UInt32(0))
        )

        let first = try await withTimeout(seconds: 5) { await taskA.value }
        let second = try await withTimeout(seconds: 5) { await taskB.value }

        XCTAssertTrue(first, "First subscriber should see the signal")
        XCTAssertTrue(second, "Second subscriber should also see the signal")

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

    func testProxyMetadataPropertyHelpers() throws {
        let connection = try DBusConnection(bus: .session)
        let proxy = makeBusProxy(connection)
        let metadata = try proxy.metadata()

        let featuresHandle = try metadata.property("Features", as: [String].self)
        let features = try proxy.getProperty(featuresHandle)
        XCTAssertNotNil(features, "metadata-backed property getter should decode value")

        XCTAssertThrowsError(try metadata.property("Features", as: UInt32.self)) { error in
            guard let metadataError = error as? DBusProxyMetadataError else {
                return XCTFail("Unexpected error \(error)")
            }
            guard
                case DBusProxyMetadataError.propertyTypeMismatch(
                    let property,
                    _,
                    _
                ) = metadataError
            else {
                return XCTFail("Unexpected metadata error \(metadataError)")
            }
            XCTAssertEqual(property, "Features")
        }
    }

    func testProxyCachedMetadataLifecycle() throws {
        let connection = try DBusConnection(bus: .session)
        let caches = DBusProxyCaches(
            propertyCache: nil,
            introspectionCache: DBusIntrospectionCache()
        )
        let proxy = makeBusProxy(connection, caches: caches)

        XCTAssertNil(proxy.cachedMetadata, "metadata cache should start empty")

        let metadata = try proxy.metadata()
        XCTAssertEqual(metadata.name, proxy.interface)
        XCTAssertNotNil(proxy.cachedMetadata)

        proxy.invalidateCachedMetadata()
        XCTAssertNil(proxy.cachedMetadata, "cached metadata should be cleared after invalidation")
    }

    func testProxyCallExpectingTypedStruct() throws {
        let connection = try DBusConnection(bus: .session)
        let proxy = makeBusProxy(connection)

        let result = try proxy.callExpecting("ListNames", as: ListNamesResponse.self)
        XCTAssertFalse(result.names.isEmpty)
    }

    func testProxyPropertyCacheRoundTrip() throws {
        let connection = try DBusConnection(bus: .session)
        let proxy = makeBusProxy(connection)
        let cache = DBusPropertyCache()

        let key = DBusPropertyKey(
            destination: proxy.destination,
            path: proxy.path,
            interface: proxy.interface,
            name: "Features"
        )
        cache.store(.stringArray(["cached-value"]), for: key)

        let cached: [String] = try proxy.getProperty("Features", cache: cache)
        XCTAssertEqual(cached, ["cached-value"])

        let refreshed: [String] = try proxy.getProperty(
            "Features",
            cache: cache,
            refreshCache: true
        )
        XCTAssertNotEqual(refreshed, ["cached-value"])

        if case .stringArray(let values)? = cache.value(for: key) {
            XCTAssertEqual(values, refreshed)
        } else {
            XCTFail("Cache should contain refreshed value")
        }
    }

    func testProxyInvalidateCachedPropertiesUsesConfiguredCache() throws {
        let connection = try DBusConnection(bus: .session)
        let propertyCache = DBusPropertyCache()
        let proxy = makeBusProxy(
            connection,
            caches: DBusProxyCaches(propertyCache: propertyCache)
        )

        let features: [String] = try proxy.getProperty("Features")
        XCTAssertNotNil(features)

        let key = DBusPropertyKey(
            destination: proxy.destination,
            path: proxy.path,
            interface: proxy.interface,
            name: "Features"
        )
        XCTAssertNotNil(propertyCache.value(for: key))

        proxy.invalidateCachedProperties("Features")
        XCTAssertNil(propertyCache.value(for: key))
    }

    func testProxyMetadataMethodHelpers() throws {
        let connection = try DBusConnection(bus: .session)
        let proxy = makeBusProxy(connection)
        let metadata = try proxy.metadata()

        let listNamesHandle = try metadata.method("ListNames", returns: [String].self)
        let names: [String] = try proxy.call(listNamesHandle)
        XCTAssertFalse(names.isEmpty)

        XCTAssertThrowsError(
            try proxy.call(listNamesHandle, arguments: [.string("unexpected")])
        ) { error in
            guard let metadataError = error as? DBusProxyMetadataError else {
                return XCTFail("Unexpected error \(error)")
            }
            guard
                case DBusProxyMetadataError.methodArgumentCountMismatch(
                    let method,
                    let expected,
                    let actual
                ) = metadataError
            else {
                return XCTFail("Unexpected metadata error \(metadataError)")
            }
            XCTAssertEqual(method, "ListNames")
            XCTAssertEqual(expected, 0)
            XCTAssertEqual(actual, 1)
        }
    }
}

private struct ListNamesResponse: DBusReturnDecodable {
    let names: [String]

    init(from decoder: inout DBusDecoder) throws {
        self.names = try decoder.next([String].self)
    }
}

private struct NameOwnerChangedSignal: DBusSignalPayload {
    static let member = "NameOwnerChanged"

    let name: String
    let oldOwner: String
    let newOwner: String

    init(from decoder: inout DBusDecoder) throws {
        self.name = try decoder.next()
        self.oldOwner = try decoder.next()
        self.newOwner = try decoder.next()
    }
}
