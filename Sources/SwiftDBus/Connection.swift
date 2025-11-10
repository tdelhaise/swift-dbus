import CDbus
import Dispatch
import Foundation

public final class DBusConnection: @unchecked Sendable {

    // MARK: - Types

    public enum Bus {
        case session
        case system

        /// Conversion vers la constante C
        var cValue: DBusBusType {
            switch self {
            case .session:
                return DBUS_BUS_SESSION
            case .system:
                return DBUS_BUS_SYSTEM
            }
        }
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case failed(String)
        case invalid(String)

        public var description: String {
            switch self {
            case .failed(let message):
                return "DBusConnection.failed(\(message))"
            case .invalid(let message):
                return "DBusConnection.invalid(\(message))"
            }
        }
    }

    // MARK: - State

    /// Pointeur C sous-jacent (exposé au module pour Signals.swift)
    internal var raw: OpaquePointer?
    private var source: DispatchSourceRead?
    private let workQueue = DispatchQueue(label: "swift-dbus.connection", qos: .userInitiated)
    private var messageContinuations: [UUID: AsyncStream<DBusMessageRef>.Continuation] = [:]
    private let continuationsLock = NSLock()

    public init() {}

    public convenience init(bus: Bus) throws {
        self.init()
        try open(bus)
    }

    deinit {
        finishAllMessageContinuations()
        source?.cancel()
        source = nil
        if let pointer = raw {
            dbus_connection_close(pointer)
            dbus_connection_unref(pointer)
        }
        raw = nil
    }

    // MARK: - Open

    /// Ouvre une nouvelle connexion DBus sur le bus indiqué.
    @discardableResult
    public static func open(_ bus: Bus) throws -> DBusConnection {
        let connection = DBusConnection()
        try connection.open(bus)
        return connection
    }

