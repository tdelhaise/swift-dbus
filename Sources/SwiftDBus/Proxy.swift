import CDbus
import Foundation

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

    // MARK: - Properties helpers (org.freedesktop.DBus.Properties)

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
}
