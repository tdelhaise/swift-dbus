import CDbus

public final class DBusConnection {
    private var raw: OpaquePointer?

    public enum Error: Swift.Error {
        case failed(String)
    }

    public init(sessionBus: Bool = true) throws {
        var error = DBusError()
        dbus_error_init(&error)
        self.raw =
            sessionBus
            ? dbus_bus_get(DBUS_BUS_SESSION, &error)
            : dbus_bus_get(DBUS_BUS_SYSTEM, &error)

        if dbus_error_is_set(&error) != 0 {
            let message = error.message.flatMap { String(cString: $0) } ?? "unknown"
            dbus_error_free(&error)
            throw Error.failed("dbus_bus_get failed: \(message)")
        }
        guard self.raw != nil else {
            throw Error.failed("dbus_bus_get returned nil")
        }
    }

    deinit {
        if let connection = raw {
            dbus_connection_unref(connection)
        }
    }

    public func uniqueName() throws -> String {
        guard let connection = raw else { throw Error.failed("connection is nil") }
        if let stringPointer = dbus_bus_get_unique_name(connection) {
            return String(cString: stringPointer)
        } else {
            throw Error.failed("unique name is nil")
        }
    }
}
