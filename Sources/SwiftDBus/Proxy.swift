import CDbus

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

    /// Appel avec arguments basiques (`s`, `i`, `b`, `d`).
    @discardableResult
    public func call(
        _ method: String,
        arguments: [DBusBasicValue],
        timeoutMS: Int32 = 2000
    ) throws -> DBusMessageRef {
        try call(method, timeoutMS: timeoutMS) { iterator in
            for argument in arguments {
                try DBusMarshal.appendBasic(argument, into: &iterator)
            }
        }
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

    /// Retourne tous les arguments décodés comme valeurs basiques.
    public func callExpectingBasics(
        _ method: String,
        arguments: [DBusBasicValue] = [],
        timeoutMS: Int32 = 2000
    ) throws -> [DBusBasicValue] {
        let reply = try call(method, arguments: arguments, timeoutMS: timeoutMS)
        return DBusMarshal.decodeAllBasicArgs(reply)
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

    public func setProperty(
        _ property: String,
        value: DBusBasicValue,
        timeoutMS: Int32 = 2000
    ) throws {
        _ = try propertiesProxy().call("Set", timeoutMS: timeoutMS) { iterator in
            try DBusMarshal.appendBasic(.string(interface), into: &iterator)
            try DBusMarshal.appendBasic(.string(property), into: &iterator)
            try DBusMarshal.appendVariant(of: value, into: &iterator)
        }
    }

    public func getAllProperties(timeoutMS: Int32 = 2000) throws -> [String: DBusBasicValue] {
        let reply = try propertiesProxy().call(
            "GetAll",
            arguments: [.string(interface)],
            timeoutMS: timeoutMS
        )
        return try DBusMarshal.firstDictStringVariantBasics(reply)
    }

    private func propertiesProxy() -> DBusProxy {
        DBusProxy(
            connection: connection,
            destination: destination,
            path: path,
            interface: "org.freedesktop.DBus.Properties"
        )
    }
}
