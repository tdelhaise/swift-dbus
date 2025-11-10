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

public struct DBusProxyCaches: Sendable {
    public let propertyCache: DBusPropertyCache?
    public let introspectionCache: DBusIntrospectionCache?

    public init(
        propertyCache: DBusPropertyCache? = nil,
        introspectionCache: DBusIntrospectionCache? = nil
    ) {
        self.propertyCache = propertyCache
        self.introspectionCache = introspectionCache
    }
}

public enum DBusProxyMetadataError: Error, Equatable, CustomStringConvertible {
    case interfaceUnavailable(String)
    case missingProperty(String)
    case propertyTypeMismatch(property: String, expected: String, actual: String)
    case propertyNotReadable(String)
    case propertyNotWritable(String)
    case missingMethod(String)
    case methodMissingReturn(String)
    case methodMultipleReturns(String)
    case methodReturnMismatch(method: String, expected: String, actual: String)
    case methodArgumentCountMismatch(method: String, expected: Int, actual: Int)
    case missingSignal(String)

    public var description: String {
        switch self {
        case .interfaceUnavailable(let name):
            return "Introspection for interface \(name) is not available"
        case .missingProperty(let name):
            return "Property \(name) is not declared in introspection data"
        case .propertyTypeMismatch(let property, let expected, let actual):
            return "Property \(property) expects signature \(actual) but caller requested \(expected)"
        case .propertyNotReadable(let property):
            return "Property \(property) is not readable"
        case .propertyNotWritable(let property):
            return "Property \(property) is not writable"
        case .missingMethod(let name):
            return "Method \(name) is not declared in introspection data"
        case .methodMissingReturn(let method):
            return "Method \(method) does not expose any output arguments"
        case .methodMultipleReturns(let method):
            return "Method \(method) exposes multiple output arguments which is not supported by typed helpers"
        case .methodReturnMismatch(let method, let expected, let actual):
            return "Method \(method) returns signature \(actual) but caller expected \(expected)"
        case .methodArgumentCountMismatch(let method, let expected, let actual):
            return "Method \(method) expects \(expected) input arguments but received \(actual)"
        case .missingSignal(let name):
            return "Signal \(name) is not declared in introspection data"
        }
    }
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

// swiftlint:disable type_body_length
/// Point d’entrée haut niveau pour consommer une interface DBus donnée (M4).
public struct DBusProxy: Sendable {
    public let connection: DBusConnection
    public let destination: String
    public let path: String
    public let interface: String
    public let caches: DBusProxyCaches
    private let signalCacheHolder = SignalCacheHolder()

