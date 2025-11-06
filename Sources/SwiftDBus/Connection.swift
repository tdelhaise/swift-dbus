import CDbus

public final class DBusConnection {
    private var raw: OpaquePointer?

    public enum Error: Swift.Error {
        case failed(String)
    }

    public init(sessionBus: Bool = true) throws {
        var err = DBusError()
        dbus_error_init(&err)
        self.raw = sessionBus
            ? dbus_bus_get(DBUS_BUS_SESSION, &err)
            : dbus_bus_get(DBUS_BUS_SYSTEM, &err)

        if dbus_error_is_set(&err) != 0 {
            let message = err.message.flatMap { String(cString: $0) } ?? "unknown"
            dbus_error_free(&err)
            throw Error.failed("dbus_bus_get failed: \(message)")
        }
        guard self.raw != nil else {
            throw Error.failed("dbus_bus_get returned nil")
        }
    }

    deinit {
        if let c = raw {
            dbus_connection_unref(c)
        }
    }

    public func uniqueName() throws -> String {
        guard let c = raw else { throw Error.failed("connection is nil") }
        if let ptr = dbus_bus_get_unique_name(c) {
            return String(cString: ptr)
        } else {
            throw Error.failed("unique name is nil")
        }
    }
}

