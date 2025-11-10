import CDbus
import XCTest

@testable import SwiftDBus

final class ServerTests: XCTestCase {

    func testExportedMethodResponds() async throws {
        let serverConnection = try DBusConnection(bus: .session)
        let exporter = DBusObjectExporter(connection: serverConnection)
        let object = EchoObject()
        let tempName = makeTemporaryBusName(prefix: "org.swiftdbus.server.echo")
        let registration = try exporter.register(object, busName: tempName)
        defer { registration.cancel() }

        try await Task.sleep(nanoseconds: 100_000_000)

        let clientConnection = try DBusConnection(bus: .session)
        XCTAssertNotEqual(
            try serverConnection.uniqueName(),
            try clientConnection.uniqueName(),
            "server and client connections should be distinct"
        )
        let proxy = DBusProxy(
            connection: clientConnection,
            destination: tempName,
            path: EchoObject.path,
            interface: EchoObject.interface
        )

        let reply: String = try await withTimeout(seconds: 20) {
            try proxy.callExpectingSingle("Echo", arguments: [.string("ping")])
        }
        XCTAssertEqual(reply, "ping")
        XCTAssertEqual(object.recordedEchoCount(), 1)

        let introspectionProxy = DBusProxy(
            connection: clientConnection,
            destination: tempName,
            path: EchoObject.path,
            interface: "org.freedesktop.DBus.Introspectable"
        )
        let xml: String = try introspectionProxy.callExpectingSingle("Introspect")
        XCTAssertTrue(xml.contains("Echo"), "Introspection should mention Echo method")
    }

    func testExportedMethodEmitsSignal() async throws {
        if ProcessInfo.processInfo.environment["CI"] != nil {
            throw XCTSkip("Signal timing is flaky on CI")
        }

        let serverConnection = try DBusConnection(bus: .session)
        let exporter = DBusObjectExporter(connection: serverConnection)
        let object = EchoObject()
        let tempName = makeTemporaryBusName(prefix: "org.swiftdbus.server.signal")
        let registration = try exporter.register(object, busName: tempName)
        defer { registration.cancel() }

        try await Task.sleep(nanoseconds: 100_000_000)
        let clientConnection = try DBusConnection(bus: .session)

        let stream = try clientConnection.signals(
            matching: DBusMatchRule.signal(
                path: EchoObject.path,
                interface: EchoObject.interface,
                member: "Pinged"
            )
        )

        let received = try await withTimeout(seconds: 20) {
            let proxy = DBusProxy(
                connection: clientConnection,
                destination: tempName,
                path: EchoObject.path,
                interface: EchoObject.interface
            )
            _ =
                try? proxy.callExpectingSingle(
                    "Send",
                    arguments: [.string("payload")]
                ) as String

            for await signal in stream {
                if case .string(let value)? = signal.args.first, value == "payload" {
                    return true
                }
            }
            return false
        }

        XCTAssertTrue(received, "Expected signal to be observed")
        XCTAssertEqual(object.recordedSendCount(), 1)
    }