    public func open(_ bus: Bus) throws {
        if raw != nil { return }

        let connectionPointer: OpaquePointer? = try withDBusError { errorPointer in
            dbus_bus_get_private(bus.cValue, errorPointer)
        }

        guard let connectionPointer else {
            throw Error.failed("dbus_bus_get returned null")
        }

        dbus_connection_set_exit_on_disconnect(connectionPointer, 0)
        raw = connectionPointer

        // Préparation de la source d'événements
        var fd: Int32 = -1
        let gotFD = dbus_connection_get_unix_fd(connectionPointer, &fd)
        guard gotFD != 0, fd >= 0 else {
            throw Error.failed("dbus_connection_get_unix_fd failed")
        }

        let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: workQueue)
        readSource.setEventHandler { [weak self] in
            guard let self, let connection = self.raw else { return }
            self.continuationsLock.lock()
            let hasContinuations = !self.messageContinuations.isEmpty
            self.continuationsLock.unlock()
            guard hasContinuations else { return }
            _ = dbus_connection_read_write(connection, 0)
            self.drainMessages(connection)
        }
        source = readSource
        readSource.resume()
    }

    // MARK: - Unique name

    /// Renvoie le nom unique (ex: ":1.42").
    public func uniqueName() throws -> String {
        guard let connection = raw else {
            throw Error.failed("connection is nil")
        }
        guard let cString = dbus_bus_get_unique_name(connection) else {
            throw Error.failed("dbus_bus_get_unique_name returned null")
        }
        return String(cString: cString)
    }

    // MARK: - Messages stream

    /// Crée un flux asynchrone de messages DBus.
    public func messages() throws -> AsyncStream<DBusMessageRef> {
        guard raw != nil else {
            throw Error.failed("connection is nil")
        }

        return AsyncStream<DBusMessageRef> { continuation in
            let token = self.registerMessageContinuation(continuation)
            workQueue.async { [weak self] in
                guard let self, let connection = self.raw else {
                    continuation.finish()
                    return
                }
                self.drainMessages(connection)
            }

            continuation.onTermination = { [weak self] _ in
                self?.removeMessageContinuation(token)
            }
        }
    }

    internal func withRawPointer<T>(_ body: (OpaquePointer) throws -> T) rethrows -> T {
        try workQueue.sync {
            guard let connection = raw else {
                throw Error.failed("connection is nil")
            }
            return try body(connection)
        }
    }

    /// Draine la file DBus et diffuse les messages aux continuations enregistrées.
    private func drainMessages(_ connection: OpaquePointer) {
        continuationsLock.lock()
        let hasContinuations = !messageContinuations.isEmpty
        continuationsLock.unlock()
        guard hasContinuations else { return }
        while true {
            guard let rawMessage = dbus_connection_pop_message(connection) else { break }

            let ref = DBusMessageRef(taking: rawMessage)
            broadcastMessage(ref)
        }
    }

    /// Arrête la source d'événements et termine les streams messages actifs.
    public func stopPump() {
        finishAllMessageContinuations()
        source?.cancel()
        source = nil
    }

    // MARK: - Appels synchrones bas niveau

    // swiftlint:disable function_parameter_count
    /// Appel méthode générique, avec écriture d’arguments via closure.
    public func callRaw(
        destination: String,
        path: String,
        interface: String,
        method: String,
        timeoutMS: Int32,
        argsWriter: (inout DBusMessageIter) throws -> Void
    ) throws -> DBusMessageRef {
        guard let connection = raw else {
            throw Error.failed("connection is nil")
        }

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
            throw Error.failed("dbus_message_new_method_call failed")
        }

        var iterator = DBusMessageIter()
        dbus_message_iter_init_append(message, &iterator)
        do {
            try argsWriter(&iterator)
        } catch {
            dbus_message_unref(message)
            throw error
        }

        // Envoi synchrone avec timeout
        let replyPointer = dbus_connection_send_with_reply_and_block(connection, message, timeoutMS, nil)
        dbus_message_unref(message)

        guard let replyPointer else {
            throw Error.failed("no reply from bus")
        }

        // Vérifie s’il s’agit d’une erreur DBus
        let type = dbus_message_get_type(replyPointer)
        if type == DBusMsgType.ERROR {
            let name =
                dbus_message_get_error_name(replyPointer).map { String(cString: $0) }
                ?? "org.freedesktop.DBus.Error.Failed"
            dbus_message_unref(replyPointer)
            throw Error.failed("DBus error: \(name) for \(interface).\(method)")
        }

        return DBusMessageRef(taking: replyPointer)
    }
    // swiftlint:enable function_parameter_count

    // MARK: - Bus names

    /// Demande un nom de bus (org.example.App). Retourne le code DBus_REQUEST_NAME_REPLY_*.
    @discardableResult
    public func requestName(_ name: String, flags: UInt32 = 0) throws -> Int32 {
        guard let connection = raw else {
            throw Error.failed("connection is nil")
        }

        let result: Int32 = try withDBusError { errorPointer in
            name.withCString { cName in
                dbus_bus_request_name(connection, cName, flags, errorPointer)
            }
        }
        return result
    }

    /// Relâche un nom de bus précédemment acquis.
    @discardableResult
    public func releaseName(_ name: String) throws -> Int32 {
        guard let connection = raw else {
            throw Error.failed("connection is nil")
        }

        let result: Int32 = try withDBusError { errorPointer in
            name.withCString { cName in
                dbus_bus_release_name(connection, cName, errorPointer)
            }
        }
        return result
    }

    // MARK: - org.freedesktop.DBus helpers

    public func getBusId(timeoutMS: Int32 = 2000) throws -> String {
        let reply = try callRaw(
            destination: "org.freedesktop.DBus",
            path: "/org/freedesktop/DBus",
            interface: "org.freedesktop.DBus",
            method: "GetId",
            timeoutMS: timeoutMS
        ) { _ in }
        return try DBusMarshal.firstString(reply)
    }

    public func getNameOwner(_ name: String, timeoutMS: Int32 = 2000) throws -> String {
        let reply = try callRaw(
            destination: "org.freedesktop.DBus",
            path: "/org/freedesktop/DBus",
            interface: "org.freedesktop.DBus",
            method: "GetNameOwner",
            timeoutMS: timeoutMS
        ) { iterator in
            try name.withCString { cString in
                var pointer: UnsafePointer<CChar>? = cString
                let ok = dbus_message_iter_append_basic(&iterator, DBusTypeCode.STRING, &pointer)
                if ok == 0 {
                    throw Error.failed("failed to append string argument for GetNameOwner")
                }
            }
        }
        return try DBusMarshal.firstString(reply)
    }

    public func listNames(timeoutMS: Int32 = 2000) throws -> [String] {
        let reply = try callRaw(
            destination: "org.freedesktop.DBus",
            path: "/org/freedesktop/DBus",
            interface: "org.freedesktop.DBus",
            method: "ListNames",
            timeoutMS: timeoutMS
        ) { _ in }
        return try DBusMarshal.firstArrayOfStrings(reply)
    }

    public func pingPeer(timeoutMS: Int32 = 2000) throws {
        _ = try callRaw(
            destination: "org.freedesktop.DBus",
            path: "/org/freedesktop/DBus",
            interface: "org.freedesktop.DBus.Peer",
            method: "Ping",
            timeoutMS: timeoutMS
        ) { _ in }
    }

    public func getMachineId(timeoutMS: Int32 = 2000) throws -> String {
        let reply = try callRaw(
            destination: "org.freedesktop.DBus",
            path: "/org/freedesktop/DBus",
            interface: "org.freedesktop.DBus",
            method: "GetMachineId",
            timeoutMS: timeoutMS
        ) { _ in }
        return try DBusMarshal.firstString(reply)
    }

    // MARK: - Message continuation bookkeeping

    private func registerMessageContinuation(
        _ continuation: AsyncStream<DBusMessageRef>.Continuation
    ) -> UUID {
        continuationsLock.lock()
        defer { continuationsLock.unlock() }
        let token = UUID()
        messageContinuations[token] = continuation
        return token
    }

    private func removeMessageContinuation(_ token: UUID) {
        continuationsLock.lock()
        messageContinuations.removeValue(forKey: token)
        continuationsLock.unlock()
    }

    private func broadcastMessage(_ message: DBusMessageRef) {
        continuationsLock.lock()
        let continuations = Array(messageContinuations.values)
        continuationsLock.unlock()
        for continuation in continuations {
            continuation.yield(message)
        }
    }

    private func finishAllMessageContinuations() {
        continuationsLock.lock()
        let continuations = Array(messageContinuations.values)
        messageContinuations.removeAll()
        continuationsLock.unlock()
        for continuation in continuations {
            continuation.finish()
        }
    }
}
