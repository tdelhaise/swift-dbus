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

    public init(bus: Bus) throws {
        self.raw = try withDBusError { err in
            dbus_bus_get(bus.raw, err)
        }
        guard self.raw != nil else {
            throw Error.failed("dbus_bus_get returned nil")
        }

        dbus_connection_set_exit_on_disconnect(self.raw, 0)
        _ = dbus_connection_set_timeout_functions(self.raw, nil, nil, nil, nil, nil)
    }

    deinit {
        stopPump()
        if let connectionPtr = raw {
            dbus_connection_unref(connectionPtr)
        }
    }

    public func uniqueName() throws -> String {
        guard let connection = raw else {
            throw Error.failed("connection is nil")
        }
        guard let cstr = dbus_bus_get_unique_name(connection) else {
            throw Error.failed("unique name is nil")
        }
        return String(cString: cstr)
    }

    public func unixFD() throws -> Int32 {
        guard let connection = raw else {
            throw Error.failed("connection is nil")
        }
        var fd: Int32 = -1
        if dbus_connection_get_unix_fd(connection, &fd) == 0 || fd < 0 {
            throw Error.failed("dbus_connection_get_unix_fd failed")
        }
        return fd
    }

    public func messages() throws -> AsyncStream<DBusMessageRef> {
        let fd = try unixFD()
        let stream = AsyncStream<DBusMessageRef> { continuation in
            workQueue.async { [weak self] in
                guard let self, let conn = self.raw else {
                    continuation.finish()
                    return
                }

                let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: self.workQueue)
                self.source = src

                src.setEventHandler { [weak self] in
                    guard let self, let conn = self.raw else {
                        continuation.finish()
                        return
                    }
                    _ = dbus_connection_read_write_dispatch(conn, 0)
                    while let msgPtr = dbus_connection_pop_message(conn) {
                        let ref = DBusMessageRef(taking: msgPtr)
                        continuation.yield(ref)
                    }
                }

                src.setCancelHandler {
                    continuation.finish()
                }

                src.resume()

                _ = dbus_connection_read_write_dispatch(conn, 0)
                while let msgPtr = dbus_connection_pop_message(conn) {
                    continuation.yield(DBusMessageRef(taking: msgPtr))
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

// MARK: - Calls (M2 minimal)

extension DBusConnection {
    public func callRaw(
        destination: String,
        path: String,
        interface: String,
        method: String,
        timeoutMS: Int32 = 2000
    ) throws -> DBusMessageRef {
        guard let conn = raw else {
            throw Error.failed("connection is nil")
        }

        let callMsg = try DBusMessageBuilder.methodCall(
            destination: destination,
            path: path,
            interface: interface,
            method: method
        )

        let replyPtr: OpaquePointer? = try withDBusError { err in
            dbus_connection_send_with_reply_and_block(conn, callMsg.raw, timeoutMS, err)
        }
        guard let reply = replyPtr else {
            throw Error.failed("send_with_reply_and_block returned nil")
        }
        let replyRef = DBusMessageRef(taking: reply)

        let typeCode = dbus_message_get_type(reply)
        if typeCode == DBusMsgType.ERROR {
            let name =
                dbus_message_get_error_name(reply).map { String(cString: $0) }
                ?? "org.freedesktop.DBus.Error.Failed"
            throw DBusMessageError.dbusError(name: name, message: "DBus returned error")
        }
        return replyRef
    }

    public func getBusId(timeoutMS: Int32 = 2000) throws -> String {
        let reply = try callRaw(
            destination: "org.freedesktop.DBus",
            path: "/org/freedesktop/DBus",
            interface: "org.freedesktop.DBus",
            method: "GetId",
            timeoutMS: timeoutMS
        )
        return try DBusMessageDecode.firstString(reply)
    }

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
}
