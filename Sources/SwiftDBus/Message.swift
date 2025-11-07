import CDbus

public enum DBusMessageError: Swift.Error, CustomStringConvertible {
    case creationFailed(String)
    case invalidType(expected: Int32, got: Int32)
    case dbusError(name: String, message: String)
    case decodeFailed(String)

    public var description: String {
        switch self {
        case .creationFailed(let reason):
            return "creationFailed(\(reason))"
        case .invalidType(let expected, let got):
            return "invalidType(expected:\(expected) got:\(got))"
        case .dbusError(let name, let message):
            return "dbusError(\(name): \(message))"
        case .decodeFailed(let reason):
            return "decodeFailed(\(reason))"
        }
    }
}

public enum DBusMessageBuilder {
    /// Construit un `METHOD_CALL` sans arguments.
    public static func methodCall(
        destination: String,
        path: String,
        interface: String,
        method: String
    ) throws -> DBusMessageRef {
        let message = try DBusMessageRef.wrapOrThrow(
            dbus_message_new_method_call(destination, path, interface, method),
            "dbus_message_new_method_call failed"
        )
        return message
    }

    /// Variante avec un seul argument `String`.
    public static func methodCall1StringArg(
        destination: String,
        path: String,
        interface: String,
        method: String,
        arg: String
    ) throws -> DBusMessageRef {
        let message = try methodCall(
            destination: destination,
            path: path,
            interface: interface,
            method: method
        )
        try DBusMarshal.appendString(message, arg)
        return message
    }
}

public enum DBusMessageDecode {
    /// Récupère le **premier argument String** d’un `METHOD_RETURN`.
    public static func firstString(_ message: DBusMessageRef) throws -> String {
        let typeCode = dbus_message_get_type(message.raw)

        if typeCode == DBusMsgType.ERROR {
            let errorName =
                dbus_message_get_error_name(message.raw).map { String(cString: $0) }
                ?? "org.freedesktop.DBus.Error.Failed"
            throw DBusMessageError.dbusError(name: errorName, message: "DBus returned error")
        }

        guard typeCode == DBusMsgType.METHOD_RETURN else {
            throw DBusMessageError.invalidType(
                expected: DBusMsgType.METHOD_RETURN,
                got: typeCode
            )
        }

        var readIterator = DBusMessageIter()
        guard dbus_message_iter_init(message.raw, &readIterator) != 0 else {
            throw DBusMessageError.decodeFailed("no return arguments")
        }

        let argTypeCode = dbus_message_iter_get_arg_type(&readIterator)
        guard argTypeCode == DBusTypeCode.STRING else {
            throw DBusMessageError.decodeFailed(
                "first arg is not string (got \(dbusTypeDebugString(argTypeCode)))"
            )
        }

        var cStringPointer: UnsafePointer<CChar>?
        dbus_message_iter_get_basic(&readIterator, &cStringPointer)
        guard let nonNullCString = cStringPointer else {
            throw DBusMessageError.decodeFailed("null string")
        }
        return String(cString: nonNullCString)
    }
}
