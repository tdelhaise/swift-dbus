// swiftlint:disable file_length
import CDbus
import Foundation
import FoundationXML

public struct DBusPropertyKey: Hashable, Sendable {
    public let destination: String
    public let path: String
    public let interface: String
    public let name: String

    public init(destination: String, path: String, interface: String, name: String) {
        self.destination = destination
        self.path = path
        self.interface = interface
        self.name = name
    }
}

public struct DBusIntrospectedArgument: Sendable {
    public let name: String
    public let type: String
    public let direction: String?
}

public struct DBusIntrospectedMethod: Sendable {
    public let name: String
    public let arguments: [DBusIntrospectedArgument]
    public let documentation: String?
}

public struct DBusIntrospectedSignal: Sendable {
    public let name: String
    public let arguments: [DBusIntrospectedArgument]
    public let documentation: String?
}

public struct DBusIntrospectedProperty: Sendable {
    public let name: String
    public let type: String
    public let access: String
    public let documentation: String?
}

public struct DBusIntrospectedInterface: Sendable {
    public let name: String
    public let methods: [DBusIntrospectedMethod]
    public let signals: [DBusIntrospectedSignal]
    public let properties: [DBusIntrospectedProperty]
}

private final class DBusIntrospectionXMLParser: NSObject, XMLParserDelegate {

    private struct MethodBuilder {
        let name: String
        var arguments: [DBusIntrospectedArgument] = []
        var documentation: String?

        func build() -> DBusIntrospectedMethod {
            DBusIntrospectedMethod(name: name, arguments: arguments, documentation: documentation)
        }
    }

    private struct SignalBuilder {
        let name: String
        var arguments: [DBusIntrospectedArgument] = []
        var documentation: String?

        func build() -> DBusIntrospectedSignal {
            DBusIntrospectedSignal(name: name, arguments: arguments, documentation: documentation)
        }
    }

    private struct PropertyBuilder {
        let name: String
        let type: String
        let access: String
        var documentation: String?

        func build() -> DBusIntrospectedProperty {
            DBusIntrospectedProperty(name: name, type: type, access: access, documentation: documentation)
        }
    }

    private let targetInterface: String
    private var currentInterface: String?
    private var currentMethod: MethodBuilder?
    private var currentSignal: SignalBuilder?
    private var currentProperty: PropertyBuilder?
    private var methods: [DBusIntrospectedMethod] = []
    private var signals: [DBusIntrospectedSignal] = []
    private var properties: [DBusIntrospectedProperty] = []
    private var result: DBusIntrospectedInterface?

    init(targetInterface: String) {
        self.targetInterface = targetInterface
    }

    func parse(xml: String) throws -> DBusIntrospectedInterface? {
        let trimmed = xml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let startRange = trimmed.range(of: "<interface name=\"\(targetInterface)\"") else {
            return nil
        }
        guard let endRange = trimmed.range(of: "</interface>", range: startRange.lowerBound..<trimmed.endIndex) else {
            return nil
        }
        let interfaceFragment = trimmed[startRange.lowerBound..<endRange.upperBound]
        let snippet = """
            <?xml version="1.0" encoding="UTF-8"?>
            <root>
            \(interfaceFragment)
            </root>
            """

        guard let data = snippet.data(using: .utf8) else {
            throw DBusConnection.Error.failed("Invalid introspection XML encoding")
        }
        let parser = XMLParser(data: data)
        parser.delegate = self
        if parser.parse() {
            return result
        }
        if let error = parser.parserError {
            throw DBusConnection.Error.failed("Introspection parsing failed: \(error.localizedDescription)")
        }
        return result
    }

