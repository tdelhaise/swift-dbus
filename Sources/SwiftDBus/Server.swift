// swiftlint:disable file_length
import CDbus
import Foundation

// MARK: - Errors & helper types

public enum DBusServerError: Swift.Error, CustomStringConvertible {
    case connectionUnavailable
    case objectAlreadyRegistered(path: String, interface: String)
    case objectNotFound(path: String, interface: String)
    case methodNotFound(String)
    case sendFailed(String)
    case invalidSignalArguments(expected: Int, got: Int)

    public var description: String {
        switch self {
        case .connectionUnavailable:
            return "DBus connection unavailable"
        case .objectAlreadyRegistered(let path, let interface):
            return "Object already registered at \(path)#\(interface)"
        case .objectNotFound(let path, let interface):
            return "Object not found at \(path)#\(interface)"
        case .methodNotFound(let method):
            return "Unknown method \(method)"
        case .sendFailed(let reason):
            return "Failed to send DBus message (\(reason))"
        case .invalidSignalArguments(let expected, let got):
            return "Invalid signal payload (expected \(expected) values, got \(got))"
        }
    }
}

public struct DBusMethodCall {
    public let path: String
    public let interface: String
    public let member: String
    public let sender: String?
    public let arguments: [DBusBasicValue]
    public let signalEmitter: DBusSignalEmitter

    public func decoder() -> DBusDecoder {
        DBusDecoder(values: arguments)
    }
}

public typealias DBusMethodHandler = @Sendable (DBusMethodCall) throws -> [DBusBasicValue]

public struct DBusIntrospectionAnnotation: Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }

    public static func doc(_ text: String) -> DBusIntrospectionAnnotation {
        DBusIntrospectionAnnotation(name: "org.freedesktop.DBus.DocString", value: text)
    }
}

public struct DBusIntrospectionArgument: Sendable {
    public enum Direction: String, Sendable {
        case input = "in"
        case output = "out"
    }

    public let name: String
    public let signature: String
    public let direction: Direction?

    public init(
        name: String,
        signature: String,
        direction: Direction? = nil
    ) {
        self.name = name
        self.signature = signature
        self.direction = direction
    }

    public static func input(_ name: String, signature: String) -> DBusIntrospectionArgument {
        DBusIntrospectionArgument(name: name, signature: signature, direction: .input)
    }

    public static func output(_ name: String, signature: String) -> DBusIntrospectionArgument {
        DBusIntrospectionArgument(name: name, signature: signature, direction: .output)
    }

    public static func field(_ name: String, signature: String) -> DBusIntrospectionArgument {
        DBusIntrospectionArgument(name: name, signature: signature, direction: nil)
    }
}

public struct DBusMethod {
    public let name: String
    let handler: DBusMethodHandler
    public let arguments: [DBusIntrospectionArgument]
    public let documentation: String?
    public let annotations: [DBusIntrospectionAnnotation]

    public init(
        name: String,
        arguments: [DBusIntrospectionArgument] = [],
        documentation: String? = nil,
        annotations: [DBusIntrospectionAnnotation] = [],
        handler: @escaping DBusMethodHandler
    ) {
        self.name = name
        self.handler = handler
        self.arguments = arguments
        self.documentation = documentation
        self.annotations = annotations
    }

    public static func returning<T>(
        _ name: String,
        arguments inputArguments: [DBusIntrospectionArgument] = [],
        returns outputArguments: [DBusIntrospectionArgument] = [],
        documentation: String? = nil,
        annotations: [DBusIntrospectionAnnotation] = [],
        _ body: @escaping @Sendable (DBusMethodCall, inout DBusDecoder) throws -> T
    ) -> DBusMethod where T: DBusBasicEncodable & Sendable {
        DBusMethod(
            name: name,
            arguments: normalizedArguments(
                inputs: inputArguments,
                outputs: outputArguments
            ),
            documentation: documentation,
            annotations: annotations
        ) { call in
            var decoder = call.decoder()
            let value = try body(call, &decoder)
            return [value.dbusValue]
        }
    }

