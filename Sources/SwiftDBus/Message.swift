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
        let message = try DBusMessageRef.wrapOrThrow(
            dbus_message_new_method_call(destination, path, interface, method),
            "dbus_message_new_method_call failed"
        )
        return message
    }

    /// Méthode multi-arguments via un writer d’append DBus.
    public static func methodCall(
        destination: String,
        path: String,
        interface: String,
        method: String,
        buildArguments: (inout DBusAppendWriter) throws -> Void
    ) throws -> DBusMessageRef {
        let message = try methodCall(
            destination: destination,
            path: path,
            interface: interface,
            method: method
        )
        var writer = DBusAppendWriter(message: message)
        try buildArguments(&writer)
        return message
    }

    /// Version 1 argument String (conserve l’API M2.1).
    public static func methodCall1StringArg(
        destination: String,
        path: String,
        interface: String,
        method: String,
        arg: String
    ) throws -> DBusMessageRef {
        try methodCall(
            destination: destination,
            path: path,
            interface: interface,
            method: method
        ) { writer in
            try writer.appendString(arg)
        }
    }
}

public enum DBusMessageDecode {
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

        return try DBusMarshal.firstString(message)
    }

    public static func firstArrayOfStrings(_ message: DBusMessageRef) throws -> [String] {
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

        return try DBusMarshal.firstArrayOfStrings(message)
    }
}