    func testExportedPropertiesRespond() async throws {
        let serverConnection = try DBusConnection(bus: .session)
        let exporter = DBusObjectExporter(connection: serverConnection)
        let object = PropertyObject()
        let tempName = makeTemporaryBusName(prefix: "org.swiftdbus.server.properties")
        let registration = try exporter.register(object, busName: tempName)
        defer { registration.cancel() }

        try await Task.sleep(nanoseconds: 100_000_000)

        let clientConnection = try DBusConnection(bus: .session)

        let proxy = DBusProxy(
            connection: clientConnection,
            destination: tempName,
            path: PropertyObject.path,
            interface: PropertyObject.interface
        )

        let initial: Int32 = try proxy.getProperty("Count")
        XCTAssertEqual(initial, 0)

        let propertiesSignals = try clientConnection.signals(
            matching: DBusMatchRule.signal(
                path: PropertyObject.path,
                interface: "org.freedesktop.DBus.Properties",
                member: "PropertiesChanged"
            )
        )
        let signalTask = Task {
            for await _ in propertiesSignals {
                return true
            }
            return false
        }

        try proxy.setProperty("Count", value: Int32(5))
        let signalReceived = try await withTimeout(seconds: 20) {
            await signalTask.value
        }
        XCTAssertTrue(signalReceived)

        let updated: Int32 = try proxy.getProperty("Count")
        XCTAssertEqual(updated, 5)

        let name: String = try proxy.getProperty("Name")
        XCTAssertEqual(name, "SwiftDBus")

        let all = try proxy.getAllProperties()
        XCTAssertEqual(all["Name"], .string("SwiftDBus"))

        let cache = DBusPropertyCache()
        let cachedCount: Int32 = try proxy.getProperty("Count", cache: cache)
        XCTAssertEqual(cachedCount, 5)
        let subscription = try proxy.autoInvalidatePropertyCache(cache)

        try proxy.setProperty("Count", value: Int32(9))
        let key = DBusPropertyKey(
            destination: tempName,
            path: PropertyObject.path,
            interface: PropertyObject.interface,
            name: "Count"
        )
        let invalidated = try await withTimeout(seconds: 20) {
            while cache.value(for: key) != nil {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            return true
        }
        XCTAssertTrue(invalidated, "Cache should be cleared when PropertiesChanged fires")

        subscription.cancel()

        let introspectionProxy = DBusProxy(
            connection: clientConnection,
            destination: tempName,
            path: PropertyObject.path,
            interface: "org.freedesktop.DBus.Introspectable"
        )
        let xml: String = try introspectionProxy.callExpectingSingle("Introspect")
        XCTAssertTrue(
            xml.contains("property name=\"Name\""),
            "Generated introspection should list properties"
        )
    }

    func testAutoIntrospectionIncludesMetadata() async throws {
        let serverConnection = try DBusConnection(bus: .session)
        let exporter = DBusObjectExporter(connection: serverConnection)
        let object = MetadataObject()
        let tempName = makeTemporaryBusName(prefix: "org.swiftdbus.server.metadata")
        let registration = try exporter.register(object, busName: tempName)
        defer { registration.cancel() }

        try await Task.sleep(nanoseconds: 100_000_000)

        let clientConnection = try DBusConnection(bus: .session)
        let metadataProxy = DBusProxy(
            connection: clientConnection,
            destination: tempName,
            path: MetadataObject.path,
            interface: MetadataObject.interface
        )
        let introspectionProxy = DBusProxy(
            connection: clientConnection,
            destination: tempName,
            path: MetadataObject.path,
            interface: "org.freedesktop.DBus.Introspectable"
        )

        let xml: String = try introspectionProxy.callExpectingSingle("Introspect")
        XCTAssertTrue(
            xml.contains("<method name=\"Describe\""),
            "Introspection should list Describe method"
        )
        XCTAssertTrue(
            xml.contains("<arg name=\"payload\" direction=\"in\" type=\"s\"/>"),
            "Method args should include payload input"
        )
        XCTAssertTrue(
            xml.contains("<arg name=\"echo\" direction=\"out\" type=\"s\"/>"),
            "Method args should include echo output"
        )
        XCTAssertTrue(
            xml.contains("org.freedesktop.DBus.DocString"),
            "Docstring annotations should be generated"
        )
        XCTAssertTrue(
            xml.contains("<signal name=\"Updated\">"),
            "Signals should be reflected in introspection"
        )

        let interfaceInfo = try metadataProxy.introspectedInterface()
        XCTAssertEqual(interfaceInfo?.methods.first?.name, "Describe")
        XCTAssertEqual(interfaceInfo?.signals.first?.name, "Updated")
        XCTAssertEqual(interfaceInfo?.properties.first?.name, "Mode")
    }

    func testSignalHelperValidatesPayloadCount() throws {
        let connection = try DBusConnection(bus: .session)
        let emitter = DBusSignalEmitter(
            connection: connection,
            path: "/org/swiftdbus/tests/Signals",
            interface: "org.swiftdbus.tests.Signals"
        )
        let description = DBusSignalDescription(
            name: "Mismatch",
            arguments: [.field("value", signature: "s")]
        )
        XCTAssertThrowsError(try emitter.emit(description, values: [])) { error in
            guard case DBusServerError.invalidSignalArguments(let expected, let got) = error else {
                return XCTFail("Unexpected error \(error)")
            }
            XCTAssertEqual(expected, 1)
            XCTAssertEqual(got, 0)
        }
    }

    func testRegistrationManagesBusNameLifecycle() async throws {
        let serverConnection = try DBusConnection(bus: .session)
        let exporter = DBusObjectExporter(connection: serverConnection)
        let object = EchoObject()
        let tempName = makeTemporaryBusName(prefix: "org.swiftdbus.server.busname")

        let registration = try exporter.register(
            object,
            busName: tempName,
            requestNameFlags: UInt32(DBUS_NAME_FLAG_DO_NOT_QUEUE)
        )

        try await Task.sleep(nanoseconds: 100_000_000)

        let competingConnection = try DBusConnection(bus: .session)
        let firstAttempt = try competingConnection.requestName(
            tempName,
            flags: UInt32(DBUS_NAME_FLAG_DO_NOT_QUEUE)
        )
        XCTAssertEqual(firstAttempt, DBUS_REQUEST_NAME_REPLY_EXISTS)

        registration.cancel()

        let secondAttempt = try competingConnection.requestName(
            tempName,
            flags: UInt32(DBUS_NAME_FLAG_DO_NOT_QUEUE)
        )
        XCTAssertEqual(secondAttempt, DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER)
        _ = try competingConnection.releaseName(tempName)
    }

    func testIntrospectionListsMultipleInterfaces() async throws {
        let serverConnection = try DBusConnection(bus: .session)
        let exporter = DBusObjectExporter(connection: serverConnection)
        let tempName = makeTemporaryBusName(prefix: "org.swiftdbus.server.multiInterface")

        let primary = EchoObject()
        let secondary = AuxiliaryInterfaceObject()

        let primaryRegistration = try exporter.register(primary, busName: tempName)
        let secondaryRegistration = try exporter.register(secondary)
        defer {
            secondaryRegistration.cancel()
            primaryRegistration.cancel()
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        let clientConnection = try DBusConnection(bus: .session)
        let introspectionProxy = DBusProxy(
            connection: clientConnection,
            destination: tempName,
            path: EchoObject.path,
            interface: "org.freedesktop.DBus.Introspectable"
        )
        let xml: String = try introspectionProxy.callExpectingSingle("Introspect")
        XCTAssertTrue(xml.contains("interface name=\"\(EchoObject.interface)\""))
        XCTAssertTrue(xml.contains("interface name=\"\(AuxiliaryInterfaceObject.interface)\""))
    }

    func testIntrospectionListsChildNodes() async throws {
        let serverConnection = try DBusConnection(bus: .session)
        let exporter = DBusObjectExporter(connection: serverConnection)
        let tempName = makeTemporaryBusName(prefix: "org.swiftdbus.server.children")

        let parent = EchoObject()
        let child = ChildEchoObject()
        let parentRegistration = try exporter.register(parent, busName: tempName)
        let childRegistration = try exporter.register(child)
        defer {
            childRegistration.cancel()
            parentRegistration.cancel()
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        let clientConnection = try DBusConnection(bus: .session)
        let parentIntrospect = DBusProxy(
            connection: clientConnection,
            destination: tempName,
            path: EchoObject.path,
            interface: "org.freedesktop.DBus.Introspectable"
        )
        let parentXML: String = try parentIntrospect.callExpectingSingle("Introspect")
        XCTAssertTrue(parentXML.contains("<node name=\"Child\"/>"))

        let childIntrospect = DBusProxy(
            connection: clientConnection,
            destination: tempName,
            path: ChildEchoObject.path,
            interface: "org.freedesktop.DBus.Introspectable"
        )
        let childXML: String = try childIntrospect.callExpectingSingle("Introspect")
        XCTAssertFalse(childXML.contains("<node name=\""))
        XCTAssertTrue(childXML.contains("interface name=\"\(ChildEchoObject.interface)\""))
    }

    func testCustomIntrospectionRespectedForSingleObject() async throws {
        let serverConnection = try DBusConnection(bus: .session)
        let exporter = DBusObjectExporter(connection: serverConnection)
        let tempName = makeTemporaryBusName(prefix: "org.swiftdbus.server.custom")
        let customObject = CustomIntrospectionObject()
        let registration = try exporter.register(customObject, busName: tempName)
        defer { registration.cancel() }

        try await Task.sleep(nanoseconds: 100_000_000)

        let clientConnection = try DBusConnection(bus: .session)
        let introspectionProxy = DBusProxy(
            connection: clientConnection,
            destination: tempName,
            path: CustomIntrospectionObject.path,
            interface: "org.freedesktop.DBus.Introspectable"
        )
        let xml: String = try introspectionProxy.callExpectingSingle("Introspect")
        XCTAssertEqual(xml, CustomIntrospectionObject.customXML)
    }

    func testIntrospectionCacheReturnsStaleMetadataAfterUnregister() async throws {
        let serverConnection = try DBusConnection(bus: .session)
        let exporter = DBusObjectExporter(connection: serverConnection)
        let object = MetadataObject()
        let registration = try exporter.register(object)
        defer { registration.cancel() }

        let tempName = makeTemporaryBusName(prefix: "org.swiftdbus.server.metadata.cache")
        _ = try serverConnection.requestName(tempName)
        try await Task.sleep(nanoseconds: 100_000_000)

        let clientConnection = try DBusConnection(bus: .session)
        let metadataProxy = DBusProxy(
            connection: clientConnection,
            destination: tempName,
            path: MetadataObject.path,
            interface: MetadataObject.interface
        )
        let cache = DBusIntrospectionCache()

        let cachedInterface = try metadataProxy.introspectedInterface(cache: cache)
        XCTAssertEqual(cachedInterface?.methods.first?.name, "Describe")

        exporter.unregister(path: MetadataObject.path, interface: MetadataObject.interface)
        _ = try serverConnection.releaseName(tempName)

        XCTAssertThrowsError(try metadataProxy.introspectedInterface(timeoutMS: 100))

        let replay = try metadataProxy.introspectedInterface(cache: cache)
        XCTAssertEqual(replay?.methods.first?.name, "Describe")
    }
}

private struct TestTimeoutError: Error {}

private func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TestTimeoutError()
        }
        guard let result = try await group.next() else {
            throw TestTimeoutError()
        }
        group.cancelAll()
        return result
    }
}