    // swiftlint:disable:next cyclomatic_complexity
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "interface":
            currentInterface = attributeDict["name"]
        case "method":
            guard currentInterface == targetInterface else { return }
            currentMethod = MethodBuilder(name: attributeDict["name"] ?? "")
        case "signal":
            guard currentInterface == targetInterface else { return }
            currentSignal = SignalBuilder(name: attributeDict["name"] ?? "")
        case "property":
            guard currentInterface == targetInterface else { return }
            currentProperty = PropertyBuilder(
                name: attributeDict["name"] ?? "",
                type: attributeDict["type"] ?? "",
                access: attributeDict["access"] ?? ""
            )
        case "arg":
            guard currentInterface == targetInterface else { return }
            let argument = DBusIntrospectedArgument(
                name: attributeDict["name"] ?? "",
                type: attributeDict["type"] ?? "",
                direction: attributeDict["direction"]
            )
            if var method = currentMethod {
                method.arguments.append(argument)
                currentMethod = method
            } else if var signal = currentSignal {
                signal.arguments.append(argument)
                currentSignal = signal
            }
        case "annotation":
            guard currentInterface == targetInterface else { return }
            guard attributeDict["name"] == "org.freedesktop.DBus.DocString" else { return }
            let doc = attributeDict["value"]
            if var method = currentMethod {
                method.documentation = doc
                currentMethod = method
            } else if var signal = currentSignal {
                signal.documentation = doc
                currentSignal = signal
            } else if var property = currentProperty {
                property.documentation = doc
                currentProperty = property
            }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "method":
            guard let method = currentMethod else { return }
            methods.append(method.build())
            currentMethod = nil
        case "signal":
            guard let signal = currentSignal else { return }
            signals.append(signal.build())
            currentSignal = nil
        case "property":
            guard let property = currentProperty else { return }
            properties.append(property.build())
            currentProperty = nil
        case "interface":
            guard currentInterface == targetInterface else {
                currentInterface = nil
                return
            }
            result = DBusIntrospectedInterface(
                name: targetInterface,
                methods: methods,
                signals: signals,
                properties: properties
            )
            currentInterface = nil
        default:
            break
        }
    }
}

public final class DBusPropertyCache: @unchecked Sendable {
    private var storage: [DBusPropertyKey: DBusBasicValue] = [:]
    private let lock = NSLock()

    public init() {}

    public func value(for key: DBusPropertyKey) -> DBusBasicValue? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func store(_ value: DBusBasicValue, for key: DBusPropertyKey) {
        lock.lock()
        storage[key] = value
        lock.unlock()
    }

    public func removeValue(for key: DBusPropertyKey) {
        lock.lock()
        storage.removeValue(forKey: key)
        lock.unlock()
    }

    public func removeAll(where shouldRemove: ((DBusPropertyKey) -> Bool)? = nil) {
        lock.lock()
        if let predicate = shouldRemove {
            storage = storage.filter { !predicate($0.key) }
        } else {
            storage.removeAll()
        }
        lock.unlock()
    }
}

public struct DBusIntrospectionKey: Hashable, Sendable {
    public let destination: String
    public let path: String
    public let interface: String

    public init(destination: String, path: String, interface: String) {
        self.destination = destination
        self.path = path
        self.interface = interface
    }
}

public final class DBusIntrospectionCache: @unchecked Sendable {
    private var storage: [DBusIntrospectionKey: DBusIntrospectedInterface] = [:]
    private let lock = NSLock()

    public init() {}

    public func value(for key: DBusIntrospectionKey) -> DBusIntrospectedInterface? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func store(_ value: DBusIntrospectedInterface, for key: DBusIntrospectionKey) {
        lock.lock()
        storage[key] = value
        lock.unlock()
    }

    public func removeValue(for key: DBusIntrospectionKey) {
        lock.lock()
        storage.removeValue(forKey: key)
        lock.unlock()
    }

    public func removeAll(where shouldRemove: ((DBusIntrospectionKey) -> Bool)? = nil) {
        lock.lock()
        if let predicate = shouldRemove {
            storage = storage.filter { !predicate($0.key) }
        } else {
            storage.removeAll()
        }
        lock.unlock()
    }
}

public final class DBusPropertyCacheSubscription: Sendable {
    private let task: Task<Void, Never>

    init(task: Task<Void, Never>) {
        self.task = task
    }

    deinit {
        task.cancel()
    }

    public func cancel() {
        task.cancel()
    }
}

public struct DBusPropertiesChanged: DBusSignalDecodable {
    public static let member = "PropertiesChanged"

    public let interface: String
    public let changed: [String: DBusBasicValue]
    public let invalidated: [String]

    public init(signal: DBusSignal, decoder: inout DBusDecoder) throws {
        interface = try decoder.next()
        let dictValue = try decoder.nextValue()
        guard case .dictStringVariant(let dictionary) = dictValue else {
            throw DBusDecodeError.typeMismatch(expected: "a{sv}", value: dictValue)
        }
        changed = dictionary
        invalidated = try decoder.next()
    }
}

