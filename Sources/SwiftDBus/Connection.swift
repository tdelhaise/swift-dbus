// Sources/SwiftDBus/Connection.swift
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
            case .failed(let messageString):
                return messageString
            }
        }
    }

    private var raw: OpaquePointer?
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "swift-dbus.connection", qos: .userInitiated)

    // MARK: Init / Deinit

    public init(bus: Bus) throws {
        self.raw = try withDBusError { dbusError in
            dbus_bus_get(bus.raw, dbusError)
        }
        guard self.raw != nil else {
            throw Error.failed("dbus_bus_get returned nil")
        }

        // Mettre la connexion en non-bloquant
        dbus_connection_set_exit_on_disconnect(self.raw, 0)
        _ = dbus_connection_set_timeout_functions(self.raw, nil, nil, nil, nil, nil)  // placeholder, pas d’override
    }

    deinit {
        stopPump()
        if let connection = raw {
            dbus_connection_unref(connection)
        }
    }

    // MARK: Infos

    public func uniqueName() throws -> String {
        guard let connection = raw else {
            throw Error.failed("connection is nil")
        }
        guard let cstr = dbus_bus_get_unique_name(connection) else {
            throw Error.failed("unique name is nil")
        }
        return String(cString: cstr)
    }

    /// Tente de récupérer le file descriptor sous-jacent (non bloquant).
    public func unixFD() throws -> Int32 {
        guard let connection = raw else {
            throw Error.failed("connection is nil")
        }
        var fileDescriptor: Int32 = -1
        if dbus_connection_get_unix_fd(connection, &fileDescriptor) == 0 || fileDescriptor < 0 {
            throw Error.failed("dbus_connection_get_unix_fd failed")
        }
        return fileDescriptor
    }

    // MARK: Pump & Messages

    /// Démarre une boucle I/O minimale et renvoie un flux de messages entrants.
    /// Le flux s’arrête si la source est annulée (via `stopPump()` ou deinit).
    public func messages() throws -> AsyncStream<DBusMessageRef> {
        let fileDescriptor = try unixFD()
        let stream = AsyncStream<DBusMessageRef> { continuation in
            queue.async { [weak self] in
                guard let self, let connection = self.raw else {
                    continuation.finish()
                    return
                }

                // Source read sur le FD de dbus
                let src = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: self.queue)
                self.source = src

                src.setEventHandler { [weak self] in
                    guard let self, let connection = self.raw else {
                        continuation.finish()
                        return
                    }
                    // Libdbus: lire/écrire/dispatcher sans bloquer
                    _ = dbus_connection_read_write_dispatch(connection, 0)

                    // Popper tous les messages disponibles et les émettre
                    while let msgPtr = dbus_connection_pop_message(connection) {
                        let ref = DBusMessageRef(taking: msgPtr)
                        continuation.yield(ref)
                    }
                }

                src.setCancelHandler {
                    continuation.finish()
                }

                // Démarre
                src.resume()

                // Tick initial non bloquant pour drainer ce qui est déjà en attente
                _ = dbus_connection_read_write_dispatch(connection, 0)
                while let msgPtr = dbus_connection_pop_message(connection) {
                    continuation.yield(DBusMessageRef(taking: msgPtr))
                }
            }
        }
        return stream
    }

    public func stopPump() {
        queue.sync {
            source?.cancel()
            source = nil
        }
    }
}
