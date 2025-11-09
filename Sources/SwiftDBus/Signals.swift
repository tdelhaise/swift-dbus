import CDbus
import Dispatch
import Foundation

// MARK: - Match rule builder

/// Constructeur fluide de match rules DBus.
/// Exemple :
/// ```swift
/// let rule = DBusMatchRule.signal(
///   interface: "org.freedesktop.DBus",
///   member: "NameOwnerChanged",
///   arg0: "org.example.App"
/// )
/// ```
public struct DBusMatchRule: Equatable, CustomStringConvertible, Sendable {
    public var type: String = "signal"
    public var sender: String?
    public var path: String?
    public var interface: String?
    public var member: String?
    /// Filtre sur l’argument 0 (string)
    public var arg0: String?

    public init(
        type: String = "signal",
        sender: String? = nil,
        path: String? = nil,
        interface: String? = nil,
        member: String? = nil,
        arg0: String? = nil
    ) {
        self.type = type
        self.sender = sender
        self.path = path
        self.interface = interface
        self.member = member
        self.arg0 = arg0
    }

    public static func signal(
        sender: String? = nil,
        path: String? = nil,
        interface: String? = nil,
        member: String? = nil,
        arg0: String? = nil
    ) -> DBusMatchRule {
        DBusMatchRule(
            type: "signal",
            sender: sender,
            path: path,
            interface: interface,
            member: member,
            arg0: arg0
        )
    }

    public var text: String {
        var parts: [String] = []
        func esc(_ value: String) -> String {
            value.replacingOccurrences(of: "'", with: "\\'")
        }
        parts.append("type='\(esc(type))'")
        if let sender { parts.append("sender='\(esc(sender))'") }
        if let path { parts.append("path='\(esc(path))'") }
        if let interface { parts.append("interface='\(esc(interface))'") }
        if let member { parts.append("member='\(esc(member))'") }
        if let arg0 { parts.append("arg0='\(esc(arg0))'") }
        return parts.joined(separator: ",")
    }

    public var description: String { text }
}

// MARK: - Représentation d’un signal

public struct DBusSignal: CustomStringConvertible, Sendable {
    public let sender: String?
    public let path: String?
    public let interface: String?
    public let member: String?
    public let args: [DBusBasicValue]

    public var description: String {
        "DBusSignal sender=\(sender ?? "-") path=\(path ?? "-") "
            + "iface=\(interface ?? "-") member=\(member ?? "-") args=\(args)"
    }
}

// MARK: - Typed signal decoding

public protocol DBusSignalDecodable: Sendable {
    static var member: String { get }
    static var arg0: String? { get }
    init(signal: DBusSignal, decoder: inout DBusDecoder) throws
}

extension DBusSignalDecodable {
    public static var arg0: String? { nil }
}

public protocol DBusSignalPayload: DBusSignalDecodable, DBusReturnDecodable {}

extension DBusSignalPayload {
    public init(signal: DBusSignal, decoder: inout DBusDecoder) throws {
        var payloadDecoder = decoder
        let value = try Self(from: &payloadDecoder)
        if !payloadDecoder.isAtEnd {
            throw DBusDecodeError.missingValue(expected: "end of signal payload")
        }
        decoder = payloadDecoder
        self = value
    }
}

// MARK: - API Connexion (match, stream)

extension DBusConnection {
    /// Ajoute une règle de match côté bus (`org.freedesktop.DBus.AddMatch`).
    public func addMatch(_ rule: DBusMatchRule, timeoutMS: Int32 = 2000) throws {
        try sendSingleStringArg(
            destination: "org.freedesktop.DBus",
            path: "/org/freedesktop/DBus",
            interface: "org.freedesktop.DBus",
            method: "AddMatch",
            value: rule.text,
            timeoutMS: timeoutMS
        )
    }

    /// Retire une règle de match côté bus (`org.freedesktop.DBus.RemoveMatch`).
    public func removeMatch(_ rule: DBusMatchRule, timeoutMS: Int32 = 2000) throws {
        try sendSingleStringArg(
            destination: "org.freedesktop.DBus",
            path: "/org/freedesktop/DBus",
            interface: "org.freedesktop.DBus",
            method: "RemoveMatch",
            value: rule.text,
            timeoutMS: timeoutMS
        )
    }