    public static func returningValues(
        _ name: String,
        arguments inputArguments: [DBusIntrospectionArgument] = [],
        returns outputArguments: [DBusIntrospectionArgument] = [],
        documentation: String? = nil,
        annotations: [DBusIntrospectionAnnotation] = [],
        _ body: @escaping @Sendable (DBusMethodCall, inout DBusDecoder) throws -> [DBusBasicValue]
    ) -> DBusMethod {
        DBusMethod(
            name: name,
            arguments: normalizedArguments(
                inputs: inputArguments,
                outputs: outputArguments
            ),
            documentation: documentation,
            annotations: annotations
        ) { call in
            var decoder = call.decoder()
            return try body(call, &decoder)
        }
    }

    public static func void(
        _ name: String,
        arguments inputArguments: [DBusIntrospectionArgument] = [],
        documentation: String? = nil,
        annotations: [DBusIntrospectionAnnotation] = [],
        _ body: @escaping @Sendable (DBusMethodCall, inout DBusDecoder) throws -> Void
    ) -> DBusMethod {
        DBusMethod(
            name: name,
            arguments: normalizedArguments(
                inputs: inputArguments,
                outputs: []
            ),
            documentation: documentation,
            annotations: annotations
        ) { call in
            var decoder = call.decoder()
            try body(call, &decoder)
            return []
        }
    }

    private static func normalizedArguments(
        inputs: [DBusIntrospectionArgument],
        outputs: [DBusIntrospectionArgument]
    ) -> [DBusIntrospectionArgument] {
        let normalizedInputs = inputs.map { argument in
            if argument.direction == .input { return argument }
            return DBusIntrospectionArgument(
                name: argument.name,
                signature: argument.signature,
                direction: .input
            )
        }
        let normalizedOutputs = outputs.map { argument in
            if argument.direction == .output { return argument }
            return DBusIntrospectionArgument(
                name: argument.name,
                signature: argument.signature,
                direction: .output
            )
        }
        return normalizedInputs + normalizedOutputs
    }
}

public struct DBusSignalDescription: Sendable {
    public let name: String
    public let arguments: [DBusIntrospectionArgument]
    public let documentation: String?
    public let annotations: [DBusIntrospectionAnnotation]

    public init(
        name: String,
        arguments: [DBusIntrospectionArgument] = [],
        documentation: String? = nil,
        annotations: [DBusIntrospectionAnnotation] = []
    ) {
        self.name = name
        self.arguments = arguments
        self.documentation = documentation
        self.annotations = annotations
    }
}

public struct DBusPropertyInvocation {
    public let path: String
    public let interface: String
    public let property: String
    public let sender: String?
    public let signalEmitter: DBusSignalEmitter
}

public struct DBusProperty {
    public enum Access: String {
        case read = "read"
        case write = "write"
        case readWrite = "readwrite"
    }

    public typealias Getter = @Sendable (DBusPropertyInvocation) throws -> DBusBasicValue
    public typealias Setter = @Sendable (DBusBasicValue, DBusPropertyInvocation) throws -> Void

    public let name: String
    public let signature: String
    public let access: Access
    let getter: Getter?
    let setter: Setter?
    public let documentation: String?
    public let annotations: [DBusIntrospectionAnnotation]

    public init(
        name: String,
        signature: String,
        access: Access,
        getter: Getter? = nil,
        setter: Setter? = nil,
        documentation: String? = nil,
        annotations: [DBusIntrospectionAnnotation] = []
    ) {
        self.name = name
        self.signature = signature
        self.access = access
        self.getter = getter
        self.setter = setter
        self.documentation = documentation
        self.annotations = annotations
    }

