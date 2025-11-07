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
    public static func methodCall(
        destination: String,
        path: String,
        interface: String,
        method: String
    ) throws -> DBusMessageRef {
        let msg = try DBusMessageRef.wrapOrThrow(
            dbus_message_new_method_call(
                destination, path, interface, method
            ),
            "dbus_message_new_method_call failed"
        )
        return msg
    }
}

public enum DBusMessageDecode {
    public static func firstString(_ msg: DBusMessageRef) throws -> String {
        let typeCode = dbus_message_get_type(msg.raw)

        if typeCode == DBusMsgType.ERROR {
            let name =
                dbus_message_get_error_name(msg.raw).map { String(cString: $0) }
                ?? "org.freedesktop.DBus.Error.Failed"
            throw DBusMessageError.dbusError(name: name, message: "DBus returned error")
        }

        guard typeCode == DBusMsgType.METHOD_RETURN else {
            throw DBusMessageError.invalidType(
                expected: DBusMsgType.METHOD_RETURN,
                got: typeCode
            )
        }

        var iter = DBusMessageIter()
        if dbus_message_iter_init(msg.raw, &iter) == 0 {
            throw DBusMessageError.decodeFailed("no return arguments")
        }
        let argType = dbus_message_iter_get_arg_type(&iter)
        guard argType == DBusTypeCode.STRING else {
            throw DBusMessageError.decodeFailed("first arg is not string (got \(dbusTypeDebugString(argType)))")
        }
        var cString: UnsafePointer<CChar>?
        dbus_message_iter_get_basic(&iter, &cString)
        guard let nonNullCString = cString else {
            throw DBusMessageError.decodeFailed("null string")
        }
        return String(cString: nonNullCString)
    }
}