    public init(
        connection: DBusConnection,
        destination: String,
        path: String,
        interface: String,
        caches: DBusProxyCaches = DBusProxyCaches()
    ) {
        self.connection = connection
        self.destination = destination
        self.path = path
        self.interface = interface
        self.caches = caches
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
        try cachedSignalStream(
            member: member,
            arg0: arg0
        )
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
        let resolvedCache = cache ?? caches.propertyCache
        if let resolvedCache, !refreshCache, let cached = resolvedCache.value(for: cacheKey) {
            return try type.decode(from: cached)
        }

        let value = try getProperty(property, timeoutMS: timeoutMS)
        resolvedCache?.store(value, for: cacheKey)
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
        let resolvedCache = cache ?? caches.propertyCache
        resolvedCache?.store(value.dbusValue, for: makePropertyKey(property))
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
        let resolvedCache = cache ?? caches.propertyCache
        if let resolvedCache {
            for (property, value) in dict {
                resolvedCache.store(value, for: makePropertyKey(property))
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

    public func invalidateCachedProperties(_ property: String? = nil) {
        guard let cache = caches.propertyCache else { return }
        invalidatePropertyCache(property, cache: cache)
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

    @discardableResult
    public func autoInvalidateCachedPropertyCache() throws -> DBusPropertyCacheSubscription {
        guard let cache = caches.propertyCache else {
            throw DBusConnection.Error.failed("No property cache configured on this proxy")
        }
        return try autoInvalidatePropertyCache(cache)
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
        cache: DBusIntrospectionCache? = nil,
        forceRefresh: Bool = false
    ) throws -> DBusIntrospectedInterface? {
        let resolvedCache = cache ?? caches.introspectionCache
        let key = makeIntrospectionKey()
        if !forceRefresh, let resolvedCache, let cached = resolvedCache.value(for: key) {
            return cached
        }

        let xml = try introspectionXML(timeoutMS: timeoutMS)
        let parser = DBusIntrospectionXMLParser(targetInterface: interface)
        guard let parsed = try parser.parse(xml: xml) else { return nil }
        resolvedCache?.store(parsed, for: key)
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

// swiftlint:enable type_body_length

// MARK: - Introspection-powered helpers

extension DBusProxy {

    public var cachedMetadata: Metadata? {
        guard let interface = cachedIntrospectedInterface() else { return nil }
        return Metadata(interface: interface)
    }

    public func cachedIntrospectedInterface(
        cache: DBusIntrospectionCache? = nil
    ) -> DBusIntrospectedInterface? {
        let resolvedCache = cache ?? caches.introspectionCache
        return resolvedCache?.value(for: makeIntrospectionKey())
    }

    public func metadata(
        timeoutMS: Int32 = 2000,
        cache: DBusIntrospectionCache? = nil,
        forceRefresh: Bool = false
    ) throws -> Metadata {
        guard
            let interfaceInfo = try introspectedInterface(
                timeoutMS: timeoutMS,
                cache: cache,
                forceRefresh: forceRefresh
            )
        else {
            throw DBusProxyMetadataError.interfaceUnavailable(interface)
        }
        return Metadata(interface: interfaceInfo)
    }

    public func refreshMetadata(
        timeoutMS: Int32 = 2000,
        cache: DBusIntrospectionCache? = nil
    ) throws -> Metadata {
        try metadata(timeoutMS: timeoutMS, cache: cache, forceRefresh: true)
    }

    public func invalidateCachedMetadata(
        cache: DBusIntrospectionCache? = nil
    ) {
        let resolvedCache = cache ?? caches.introspectionCache
        resolvedCache?.removeValue(for: makeIntrospectionKey())
    }

    public struct Metadata: Sendable {
        public let interface: DBusIntrospectedInterface
        private let methodsByName: [String: DBusIntrospectedMethod]
        private let propertiesByName: [String: DBusIntrospectedProperty]
        private let signalsByName: [String: DBusIntrospectedSignal]

        fileprivate init(interface: DBusIntrospectedInterface) {
            self.interface = interface
            self.methodsByName = interface.methods.reduce(into: [:]) { dict, method in
                dict[method.name] = method
            }
            self.propertiesByName = interface.properties.reduce(into: [:]) { dict, property in
                dict[property.name] = property
            }
            self.signalsByName = interface.signals.reduce(into: [:]) { dict, signal in
                dict[signal.name] = signal
            }
        }

        public var name: String { interface.name }
        public var methods: [DBusIntrospectedMethod] { interface.methods }
        public var signals: [DBusIntrospectedSignal] { interface.signals }
        public var properties: [DBusIntrospectedProperty] { interface.properties }

        public func method(named name: String) -> DBusIntrospectedMethod? {
            methodsByName[name]
        }

        public func property(named name: String) -> DBusIntrospectedProperty? {
            propertiesByName[name]
        }

        public func signal(named name: String) -> DBusIntrospectedSignal? {
            signalsByName[name]
        }

        public func property<Value: DBusPropertyConvertible & DBusStaticSignature>(
            _ name: String,
            as type: Value.Type = Value.self
        ) throws -> PropertyHandle<Value> {
            guard let property = property(named: name) else {
                throw DBusProxyMetadataError.missingProperty(name)
            }
            guard property.type == Value.dbusSignature else {
                throw DBusProxyMetadataError.propertyTypeMismatch(
                    property: property.name,
                    expected: Value.dbusSignature,
                    actual: property.type
                )
            }
            return PropertyHandle(property: property)
        }

        public func method<Return: DBusBasicDecodable & DBusStaticSignature>(
            _ name: String,
            returns type: Return.Type = Return.self
        ) throws -> MethodHandle<Return> {
            guard let method = method(named: name) else {
                throw DBusProxyMetadataError.missingMethod(name)
            }
            let outputs = method.arguments.filter(\.isOutput)
            guard !outputs.isEmpty else {
                throw DBusProxyMetadataError.methodMissingReturn(method.name)
            }
            guard outputs.count == 1 else {
                throw DBusProxyMetadataError.methodMultipleReturns(method.name)
            }
            let outputSignature = outputs[0].type
            guard outputSignature == Return.dbusSignature else {
                throw DBusProxyMetadataError.methodReturnMismatch(
                    method: method.name,
                    expected: Return.dbusSignature,
                    actual: outputSignature
                )
            }
            let inputs = method.arguments.filter { !$0.isOutput }
            return MethodHandle(
                method: method,
                inputCount: inputs.count,
                outputSignature: outputSignature
            )
        }

        public func signal(_ name: String) throws -> SignalHandle {
            guard let signal = signal(named: name) else {
                throw DBusProxyMetadataError.missingSignal(name)
            }
            return SignalHandle(signal: signal)
        }

        public func signal<T: DBusSignalDecodable>(
            _ type: T.Type
        ) throws -> TypedSignalHandle<T> {
            guard let signal = signal(named: type.member) else {
                throw DBusProxyMetadataError.missingSignal(type.member)
            }
            return TypedSignalHandle(signal: signal)
        }
    }

    public struct PropertyHandle<Value: DBusPropertyConvertible & DBusStaticSignature>: Sendable {
        fileprivate let property: DBusIntrospectedProperty

        public var name: String { property.name }
        public var documentation: String? { property.documentation }
        public var typeSignature: String { property.type }
        public var isReadable: Bool { property.isReadable }
        public var isWritable: Bool { property.isWritable }
    }

    public struct MethodHandle<Return: DBusBasicDecodable & DBusStaticSignature>: Sendable {
        fileprivate let method: DBusIntrospectedMethod
        fileprivate let inputCount: Int
        fileprivate let outputSignature: String

        public var name: String { method.name }
        public var documentation: String? { method.documentation }
        public var inputArgumentCount: Int { inputCount }
    }

    public struct SignalHandle: Sendable {
        fileprivate let signal: DBusIntrospectedSignal

        public var name: String { signal.name }
        public var documentation: String? { signal.documentation }
    }

    public struct TypedSignalHandle<T: DBusSignalDecodable>: Sendable {
        fileprivate let signal: DBusIntrospectedSignal

        public var name: String { signal.name }
        public var documentation: String? { signal.documentation }
    }

    public func getProperty<T: DBusPropertyConvertible & DBusStaticSignature>(
        _ handle: PropertyHandle<T>,
        timeoutMS: Int32 = 2000,
        cache: DBusPropertyCache? = nil,
        refreshCache: Bool = false
    ) throws -> T {
        guard handle.isReadable else {
            throw DBusProxyMetadataError.propertyNotReadable(handle.name)
        }
        return try getProperty(
            handle.name,
            as: T.self,
            timeoutMS: timeoutMS,
            cache: cache,
            refreshCache: refreshCache
        )
    }

    public func setProperty<T: DBusPropertyConvertible & DBusStaticSignature>(
        _ handle: PropertyHandle<T>,
        value: T,
        timeoutMS: Int32 = 2000,
        cache: DBusPropertyCache? = nil
    ) throws {
        guard handle.isWritable else {
            throw DBusProxyMetadataError.propertyNotWritable(handle.name)
        }
        try setProperty(
            handle.name,
            value: value,
            timeoutMS: timeoutMS,
            cache: cache
        )
    }

    public func call<Return: DBusBasicDecodable & DBusStaticSignature>(
        _ handle: MethodHandle<Return>,
        arguments: [DBusBasicValue] = [],
        timeoutMS: Int32 = 2000
    ) throws -> Return {
        try handle.validateArgumentCount(arguments.count)
        return try callExpectingSingle(
            handle.name,
            arguments: arguments,
            timeoutMS: timeoutMS
        )
    }

    public func call<Return: DBusBasicDecodable & DBusStaticSignature, Args: DBusArgumentEncodable>(
        _ handle: MethodHandle<Return>,
        typedArguments arguments: Args,
        timeoutMS: Int32 = 2000
    ) throws -> Return {
        try callExpectingSingle(
            handle.name,
            typedArguments: arguments,
            timeoutMS: timeoutMS
        )
    }

    public func signals(
        _ handle: SignalHandle,
        arg0: String? = nil
    ) throws -> AsyncStream<DBusSignal> {
        try signals(member: handle.name, arg0: arg0)
    }

    public func signals<T: DBusSignalDecodable>(
        _ handle: TypedSignalHandle<T>,
        arg0 overrideArg0: String? = nil
    ) throws -> AsyncStream<T> {
        guard handle.name == T.member else {
            throw DBusProxyMetadataError.missingSignal(T.member)
        }
        return try signals(T.self, arg0: overrideArg0 ?? T.arg0)
    }

    private func cachedSignalStream(
        member: String,
        arg0: String?
    ) throws -> AsyncStream<DBusSignal> {
        try cachedSignalStream(rule: signalMatchRule(member: member, arg0: arg0))
    }

    private func cachedSignalStream(
        rule: DBusMatchRule
    ) throws -> AsyncStream<DBusSignal> {
        if let existing = signalCacheHolder.cache(for: rule) {
            return existing.stream()
        }
        let cache = try SignalStreamCache(
            rule: rule,
            connection: connection
        ) { [weak signalCacheHolder] in
            signalCacheHolder?.removeCache(for: rule)
        }
        signalCacheHolder.store(cache, for: rule)
        return cache.stream()
    }

    private func signalMatchRule(member: String, arg0: String?) -> DBusMatchRule {
        DBusMatchRule.signal(
            path: path,
            interface: interface,
            member: member,
            arg0: arg0
        )
    }
}

extension DBusProxy.MethodHandle {
    fileprivate func validateArgumentCount(_ actual: Int) throws {
        guard actual == inputCount else {
            throw DBusProxyMetadataError.methodArgumentCountMismatch(
                method: name,
                expected: inputCount,
                actual: actual
            )
        }
    }
}

private final class SignalStreamCache: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [Int: AsyncStream<DBusSignal>.Continuation] = [:]
    private var nextID = 0
    private var isFinalized = false
    private let cleanup: @Sendable () -> Void
    private var task: Task<Void, Never>?

    init(
        rule: DBusMatchRule,
        connection: DBusConnection,
        cleanup: @escaping @Sendable () -> Void
    ) throws {
        self.cleanup = cleanup
        let stream = try connection.signals(matching: rule)
        task = Task.detached { [weak self] in
            guard let self else { return }
            for await signal in stream {
                self.broadcast(signal)
            }
            self.finalize()
        }
    }

    func stream() -> AsyncStream<DBusSignal> {
        AsyncStream { continuation in
            lock.lock()
            let id = nextID
            nextID += 1
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id)
            }
        }
    }

    private func broadcast(_ signal: DBusSignal) {
        lock.lock()
        let continuationsCopy = Array(continuations.values)
        lock.unlock()
        for continuation in continuationsCopy {
            continuation.yield(signal)
        }
    }

    private func removeContinuation(_ id: Int) {
        lock.lock()
        continuations.removeValue(forKey: id)
        let isEmpty = continuations.isEmpty
        lock.unlock()
        if isEmpty {
            cancel()
        }
    }

    private func cancel() {
        task?.cancel()
        finalize()
    }

    private func finalize() {
        lock.lock()
        guard !isFinalized else {
            lock.unlock()
            return
        }
        isFinalized = true
        let continuationsCopy = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        cleanup()
        for continuation in continuationsCopy {
            continuation.finish()
        }
    }
}

private final class SignalCacheHolder: @unchecked Sendable {
    private var storage: [DBusMatchRule: SignalStreamCache] = [:]
    private let lock = NSLock()

    func cache(for rule: DBusMatchRule) -> SignalStreamCache? {
        lock.lock()
        defer { lock.unlock() }
        return storage[rule]
    }

    func store(_ cache: SignalStreamCache, for rule: DBusMatchRule) {
        lock.lock()
        storage[rule] = cache
        lock.unlock()
    }

    func removeCache(for rule: DBusMatchRule) {
        lock.lock()
        storage.removeValue(forKey: rule)
        lock.unlock()
    }
}

extension DBusIntrospectedArgument {
    fileprivate var isOutput: Bool {
        (direction?.lowercased() == "out")
    }
}

extension DBusIntrospectedProperty {
    fileprivate var isReadable: Bool {
        access.lowercased().contains("read")
    }

    fileprivate var isWritable: Bool {
        access.lowercased().contains("write")
    }
}
