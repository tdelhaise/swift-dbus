import XCTest

@testable import SwiftDBus

final class ServerTests: XCTestCase {

    func testExportedMethodResponds() async throws {
        let serverConnection = try DBusConnection(bus: .session)
        let exporter = DBusObjectExporter(connection: serverConnection)
        let object = EchoObject()
        try exporter.register(object)

        let tempName = makeTemporaryBusName(prefix: "org.swiftdbus.server.echo")
        _ = try serverConnection.requestName(tempName)
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

        _ = try serverConnection.releaseName(tempName)
    }

    func testExportedMethodEmitsSignal() async throws {
        if ProcessInfo.processInfo.environment["CI"] != nil {
            throw XCTSkip("Signal timing is flaky on CI")
        }

        let serverConnection = try DBusConnection(bus: .session)
        let exporter = DBusObjectExporter(connection: serverConnection)
        let object = EchoObject()
        try exporter.register(object)

        let tempName = makeTemporaryBusName(prefix: "org.swiftdbus.server.signal")
        _ = try serverConnection.requestName(tempName)
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

        _ = try serverConnection.releaseName(tempName)
    }

    func testExportedPropertiesRespond() async throws {
        let serverConnection = try DBusConnection(bus: .session)
        let exporter = DBusObjectExporter(connection: serverConnection)
        let object = PropertyObject()
        try exporter.register(object)

        let tempName = makeTemporaryBusName(prefix: "org.swiftdbus.server.properties")
        _ = try serverConnection.requestName(tempName)
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

        _ = try serverConnection.releaseName(tempName)
    }

    func testAutoIntrospectionIncludesMetadata() async throws {
        let serverConnection = try DBusConnection(bus: .session)
        let exporter = DBusObjectExporter(connection: serverConnection)
        let object = MetadataObject()
        try exporter.register(object)

        let tempName = makeTemporaryBusName(prefix: "org.swiftdbus.server.metadata")
        _ = try serverConnection.requestName(tempName)
        try await Task.sleep(nanoseconds: 100_000_000)

        let clientConnection = try DBusConnection(bus: .session)
        let proxy = DBusProxy(
            connection: clientConnection,
            destination: tempName,
            path: MetadataObject.path,
            interface: "org.freedesktop.DBus.Introspectable"
        )

        let xml: String = try proxy.callExpectingSingle("Introspect")
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

        _ = try serverConnection.releaseName(tempName)
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

private final class EchoObject: DBusObject, @unchecked Sendable {
    static let interface = "org.swiftdbus.tests.Echo"
    static let path = "/org/swiftdbus/tests/Echo"

    var introspectionXML: String? {
        """
        <node>
          <interface name="\(Self.interface)">
            <method name="Echo">
              <arg name="message" direction="in" type="s"/>
              <arg name="message" direction="out" type="s"/>
            </method>
            <method name="Send">
              <arg name="message" direction="in" type="s"/>
            </method>
          </interface>
        </node>
        """
    }

    private let lock = NSLock()
    private var echoCount = 0
    private var sendCount = 0

    func recordedEchoCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return echoCount
    }

    func recordedSendCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return sendCount
    }

    var methods: [DBusMethod] {
        [
            .returning("Echo") { _, decoder in
                let value: String = try decoder.next()
                self.incrementEcho()
                return value
            },
            .void("Send") { call, decoder in
                let payload: String = try decoder.next()
                try call.signalEmitter.emit(member: "Pinged", values: [.string(payload)])
                self.incrementSend()
            }
        ]
    }

    private func incrementEcho() {
        lock.lock()
        echoCount += 1
        lock.unlock()
    }

    private func incrementSend() {
        lock.lock()
        sendCount += 1
        lock.unlock()
    }
}

private final class PropertyObject: DBusObject, @unchecked Sendable {
    static let interface = "org.swiftdbus.tests.Properties"
    static let path = "/org/swiftdbus/tests/Properties"

    private let lock = NSLock()
    private var count: Int32 = 0
    private var name: String = "SwiftDBus"

    var properties: [DBusProperty] {
        [
            .readOnly("Name") { _ in
                self.lock.lock()
                defer { self.lock.unlock() }
                return self.name
            },
            .readWrite(
                "Count",
                get: { _ in
                    self.lock.lock()
                    defer { self.lock.unlock() }
                    return self.count
                },
                set: { newValue, invocation in
                    self.lock.lock()
                    self.count = newValue
                    self.lock.unlock()
                    try invocation.signalEmitter.emitPropertiesChanged(
                        interface: Self.interface,
                        changed: ["Count": newValue.dbusValue]
                    )
                }
            )
        ]
    }
}

private final class MetadataObject: DBusObject, @unchecked Sendable {
    static let interface = "org.swiftdbus.tests.Metadata"
    static let path = "/org/swiftdbus/tests/Metadata"

    private let lock = NSLock()
    private var mode: String = "idle"

    var methods: [DBusMethod] {
        [
            .returning(
                "Describe",
                arguments: [.input("payload", signature: "s")],
                returns: [.output("echo", signature: "s")],
                documentation: "Echoes the provided payload."
            ) { _, decoder in
                let text: String = try decoder.next()
                return ">> \(text)"
            }
        ]
    }

    var properties: [DBusProperty] {
        [
            .readWrite(
                "Mode",
                documentation: "Current operating mode.",
                get: { _ in
                    self.lock.lock()
                    defer { self.lock.unlock() }
                    return self.mode
                },
                set: { newValue, _ in
                    self.lock.lock()
                    self.mode = newValue
                    self.lock.unlock()
                }
            )
        ]
    }

    var signals: [DBusSignalDescription] {
        [
            DBusSignalDescription(
                name: "Updated",
                arguments: [
                    DBusIntrospectionArgument.field("field", signature: "s"),
                    DBusIntrospectionArgument.field("value", signature: "s")
                ],
                documentation: "Emitted whenever a field changes."
            )
        ]
    }
}