/// Point d’entrée haut niveau pour consommer une interface DBus donnée (M4).
public struct DBusProxy: Sendable {
    public let connection: DBusConnection
    public let destination: String
    public let path: String
    public let interface: String

    public init(
        connection: DBusConnection,
        destination: String,
        path: String,
        interface: String
    ) {
        self.connection = connection
        self.destination = destination
        self.path = path
        self.interface = interface
    }

    /// Appel brut avec writer d’arguments explicite.
    /// - Returns: `DBusMessageRef` (`METHOD_RETURN` attendu)
    @discardableResult
    public func call(
        _ method: String,
        timeoutMS: Int32 = 2000,
        argsWriter: (inout DBusMessageIter) throws -> Void = { _ in }
    ) throws -> DBusMessageRef {
        try connection.callRaw(
            destination: destination,
            path: path,
            interface: interface,
            method: method,
            timeoutMS: timeoutMS,
            argsWriter: argsWriter
        )
    }

    /// Appel avec arguments basiques/génériques (`DBusBasicValue`).
    @discardableResult
    public func call(
        _ method: String,
        arguments: [DBusBasicValue],
        timeoutMS: Int32 = 2000
    ) throws -> DBusMessageRef {
        try call(method, timeoutMS: timeoutMS) { iterator in
            for argument in arguments {
                try DBusMarshal.appendValue(argument, into: &iterator)
            }
        }
    }

    /// Appel avec encodeur typed (ex: `DBusArguments("foo", UInt32(0))`).
    @discardableResult
    public func call<Args: DBusArgumentEncodable>(
        _ method: String,
        typedArguments arguments: Args,
        timeoutMS: Int32 = 2000
    ) throws -> DBusMessageRef {
        var encoder = DBusArgumentEncoder()
        try arguments.encodeArguments(into: &encoder)
        return try call(method, arguments: encoder.values, timeoutMS: timeoutMS)
    }

    /// Appel standard retournant le **premier String** du reply.
    public func callExpectingFirstString(
        _ method: String,
        arguments: [DBusBasicValue] = [],
        timeoutMS: Int32 = 2000
    ) throws -> String {
        let reply = try call(method, arguments: arguments, timeoutMS: timeoutMS)
        return try DBusMarshal.firstString(reply)
    }

    public func callExpectingFirstString<Args: DBusArgumentEncodable>(
        _ method: String,
        typedArguments arguments: Args,
        timeoutMS: Int32 = 2000
    ) throws -> String {
        let reply = try call(method, typedArguments: arguments, timeoutMS: timeoutMS)
        return try DBusMarshal.firstString(reply)
    }

    /// Retourne tous les arguments décodés comme valeurs basiques.
    public func callExpectingBasics(
        _ method: String,
        arguments: [DBusBasicValue] = [],
        timeoutMS: Int32 = 2000
    ) throws -> [DBusBasicValue] {
        let reply = try call(method, arguments: arguments, timeoutMS: timeoutMS)
        return DBusMarshal.decodeAllBasicArgs(reply)
    }

    public func callExpectingBasics<Args: DBusArgumentEncodable>(
        _ method: String,
        typedArguments arguments: Args,
        timeoutMS: Int32 = 2000
    ) throws -> [DBusBasicValue] {
        let reply = try call(method, typedArguments: arguments, timeoutMS: timeoutMS)
        return DBusMarshal.decodeAllBasicArgs(reply)
    }

    /// Appel avec décodage personnalisé via un `DBusDecoder`.
    public func callExpecting<T>(
        _ method: String,
        arguments: [DBusBasicValue] = [],
        timeoutMS: Int32 = 2000,
        decode: (inout DBusDecoder) throws -> T
    ) throws -> T {
        let basics = try callExpectingBasics(method, arguments: arguments, timeoutMS: timeoutMS)
        var decoder = DBusDecoder(values: basics)
        return try decode(&decoder)
    }

    /// Appel et décodage via un type conforme à `DBusReturnDecodable`.
    public func callExpecting<T: DBusReturnDecodable>(
        _ method: String,
        arguments: [DBusBasicValue] = [],
        timeoutMS: Int32 = 2000,
        as type: T.Type = T.self
    ) throws -> T {
        let basics = try callExpectingBasics(method, arguments: arguments, timeoutMS: timeoutMS)
        var decoder = DBusDecoder(values: basics)
        let value = try type.init(from: &decoder)
        if !decoder.isAtEnd {
            throw DBusDecodeError.missingValue(expected: "end of values")
        }
        return value
    }