    public static func readOnly<T>(
        _ name: String,
        documentation: String? = nil,
        annotations: [DBusIntrospectionAnnotation] = [],
        _ getter: @escaping @Sendable (DBusPropertyInvocation) throws -> T
    ) -> DBusProperty where T: DBusPropertyConvertible & DBusStaticSignature & Sendable {
        DBusProperty(
            name: name,
            signature: T.dbusSignature,
            access: .read,
            getter: { invocation in try getter(invocation).dbusValue },
            setter: nil,
            documentation: documentation,
            annotations: annotations
        )
    }

    public static func readWrite<T>(
        _ name: String,
        documentation: String? = nil,
        annotations: [DBusIntrospectionAnnotation] = [],
        get getter: @escaping @Sendable (DBusPropertyInvocation) throws -> T,
        set setter: @escaping @Sendable (T, DBusPropertyInvocation) throws -> Void
    ) -> DBusProperty where T: DBusPropertyConvertible & DBusStaticSignature & Sendable {
        DBusProperty(
            name: name,
            signature: T.dbusSignature,
            access: .readWrite,
            getter: { invocation in try getter(invocation).dbusValue },
            setter: { value, invocation in
                let typed = try T.decode(from: value)
                try setter(typed, invocation)
            },
            documentation: documentation,
            annotations: annotations
        )
    }

    public static func writeOnly<T>(
        _ name: String,
        documentation: String? = nil,
        annotations: [DBusIntrospectionAnnotation] = [],
        set setter: @escaping @Sendable (T, DBusPropertyInvocation) throws -> Void
    ) -> DBusProperty where T: DBusPropertyConvertible & DBusStaticSignature & Sendable {
        DBusProperty(
            name: name,
            signature: T.dbusSignature,
            access: .write,
            getter: nil,
            setter: { value, invocation in
                let typed = try T.decode(from: value)
                try setter(typed, invocation)
            },
            documentation: documentation,
            annotations: annotations
        )
    }

    var isReadable: Bool { getter != nil }
    var isWritable: Bool { setter != nil }
}

public protocol DBusObject: Sendable {
    static var interface: String { get }
    static var path: String { get }
    /// Optional XML snippet for DBus introspection.
    var introspectionXML: String? { get }
    var methods: [DBusMethod] { get }
    var methodHandlers: [String: DBusMethodHandler] { get }
    var properties: [DBusProperty] { get }
    var propertyHandlers: [String: DBusProperty] { get }
    var signals: [DBusSignalDescription] { get }
}

extension DBusObject {
    public var introspectionXML: String? { nil }
    public var methods: [DBusMethod] { [] }
    public var properties: [DBusProperty] { [] }
    public var signals: [DBusSignalDescription] { [] }

    public var methodHandlers: [String: DBusMethodHandler] {
        Dictionary(uniqueKeysWithValues: methods.map { ($0.name, $0.handler) })
    }

    public var propertyHandlers: [String: DBusProperty] {
        Dictionary(uniqueKeysWithValues: properties.map { ($0.name, $0) })
    }
}

public struct DBusSignalEmitter: Sendable {
    private weak var connection: DBusConnection?
    private let path: String
    private let interface: String

    init(connection: DBusConnection, path: String, interface: String) {
        self.connection = connection
        self.path = path
        self.interface = interface
    }

    public func emit(member: String, values: [DBusBasicValue]) throws {
        guard let connection else { throw DBusServerError.connectionUnavailable }
        try connection.withRawPointer { connPointer in
            guard let signal = dbus_message_new_signal(path, interface, member) else {
                throw DBusServerError.sendFailed("dbus_message_new_signal returned null")
            }
            var iterator = DBusMessageIter()
            dbus_message_iter_init_append(signal, &iterator)
            do {
                for value in values {
                    try DBusMarshal.appendValue(value, into: &iterator)
                }
            } catch {
                dbus_message_unref(signal)
                throw error
            }
            if dbus_connection_send(connPointer, signal, nil) == 0 {
                dbus_message_unref(signal)
                throw DBusServerError.sendFailed("dbus_connection_send returned 0")
            }
            dbus_connection_flush(connPointer)
            dbus_message_unref(signal)
        }
    }

