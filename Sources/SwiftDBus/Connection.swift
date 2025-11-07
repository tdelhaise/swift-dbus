import CDbus
import Dispatch

public final class DBusConnection: @unchecked Sendable {
    public enum Bus {
        case session, system
        fileprivate var raw: DBusBusType { self == .session ? DBUS_BUS_SESSION : DBUS_BUS_SYSTEM }
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case failed(String)
        public var description: String {
            switch self {
            case .failed(let message):
                return message
            }
        }
    }

    private var raw: OpaquePointer?
    private var source: DispatchSourceRead?
    private let workQueue = DispatchQueue(label: "swift-dbus.connection", qos: .userInitiated)

    // MARK: Init / Deinit

    public init(bus: Bus) throws {
        self.raw = try withDBusError { errorPointer in
            dbus_bus_get(bus.raw, errorPointer)
        }
        guard self.raw != nil else {
            throw Error.failed("dbus_bus_get returned nil")
        }

        dbus_connection_set_exit_on_disconnect(self.raw, 0)
        _ = dbus_connection_set_timeout_functions(self.raw, nil, nil, nil, nil, nil)
    }

    deinit {
        stopPump()
        if let connectionPointer = raw {
            dbus_connection_unref(connectionPointer)
        }
    }

    // MARK: Infos

    public func uniqueName() throws -> String {
        guard let connectionPointer = raw else {
            throw Error.failed("connection is nil")
        }
        guard let cString = dbus_bus_get_unique_name(connectionPointer) else {
            throw Error.failed("unique name is nil")
        }
        return String(cString: cString)
    }

    /// Récupère le file descriptor sous-jacent (non bloquant).
    public func unixFD() throws -> Int32 {
        guard let connectionPointer = raw else {
            throw Error.failed("connection is nil")
        }
        var fileDescriptor: Int32 = -1
        if dbus_connection_get_unix_fd(connectionPointer, &fileDescriptor) == 0 || fileDescriptor < 0 {
            throw Error.failed("dbus_connection_get_unix_fd failed")
        }
        return fileDescriptor
    }

    // MARK: Pump & Messages

    /// Démarre une boucle I/O et renvoie un flux de messages entrants.
    /// Le flux se termine si la source est annulée (via `stopPump()` ou deinit).
    public func messages() throws -> AsyncStream<DBusMessageRef> {
        let fileDescriptor = try unixFD()
        let stream = AsyncStream<DBusMessageRef> { continuation in
            workQueue.async { [weak self] in
                guard let self, let connectionPointer = self.raw else {
                    continuation.finish()
                    return
                }

                let readSource = DispatchSource.makeReadSource(
                    fileDescriptor: fileDescriptor,
                    queue: self.workQueue
                )
                self.source = readSource

                readSource.setEventHandler { [weak self] in
                    guard let self, let connectionPointer = self.raw else {
                        continuation.finish()
                        return
                    }
                    _ = dbus_connection_read_write_dispatch(connectionPointer, 0)
                    while let messagePointer = dbus_connection_pop_message(connectionPointer) {
                        let messageRef = DBusMessageRef(taking: messagePointer)
                        continuation.yield(messageRef)
                    }
                }

                readSource.setCancelHandler {
                    continuation.finish()
                }

                readSource.resume()

                _ = dbus_connection_read_write_dispatch(connectionPointer, 0)
                while let messagePointer = dbus_connection_pop_message(connectionPointer) {
                    continuation.yield(DBusMessageRef(taking: messagePointer))
                }
            }
        }
        return stream
    }

    public func stopPump() {
        workQueue.sync {
            source?.cancel()
            source = nil
        }
    }
}

// MARK: - Appels (M2 / M2.1 / M2.2)