    public func callExpecting<T: DBusReturnDecodable, Args: DBusArgumentEncodable>(
        _ method: String,
        typedArguments arguments: Args,
        timeoutMS: Int32 = 2000,
        as type: T.Type = T.self
    ) throws -> T {
        let basics = try callExpectingBasics(
            method,
            typedArguments: arguments,
            timeoutMS: timeoutMS
        )
        var decoder = DBusDecoder(values: basics)
        let value = try type.init(from: &decoder)
        if !decoder.isAtEnd {
            throw DBusDecodeError.missingValue(expected: "end of values")
        }
        return value
    }

    /// Appel attend un unique élément décodable.
    public func callExpectingSingle<T: DBusBasicDecodable>(
        _ method: String,
        arguments: [DBusBasicValue] = [],
        timeoutMS: Int32 = 2000
    ) throws -> T {
        try callExpecting(
            method,
            arguments: arguments,
            timeoutMS: timeoutMS,
            as: T.self
        )
    }

    public func callExpectingSingle<T: DBusBasicDecodable, Args: DBusArgumentEncodable>(
        _ method: String,
        typedArguments arguments: Args,
        timeoutMS: Int32 = 2000
    ) throws -> T {
        try callExpecting(
            method,
            typedArguments: arguments,
            timeoutMS: timeoutMS,
            as: T.self
        )
    }

    /// Stream de signaux limité à cette interface & member (optionnel arg0).
    public func signals(
        member: String,
        arg0: String? = nil
    ) throws -> AsyncStream<DBusSignal> {
        let rule = DBusMatchRule.signal(
            path: path,
            interface: interface,
            member: member,
            arg0: arg0
        )
        return try connection.signals(matching: rule)
    }

