import Foundation

@testable import SwiftDBus

final class EchoObject: DBusObject, @unchecked Sendable {
    static let interface = "org.swiftdbus.tests.Echo"
    static let path = "/org/swiftdbus/tests/Echo"
    static let pingedSignal = DBusSignalDescription(
        name: "Pinged",
        arguments: [.field("payload", signature: "s")],
        documentation: "Echo object emitted signal."
    )

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
                try call.signalEmitter.emit(Self.pingedSignal) { encoder in
                    encoder.encode(payload)
                }
                self.incrementSend()
            }
        ]
    }

    var signals: [DBusSignalDescription] { [Self.pingedSignal] }

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

final class PropertyObject: DBusObject, @unchecked Sendable {
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

final class MetadataObject: DBusObject, @unchecked Sendable {
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

final class AuxiliaryInterfaceObject: DBusObject, @unchecked Sendable {
    static let interface = "org.swiftdbus.tests.Auxiliary"
    static let path = EchoObject.path

    var methods: [DBusMethod] {
        [
            .returning("AuxPing") { _, _ in
                "pong"
            }
        ]
    }
}

final class ChildEchoObject: DBusObject, @unchecked Sendable {
    static let interface = "org.swiftdbus.tests.ChildEcho"
    static let path = "/org/swiftdbus/tests/Echo/Child"

    var methods: [DBusMethod] {
        [
            .returning("ChildMethod") { _, _ in
                "child"
            }
        ]
    }
}

final class CustomIntrospectionObject: DBusObject, @unchecked Sendable {
    static let interface = "org.swiftdbus.tests.Custom"
    static let path = "/org/swiftdbus/tests/Custom"
    static let customXML = """
        <node>
          <interface name="org.swiftdbus.tests.Custom">
            <method name="Describe"/>
          </interface>
        </node>
        """

    var introspectionXML: String? { Self.customXML }
}