    public func emit(
        _ signal: DBusSignalDescription,
        values: [DBusBasicValue]
    ) throws {
        try validate(values: values, against: signal)
        try emit(member: signal.name, values: values)
    }

    public func emit(
        _ signal: DBusSignalDescription,
        encode buildArguments: (inout DBusSignalArgumentsEncoder) throws -> Void
    ) throws {
        var encoder = DBusSignalArgumentsEncoder()
        try buildArguments(&encoder)
        try emit(signal, values: encoder.values)
    }

    public func emitPropertiesChanged(
        interface changedInterface: String,
        changed: [String: DBusBasicValue],
        invalidated: [String] = []
    ) throws {
        guard let connection else { throw DBusServerError.connectionUnavailable }
        try connection.withRawPointer { connPointer in
            guard
                let signal = dbus_message_new_signal(
                    path,
                    "org.freedesktop.DBus.Properties",
                    "PropertiesChanged"
                )
            else {
                throw DBusServerError.sendFailed("dbus_message_new_signal returned null")
            }
            var iterator = DBusMessageIter()
            dbus_message_iter_init_append(signal, &iterator)
            do {
                try DBusMarshal.appendValue(.string(changedInterface), into: &iterator)
                try DBusMarshal.appendDictStringVariantBasics(changed, into: &iterator)
                try DBusMarshal.appendValue(.stringArray(invalidated), into: &iterator)
            } catch {
                dbus_message_unref(signal)
                throw error
            }
            if dbus_connection_send(connPointer, signal, nil) == 0 {
                dbus_message_unref(signal)
                throw DBusServerError.sendFailed("dbus_connection_send returned 0")
            }
            dbus_connection_flush(connPointer)
            dbus_message_unref(signal)
        }
    }

    private func validate(values: [DBusBasicValue], against signal: DBusSignalDescription) throws {
        guard !signal.arguments.isEmpty else { return }
        guard signal.arguments.count == values.count else {
            throw DBusServerError.invalidSignalArguments(
                expected: signal.arguments.count,
                got: values.count
            )
        }
    }
}

// MARK: - Exporter

public final class DBusObjectExporter: @unchecked Sendable {  // swiftlint:disable:this type_body_length
    private struct ObjectKey: Hashable {
        let path: String
        let interface: String
    }

    private struct AnyDBusObject {
        let path: String
        let interface: String
        let handlers: [String: DBusMethodHandler]
        let signalEmitter: DBusSignalEmitter
        let introspectionXML: String?
        let methodList: [DBusMethod]
        let propertyHandlers: [String: DBusProperty]
        let propertyList: [DBusProperty]
        let signalList: [DBusSignalDescription]
    }

    private let connection: DBusConnection
    private var objects: [ObjectKey: AnyDBusObject] = [:]
    private let lock = NSLock()
    private var listenerTask: Task<Void, Never>?

    public init(connection: DBusConnection) {
        self.connection = connection
    }

    deinit {
        listenerTask?.cancel()
    }

    public func register<Object: DBusObject>(_ object: Object) throws {
        let key = ObjectKey(path: Object.path, interface: Object.interface)
        lock.lock()
        defer { lock.unlock() }
        guard objects[key] == nil else {
            throw DBusServerError.objectAlreadyRegistered(path: key.path, interface: key.interface)
        }
        let emitter = DBusSignalEmitter(connection: connection, path: key.path, interface: key.interface)
        let entry = AnyDBusObject(
            path: key.path,
            interface: key.interface,
            handlers: object.methodHandlers,
            signalEmitter: emitter,
            introspectionXML: object.introspectionXML,
            methodList: object.methods,
            propertyHandlers: object.propertyHandlers,
            propertyList: object.properties,
            signalList: object.signals
        )
        objects[key] = entry
        ensureListener()
    }