extension DBusConnection {
    /// Envoie un appel DBus et renvoie la réponse brute (ou jette sur erreur DBus).
    public func callRaw(
        destination: String,
        path: String,
        interface: String,
        method: String,
        timeoutMS: Int32 = 2000
    ) throws -> DBusMessageRef {
        guard let connectionPointer = raw else {
            throw Error.failed("connection is nil")
        }

        let requestMessage = try DBusMessageBuilder.methodCall(
            destination: destination,
            path: path,
            interface: interface,
            method: method
        )

        let replyPointer: OpaquePointer? = try withDBusError { errorPointer in
            dbus_connection_send_with_reply_and_block(
                connectionPointer,
                requestMessage.raw,
                timeoutMS,
                errorPointer
            )
        }
        guard let nonNullReplyPointer = replyPointer else {
            throw Error.failed("send_with_reply_and_block returned nil")
        }

        let typeCode = dbus_message_get_type(nonNullReplyPointer)
        if typeCode == DBusMsgType.ERROR {
            let errorName =
                dbus_message_get_error_name(nonNullReplyPointer).map { String(cString: $0) }
                ?? "org.freedesktop.DBus.Error.Failed"
            throw DBusMessageError.dbusError(name: errorName, message: "DBus returned error")
        }

        return DBusMessageRef(taking: nonNullReplyPointer)
    }

    /// org.freedesktop.DBus.GetId() -> String
    public func getBusId(timeoutMS: Int32 = 2000) throws -> String {
        let replyMessage = try callRaw(
            destination: "org.freedesktop.DBus",
            path: "/org/freedesktop/DBus",
            interface: "org.freedesktop.DBus",
            method: "GetId",
            timeoutMS: timeoutMS
        )
        return try DBusMessageDecode.firstString(replyMessage)
    }

    /// org.freedesktop.DBus.Peer.Ping() -> aucune valeur
    public func pingPeer(
        destination: String = "org.freedesktop.DBus",
        path: String = "/org/freedesktop/DBus",
        interface: String = "org.freedesktop.DBus.Peer",
        timeoutMS: Int32 = 2000
    ) throws {
        _ = try callRaw(
            destination: destination,
            path: path,
            interface: interface,
            method: "Ping",
            timeoutMS: timeoutMS
        )
    }

    /// org.freedesktop.DBus.GetNameOwner(name: s) -> s
    public func getNameOwner(_ wellKnownName: String, timeoutMS: Int32 = 2000) throws -> String {
        guard let connectionPointer = raw else {
            throw Error.failed("connection is nil")
        }

        let requestMessage = try DBusMessageBuilder.methodCall1StringArg(
            destination: "org.freedesktop.DBus",
            path: "/org/freedesktop/DBus",
            interface: "org.freedesktop.DBus",
            method: "GetNameOwner",
            arg: wellKnownName
        )

        let replyPointer: OpaquePointer? = try withDBusError { errorPointer in
            dbus_connection_send_with_reply_and_block(
                connectionPointer,
                requestMessage.raw,
                timeoutMS,
                errorPointer
            )
        }
        guard let nonNullReplyPointer = replyPointer else {
            throw Error.failed("send_with_reply_and_block returned nil")
        }

        let typeCode = dbus_message_get_type(nonNullReplyPointer)
        if typeCode == DBusMsgType.ERROR {
            let errorName =
                dbus_message_get_error_name(nonNullReplyPointer).map { String(cString: $0) }
                ?? "org.freedesktop.DBus.Error.Failed"
            throw DBusMessageError.dbusError(name: errorName, message: "DBus returned error")
        }

        let replyMessage = DBusMessageRef(taking: nonNullReplyPointer)
        return try DBusMessageDecode.firstString(replyMessage)
    }

    /// org.freedesktop.DBus.ListNames() -> as
    public func listNames(timeoutMS: Int32 = 2000) throws -> [String] {
        let replyMessage = try callRaw(
            destination: "org.freedesktop.DBus",
            path: "/org/freedesktop/DBus",
            interface: "org.freedesktop.DBus",
            method: "ListNames",
            timeoutMS: timeoutMS
        )
        return try DBusMessageDecode.firstArrayOfStrings(replyMessage)
    }
}