    /// Renvoie un `AsyncStream<DBusSignal>` correspondant à la règle.
    /// La règle est ajoutée au start et retirée à l’annulation/fin du stream.
    public func signals(matching rule: DBusMatchRule) throws -> AsyncStream<DBusSignal> {
        // Ajout côté bus
        try addMatch(rule)

        let connection = self
        // Stream brut de messages (déjà pompé par la connexion)
        let messageStream = try messages()

        // Filtrage léger côté client (en plus du match côté bus).
        let filtered = AsyncStream<DBusSignal> { continuation in
            // Tâche dédiée de consommation
            let consumerTask = Task.detached {
                for await message in messageStream {
                    guard dbus_message_get_type(message.raw) == DBusMsgType.SIGNAL else { continue }

                    let signal = DBusSignal(
                        sender: dbus_message_get_sender(message.raw).map { String(cString: $0) },
                        path: dbus_message_get_path(message.raw).map { String(cString: $0) },
                        interface: dbus_message_get_interface(message.raw).map { String(cString: $0) },
                        member: dbus_message_get_member(message.raw).map { String(cString: $0) },
                        args: DBusMarshal.decodeAllBasicArgs(message)
                    )

                    // Vérification locale facultative selon la rule
                    if let iface = rule.interface, signal.interface != iface { continue }
                    if let mem = rule.member, signal.member != mem { continue }
                    if let pathFilter = rule.path, signal.path != pathFilter { continue }
                    if let expectedArg0 = rule.arg0 {
                        if case .string(let first)? = signal.args.first {
                            if first != expectedArg0 { continue }
                        } else {
                            continue
                        }
                    }

                    continuation.yield(signal)
                }
                continuation.finish()
            }

            // Nettoyage best-effort : annule le consumer et retire la règle côté bus.
            continuation.onTermination = { @Sendable _ in
                consumerTask.cancel()
                try? connection.removeMatch(rule, timeoutMS: 2000)
            }
        }

        return filtered
    }
}

// MARK: - Helpers d’appel C natifs (1 string argument)

extension DBusConnection {
    // swiftlint:disable function_parameter_count
    /// Envoie un appel méthode avec un unique argument string et vérifie l'absence d'erreur DBus.
    fileprivate func sendSingleStringArg(
        destination: String,
        path: String,
        interface: String,
        method: String,
        value: String,
        timeoutMS: Int32
    ) throws {
        guard let connectionPointer = raw else {
            throw Error.failed("connection is nil")
        }
        try sendSingleStringArgRaw(
            connectionPointer: connectionPointer,
            destination: destination,
            path: path,
            interface: interface,
            method: method,
            value: value,
            timeoutMS: timeoutMS
        )
    }
    // swiftlint:enable function_parameter_count
}

// swiftlint:disable function_parameter_count
/// Variante « statique » pour éviter de capturer `self` dans des closures `@Sendable`.
@inline(__always)
private func sendSingleStringArgRaw(
    connectionPointer: OpaquePointer,
    destination: String,
    path: String,
    interface: String,
    method: String,
    value: String,
    timeoutMS: Int32
) throws {
    // Crée le message méthode
    guard
        let message = destination.withCString({ destPtr in
            path.withCString { pathPtr in
                interface.withCString { ifacePtr in
                    method.withCString { methPtr in
                        dbus_message_new_method_call(destPtr, pathPtr, ifacePtr, methPtr)
                    }
                }
            }
        })
    else {
        throw DBusConnection.Error.failed("dbus_message_new_method_call failed")
    }

    // Append: 1 argument STRING (value)
    var iterator = DBusMessageIter()
    dbus_message_iter_init_append(message, &iterator)
    value.withCString { cString in
        var pointer: UnsafePointer<CChar>? = cString
        withUnsafePointer(to: &pointer) { doublePointer in
            _ = dbus_message_iter_append_basic(&iterator, DBusTypeCode.STRING, UnsafeRawPointer(doublePointer))
        }
    }

    // Appel synchrone avec timeout
    let reply = dbus_connection_send_with_reply_and_block(connectionPointer, message, timeoutMS, nil)
    dbus_message_unref(message)

    guard let replyMessage = reply else {
        throw DBusConnection.Error.failed("no reply from bus")
    }
    defer { dbus_message_unref(replyMessage) }

    // Si ERROR -> lever une erreur Swift
    if dbus_message_get_type(replyMessage) == DBusMsgType.ERROR {
        let name =
            dbus_message_get_error_name(replyMessage).map { String(cString: $0) }
            ?? "org.freedesktop.DBus.Error.Failed"
        throw DBusConnection.Error.failed("DBus error: \(name) on \(interface).\(method)")
    }
}
// swiftlint:enable function_parameter_count