    public func unregister(path: String, interface: String) {
        lock.lock()
        objects.removeValue(forKey: ObjectKey(path: path, interface: interface))
        lock.unlock()
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func ensureListener() {
        guard listenerTask == nil else { return }
        listenerTask = Task { [weak self] in
            guard let self else { return }
            let stream: AsyncStream<DBusMessageRef>
            do {
                stream = try connection.messages()
            } catch {
                return
            }
            for await message in stream {
                guard dbus_message_get_type(message.raw) == DBusMsgType.METHOD_CALL else { continue }
                guard
                    let cPath = dbus_message_get_path(message.raw),
                    let cInterface = dbus_message_get_interface(message.raw),
                    let cMember = dbus_message_get_member(message.raw)
                else { continue }
                let path = String(cString: cPath)
                let interface = String(cString: cInterface)
                let member = String(cString: cMember)
                let sender = dbus_message_get_sender(message.raw).map { String(cString: $0) }
                if interface == "org.freedesktop.DBus.Introspectable", member == "Introspect" {
                    guard let entry = object(atPath: path) else { continue }
                    do {
                        let xml = try introspectionXML(for: entry)
                        try sendReturn(for: message, values: [.string(xml)])
                    } catch {
                        try? sendFailure(for: message, error: error)
                    }
                    continue
                }
                if interface == "org.freedesktop.DBus.Properties" {
                    handlePropertiesCall(
                        for: message,
                        path: path,
                        member: member,
                        sender: sender
                    )
                    continue
                }
                guard let entry = object(at: path, interface: interface) else { continue }
                guard interface == entry.interface else { continue }
                guard let handler = entry.handlers[member] else {
                    try? sendUnknownMethodError(for: message, member: member)
                    continue
                }
                let call = DBusMethodCall(
                    path: path,
                    interface: interface,
                    member: member,
                    sender: sender,
                    arguments: DBusMarshal.decodeAllBasicArgs(message),
                    signalEmitter: entry.signalEmitter
                )
                do {
                    let replyValues = try handler(call)
                    try sendReturn(for: message, values: replyValues)
                } catch {
                    try? sendFailure(for: message, error: error)
                }
            }
        }
    }

    private func object(at path: String, interface: String) -> AnyDBusObject? {
        lock.lock()
        defer { lock.unlock() }
        return objects[ObjectKey(path: path, interface: interface)]
    }

    private func object(atPath path: String) -> AnyDBusObject? {
        lock.lock()
        defer { lock.unlock() }
        return objects.first { $0.key.path == path }?.value
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func handlePropertiesCall(
        for message: DBusMessageRef,
        path: String,
        member: String,
        sender: String?
    ) {
        switch member {
        case "Get":
            guard let (targetInterface, propertyName) = try? propertiesGetArguments(message) else {
                try? sendPropertiesInvalidArgsError(for: message)
                return
            }
            guard let entry = object(at: path, interface: targetInterface) else {
                try? sendUnknownInterfaceError(for: message, interface: targetInterface)
                return
            }
            guard let property = entry.propertyHandlers[propertyName],
                property.isReadable, let getter = property.getter
            else {
                try? sendUnknownPropertyError(for: message, property: propertyName)
                return
            }

            let invocation = DBusPropertyInvocation(
                path: path,
                interface: entry.interface,
                property: propertyName,
                sender: sender,
                signalEmitter: entry.signalEmitter
            )
            do {
                let value = try getter(invocation)
                try sendVariantReturn(for: message, value: value)
            } catch {
                try? sendFailure(for: message, error: error)
            }

        case "Set":
            guard
                let (targetInterface, propertyName, value) = try? propertiesSetArguments(message)
            else {
                try? sendPropertiesInvalidArgsError(for: message)
                return
            }
            guard let entry = object(at: path, interface: targetInterface) else {
                try? sendUnknownInterfaceError(for: message, interface: targetInterface)
                return
            }
            guard let property = entry.propertyHandlers[propertyName] else {
                try? sendUnknownPropertyError(for: message, property: propertyName)
                return
            }
            guard property.isWritable, let setter = property.setter else {
                try? sendPropertyReadOnlyError(for: message, property: propertyName)
                return
            }
            let invocation = DBusPropertyInvocation(
                path: path,
                interface: entry.interface,
                property: propertyName,
                sender: sender,
                signalEmitter: entry.signalEmitter
            )
            do {
                try setter(value, invocation)
                try sendReturn(for: message, values: [])
            } catch {
                try? sendFailure(for: message, error: error)
            }

        case "GetAll":
            guard let targetInterface = try? propertiesGetAllArguments(message) else {
                try? sendPropertiesInvalidArgsError(for: message)
                return
            }
            guard let entry = object(at: path, interface: targetInterface) else {
                try? sendUnknownInterfaceError(for: message, interface: targetInterface)
                return
            }
            var dictionary: [String: DBusBasicValue] = [:]
            for property in entry.propertyList where property.isReadable {
                guard let getter = property.getter else { continue }
                let invocation = DBusPropertyInvocation(
                    path: path,
                    interface: entry.interface,
                    property: property.name,
                    sender: sender,
                    signalEmitter: entry.signalEmitter
                )
                do {
                    dictionary[property.name] = try getter(invocation)
                } catch {
                    try? sendFailure(for: message, error: error)
                    return
                }
            }
            do {
                try sendDictionaryReturn(for: message, dictionary: dictionary)
            } catch {
                try? sendFailure(for: message, error: error)
            }

        default:
            try? sendUnknownMethodError(for: message, member: member)
        }
    }

    private func introspectionXML(for entry: AnyDBusObject) throws -> String {
        if let provided = entry.introspectionXML {
            return provided
        }
        let methodsXML = entry.methodList.map { xml(for: $0) }
        let propertiesXML = entry.propertyList.map { xml(for: $0) }
        let signalsXML = entry.signalList.map { xml(for: $0) }

        let allLines = methodsXML + signalsXML + propertiesXML
        let body = allLines.isEmpty ? "" : allLines.joined(separator: "\n") + "\n"
        return """
            <node>
              <interface name="\(entry.interface)">
            \(body)  </interface>
            </node>
            """
    }

    private func xml(for method: DBusMethod) -> String {
        var lines: [String] = ["    <method name=\"\(method.name.xmlEscaped())\">"]
        for argument in method.arguments {
            lines.append(xml(for: argument, indent: "      "))
        }
        for annotation in annotations(forDocumentation: method.documentation, existing: method.annotations) {
            lines.append(xml(for: annotation, indent: "      "))
        }
        lines.append("    </method>")
        return lines.joined(separator: "\n")
    }

    private func xml(for signal: DBusSignalDescription) -> String {
        var lines: [String] = ["    <signal name=\"\(signal.name.xmlEscaped())\">"]
        for argument in signal.arguments {
            lines.append(xml(for: argument, indent: "      "))
        }
        for annotation in annotations(forDocumentation: signal.documentation, existing: signal.annotations) {
            lines.append(xml(for: annotation, indent: "      "))
        }
        lines.append("    </signal>")
        return lines.joined(separator: "\n")
    }

    private func xml(for property: DBusProperty) -> String {
        let opening =
            "    <property name=\"\(property.name.xmlEscaped())\" type=\"\(property.signature.xmlEscaped())\" access=\"\(property.access.rawValue)\">"
        let annotations = annotations(forDocumentation: property.documentation, existing: property.annotations)
        if annotations.isEmpty {
            return opening.replacingOccurrences(of: ">", with: "/>")
        }
        var lines: [String] = [opening]
        for annotation in annotations {
            lines.append(xml(for: annotation, indent: "      "))
        }
        lines.append("    </property>")
        return lines.joined(separator: "\n")
    }

    private func xml(for argument: DBusIntrospectionArgument, indent: String) -> String {
        var attributes = [
            "name=\"\(argument.name.xmlEscaped())\"",
            "type=\"\(argument.signature.xmlEscaped())\""
        ]
        if let direction = argument.direction {
            attributes.insert("direction=\"\(direction.rawValue)\"", at: 1)
        }
        return "\(indent)<arg \(attributes.joined(separator: " "))/>"
    }

    private func xml(for annotation: DBusIntrospectionAnnotation, indent: String) -> String {
        "\(indent)<annotation name=\"\(annotation.name.xmlEscaped())\" value=\"\(annotation.value.xmlEscaped())\"/>"
    }

    private func annotations(
        forDocumentation documentation: String?,
        existing: [DBusIntrospectionAnnotation]
    ) -> [DBusIntrospectionAnnotation] {
        if let documentation, !documentation.isEmpty {
            return existing + [.doc(documentation)]
        }
        return existing
    }

    private func sendVariantReturn(for message: DBusMessageRef, value: DBusBasicValue) throws {
        try connection.withRawPointer { connectionPointer in
            guard let reply = dbus_message_new_method_return(message.raw) else {
                throw DBusServerError.sendFailed("dbus_message_new_method_return returned null")
            }
            var iterator = DBusMessageIter()
            dbus_message_iter_init_append(reply, &iterator)
            do {
                try DBusMarshal.appendVariant(of: value, into: &iterator)
            } catch {
                dbus_message_unref(reply)
                throw error
            }
            if dbus_connection_send(connectionPointer, reply, nil) == 0 {
                dbus_message_unref(reply)
                throw DBusServerError.sendFailed("dbus_connection_send returned 0")
            }
            dbus_connection_flush(connectionPointer)
            dbus_message_unref(reply)
        }
    }

    private func sendDictionaryReturn(
        for message: DBusMessageRef,
        dictionary: [String: DBusBasicValue]
    ) throws {
        try connection.withRawPointer { connectionPointer in
            guard let reply = dbus_message_new_method_return(message.raw) else {
                throw DBusServerError.sendFailed("dbus_message_new_method_return returned null")
            }
            var iterator = DBusMessageIter()
            dbus_message_iter_init_append(reply, &iterator)
            do {
                try DBusMarshal.appendDictStringVariantBasics(dictionary, into: &iterator)
            } catch {
                dbus_message_unref(reply)
                throw error
            }
            if dbus_connection_send(connectionPointer, reply, nil) == 0 {
                dbus_message_unref(reply)
                throw DBusServerError.sendFailed("dbus_connection_send returned 0")
            }
            dbus_connection_flush(connectionPointer)
            dbus_message_unref(reply)
        }
    }

    private func sendReturn(for message: DBusMessageRef, values: [DBusBasicValue]) throws {
        try connection.withRawPointer { connectionPointer in
            guard let reply = dbus_message_new_method_return(message.raw) else {
                throw DBusServerError.sendFailed("dbus_message_new_method_return returned null")
            }
            var iterator = DBusMessageIter()
            dbus_message_iter_init_append(reply, &iterator)
            do {
                for value in values {
                    try DBusMarshal.appendValue(value, into: &iterator)
                }
            } catch {
                dbus_message_unref(reply)
                throw error
            }
            if dbus_connection_send(connectionPointer, reply, nil) == 0 {
                dbus_message_unref(reply)
                throw DBusServerError.sendFailed("dbus_connection_send returned 0")
            }
            dbus_connection_flush(connectionPointer)
            dbus_message_unref(reply)
        }
    }

    private func sendUnknownMethodError(for message: DBusMessageRef, member: String) throws {
        try sendError(
            for: message,
            name: "org.freedesktop.DBus.Error.UnknownMethod",
            description: "No method named \(member)"
        )
    }

    private func sendFailure(for message: DBusMessageRef, error: Swift.Error) throws {
        try sendError(
            for: message,
            name: "org.freedesktop.DBus.Error.Failed",
            description: String(describing: error)
        )
    }

    private func sendError(for message: DBusMessageRef, name: String, description: String) throws {
        try connection.withRawPointer { connectionPointer in
            guard
                let errorMessage = dbus_message_new_error(message.raw, name, description)
            else {
                throw DBusServerError.sendFailed("dbus_message_new_error returned null")
            }
            if dbus_connection_send(connectionPointer, errorMessage, nil) == 0 {
                dbus_message_unref(errorMessage)
                throw DBusServerError.sendFailed("dbus_connection_send returned 0")
            }
            dbus_connection_flush(connectionPointer)
            dbus_message_unref(errorMessage)
        }
    }

    private func sendPropertiesInvalidArgsError(for message: DBusMessageRef) throws {
        try sendError(
            for: message,
            name: "org.freedesktop.DBus.Error.InvalidArgs",
            description: "Invalid property arguments"
        )
    }

    private func sendUnknownInterfaceError(for message: DBusMessageRef, interface: String) throws {
        try sendError(
            for: message,
            name: "org.freedesktop.DBus.Error.UnknownInterface",
            description: "Unknown interface \(interface)"
        )
    }

    private func sendUnknownPropertyError(for message: DBusMessageRef, property: String) throws {
        try sendError(
            for: message,
            name: "org.freedesktop.DBus.Error.UnknownProperty",
            description: "Unknown property \(property)"
        )
    }

    private func sendPropertyReadOnlyError(for message: DBusMessageRef, property: String) throws {
        try sendError(
            for: message,
            name: "org.freedesktop.DBus.Error.PropertyReadOnly",
            description: "Property \(property) is read-only"
        )
    }

    private func propertiesGetArguments(_ message: DBusMessageRef) throws -> (String, String) {
        var iterator = DBusMessageIter()
        guard dbus_message_iter_init(message.raw, &iterator) != 0 else {
            throw DBusMarshalError.initIterFailed
        }
        let interface = try readStringArgument(&iterator)
        guard dbus_message_iter_next(&iterator) != 0 else {
            throw DBusMarshalError.invalidType(
                expected: DBusTypeCode.STRING,
                got: 0
            )
        }
        let property = try readStringArgument(&iterator)
        return (interface, property)
    }

    private func propertiesSetArguments(_ message: DBusMessageRef) throws -> (String, String, DBusBasicValue) {
        var iterator = DBusMessageIter()
        guard dbus_message_iter_init(message.raw, &iterator) != 0 else {
            throw DBusMarshalError.initIterFailed
        }
        let interface = try readStringArgument(&iterator)
        guard dbus_message_iter_next(&iterator) != 0 else {
            throw DBusMarshalError.invalidType(
                expected: DBusTypeCode.STRING,
                got: 0
            )
        }
        let property = try readStringArgument(&iterator)
        guard dbus_message_iter_next(&iterator) != 0 else {
            throw DBusMarshalError.invalidType(
                expected: DBusTypeCode.VARIANT,
                got: 0
            )
        }
        var variantIterator = iterator
        let value = try DBusMarshal.decodeVariantBasicValue(&variantIterator)
        return (interface, property, value)
    }

    private func propertiesGetAllArguments(_ message: DBusMessageRef) throws -> String {
        var iterator = DBusMessageIter()
        guard dbus_message_iter_init(message.raw, &iterator) != 0 else {
            throw DBusMarshalError.initIterFailed
        }
        return try readStringArgument(&iterator)
    }

    private func readStringArgument(_ iterator: inout DBusMessageIter) throws -> String {
        let type = dbus_message_iter_get_arg_type(&iterator)
        guard type == DBusTypeCode.STRING else {
            throw DBusMarshalError.invalidType(expected: DBusTypeCode.STRING, got: type)
        }
        var pointer: UnsafePointer<CChar>?
        dbus_message_iter_get_basic(&iterator, &pointer)
        guard let pointer else {
            throw DBusMarshalError.null
        }
        return String(cString: pointer)
    }
}

extension String {
    fileprivate func xmlEscaped() -> String {
        var escaped = self
        escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        escaped = escaped.replacingOccurrences(of: "'", with: "&apos;")
        return escaped
    }
}