    /// Variante typée de `signals` : décode chaque signal via closure.
    public func signals<T>(
        member: String,
        arg0: String? = nil,
        as decode: @escaping @Sendable (inout DBusDecoder) throws -> T
    ) throws -> AsyncStream<T> {
        let raw = try signals(member: member, arg0: arg0)
        return AsyncStream<T> { continuation in
            let task = Task {
                for await signal in raw {
                    var decoder = DBusDecoder(values: signal.args)
                    do {
                        let decoded = try decode(&decoder)
                        continuation.yield(decoded)
                    } catch {
                        continue
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Variante encore plus typée : `T` fournit la métadonnée `member` + init depuis `DBusSignal`.
    public func signals<T: DBusSignalDecodable>(
        _ type: T.Type = T.self,
        arg0 overrideArg0: String? = nil
    ) throws -> AsyncStream<T> {
        let stream = try signals(
            member: type.member,
            arg0: overrideArg0 ?? type.arg0
        )
        return AsyncStream<T> { continuation in
            let task = Task {
                for await signal in stream {
                    var decoder = DBusDecoder(values: signal.args)
                    do {
                        let typed = try type.init(signal: signal, decoder: &decoder)
                        continuation.yield(typed)
                    } catch {
                        continue
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Properties helpers (org.freedesktop.DBus.Properties)

    public func propertiesChangedStream() throws -> AsyncStream<DBusPropertiesChanged> {
        let rule = DBusMatchRule.signal(
            path: path,
            interface: "org.freedesktop.DBus.Properties",
            member: DBusPropertiesChanged.member,
            arg0: interface
        )
        let raw = try connection.signals(matching: rule)
        return AsyncStream<DBusPropertiesChanged> { continuation in
            let task = Task {
                for await signal in raw {
                    var decoder = DBusDecoder(values: signal.args)
                    do {
                        let change = try DBusPropertiesChanged(signal: signal, decoder: &decoder)
                        continuation.yield(change)
                    } catch {
                        continue
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func getProperty(
        _ property: String,
        timeoutMS: Int32 = 2000
    ) throws -> DBusBasicValue {
        let reply = try propertiesProxy().call(
            "Get",
            arguments: [
                .string(interface),
                .string(property)
            ],
            timeoutMS: timeoutMS
        )
        return try DBusMarshal.firstVariantBasic(reply)
    }

    public func getProperty<T: DBusPropertyConvertible>(
        _ property: String,
        as type: T.Type = T.self,
        timeoutMS: Int32 = 2000,
        cache: DBusPropertyCache? = nil,
        refreshCache: Bool = false
    ) throws -> T {
        let cacheKey = makePropertyKey(property)
        if let cache, !refreshCache, let cached = cache.value(for: cacheKey) {
            return try type.decode(from: cached)
        }

        let value = try getProperty(property, timeoutMS: timeoutMS)
        cache?.store(value, for: cacheKey)
        return try type.decode(from: value)
    }

    public func setProperty(
        _ property: String,
        value: DBusBasicValue,
        timeoutMS: Int32 = 2000
    ) throws {
        _ = try propertiesProxy().call("Set", timeoutMS: timeoutMS) { iterator in
            try DBusMarshal.appendValue(.string(interface), into: &iterator)
            try DBusMarshal.appendValue(.string(property), into: &iterator)
            try DBusMarshal.appendVariant(of: value, into: &iterator)
        }
    }

    public func setProperty<T: DBusPropertyConvertible>(
        _ property: String,
        value: T,
        timeoutMS: Int32 = 2000,
        cache: DBusPropertyCache? = nil
    ) throws {
        try setProperty(property, value: value.dbusValue, timeoutMS: timeoutMS)
        cache?.store(value.dbusValue, for: makePropertyKey(property))
    }

    public func getAllProperties(
        timeoutMS: Int32 = 2000,
        cache: DBusPropertyCache? = nil
    ) throws -> [String: DBusBasicValue] {
        let reply = try propertiesProxy().call(
            "GetAll",
            arguments: [.string(interface)],
            timeoutMS: timeoutMS
        )
        let dict = try DBusMarshal.firstDictStringVariantBasics(reply)
        if let cache {
            for (property, value) in dict {
                cache.store(value, for: makePropertyKey(property))
            }
        }
        return dict
    }

    public func invalidatePropertyCache(
        _ property: String? = nil,
        cache: DBusPropertyCache
    ) {
        if let property {
            cache.removeValue(for: makePropertyKey(property))
        } else {
            let destination = destination
            let path = path
            let interface = interface
            cache.removeAll { key in
                key.destination == destination
                    && key.path == path
                    && key.interface == interface
            }
        }
    }

    @discardableResult
    public func autoInvalidatePropertyCache(
        _ cache: DBusPropertyCache
    ) throws -> DBusPropertyCacheSubscription {
        let stream = try propertiesChangedStream()
        let destination = destination
        let path = path
        let interface = interface

        let task = Task {
            for await change in stream {
                for name in change.changed.keys {
                    cache.removeValue(
                        for: DBusPropertyKey(
                            destination: destination,
                            path: path,
                            interface: interface,
                            name: name
                        )
                    )
                }
                for name in change.invalidated {
                    cache.removeValue(
                        for: DBusPropertyKey(
                            destination: destination,
                            path: path,
                            interface: interface,
                            name: name
                        )
                    )
                }
            }
        }

        return DBusPropertyCacheSubscription(task: task)
    }

    public func introspectionXML(timeoutMS: Int32 = 2000) throws -> String {
        try DBusProxy(
            connection: connection,
            destination: destination,
            path: path,
            interface: "org.freedesktop.DBus.Introspectable"
        ).callExpectingSingle("Introspect", timeoutMS: timeoutMS)
    }

    public func introspectedInterface(
        timeoutMS: Int32 = 2000,
        cache: DBusIntrospectionCache? = nil
    ) throws -> DBusIntrospectedInterface? {
        let key = makeIntrospectionKey()
        if let cache, let cached = cache.value(for: key) {
            return cached
        }

        let xml = try introspectionXML(timeoutMS: timeoutMS)
        let parser = DBusIntrospectionXMLParser(targetInterface: interface)
        guard let parsed = try parser.parse(xml: xml) else { return nil }
        cache?.store(parsed, for: key)
        return parsed
    }

    private func propertiesProxy() -> DBusProxy {
        DBusProxy(
            connection: connection,
            destination: destination,
            path: path,
            interface: "org.freedesktop.DBus.Properties"
        )
    }

    private func makePropertyKey(_ property: String) -> DBusPropertyKey {
        DBusPropertyKey(
            destination: destination,
            path: path,
            interface: interface,
            name: property
        )
    }

    private func makeIntrospectionKey() -> DBusIntrospectionKey {
        DBusIntrospectionKey(
            destination: destination,
            path: path,
            interface: interface
        )
    }
}
