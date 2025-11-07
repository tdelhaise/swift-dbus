import CDbus

public enum DBusMarshalError: Swift.Error, CustomStringConvertible {
    case appendFailed(String)
    case initIterFailed
    case invalidType(expected: Int32, got: Int32)
    case null

    public var description: String {
        switch self {
        case .appendFailed(let reason):
            return "appendFailed(\(reason))"
        case .initIterFailed:
            return "initIterFailed"
        case .invalidType(let expected, let got):
            return "invalidType(expected:\(expected) got:\(got))"
        case .null:
            return "null"
        }
    }
}

public enum DBusMarshal {
    // MARK: - Append

    public static func appendString(_ message: DBusMessageRef, _ value: String) throws {
        var appendIterator = DBusMessageIter()
        dbus_message_iter_init_append(message.raw, &appendIterator)

        try value.withCString { cStringPointer in
            var pointerToCString: UnsafePointer<CChar>? = cStringPointer
            let success = dbus_message_iter_append_basic(&appendIterator, DBusTypeCode.STRING, &pointerToCString)
            if success == 0 {
                throw DBusMarshalError.appendFailed("string")
            }
        }
    }

    public static func appendBool(_ message: DBusMessageRef, _ value: Bool) throws {
        var appendIterator = DBusMessageIter()
        dbus_message_iter_init_append(message.raw, &appendIterator)

        var boolValue: dbus_bool_t = value ? 1 : 0
        let success = dbus_message_iter_append_basic(&appendIterator, DBusTypeCode.BOOLEAN, &boolValue)
        if success == 0 {
            throw DBusMarshalError.appendFailed("bool")
        }
    }

    public static func appendInt32(_ message: DBusMessageRef, _ value: Int32) throws {
        var appendIterator = DBusMessageIter()
        dbus_message_iter_init_append(message.raw, &appendIterator)

        var int32Value = value
        let success = dbus_message_iter_append_basic(&appendIterator, DBusTypeCode.INT32, &int32Value)
        if success == 0 {
            throw DBusMarshalError.appendFailed("int32")
        }
    }

    public static func appendDouble(_ message: DBusMessageRef, _ value: Double) throws {
        var appendIterator = DBusMessageIter()
        dbus_message_iter_init_append(message.raw, &appendIterator)

        var doubleValue = value
        let success = dbus_message_iter_append_basic(&appendIterator, DBusTypeCode.DOUBLE, &doubleValue)
        if success == 0 {
            throw DBusMarshalError.appendFailed("double")
        }
    }

    // MARK: - Decode first

    public static func firstString(_ message: DBusMessageRef) throws -> String {
        var readIterator = DBusMessageIter()
        guard dbus_message_iter_init(message.raw, &readIterator) != 0 else {
            throw DBusMarshalError.initIterFailed
        }

        let typeCode = dbus_message_iter_get_arg_type(&readIterator)
        guard typeCode == DBusTypeCode.STRING else {
            throw DBusMarshalError.invalidType(expected: DBusTypeCode.STRING, got: typeCode)
        }

        var cStringPointer: UnsafePointer<CChar>?
        dbus_message_iter_get_basic(&readIterator, &cStringPointer)
        guard let nonNullCString = cStringPointer else {
            throw DBusMarshalError.null
        }
        return String(cString: nonNullCString)
    }

    public static func firstBool(_ message: DBusMessageRef) throws -> Bool {
        var readIterator = DBusMessageIter()
        guard dbus_message_iter_init(message.raw, &readIterator) != 0 else {
            throw DBusMarshalError.initIterFailed
        }

        let typeCode = dbus_message_iter_get_arg_type(&readIterator)
        guard typeCode == DBusTypeCode.BOOLEAN else {
            throw DBusMarshalError.invalidType(expected: DBusTypeCode.BOOLEAN, got: typeCode)
        }

        var boolValue: dbus_bool_t = 0
        dbus_message_iter_get_basic(&readIterator, &boolValue)
        return boolValue != 0
    }

    public static func firstInt32(_ message: DBusMessageRef) throws -> Int32 {
        var readIterator = DBusMessageIter()
        guard dbus_message_iter_init(message.raw, &readIterator) != 0 else {
            throw DBusMarshalError.initIterFailed
        }

        let typeCode = dbus_message_iter_get_arg_type(&readIterator)
        guard typeCode == DBusTypeCode.INT32 else {
            throw DBusMarshalError.invalidType(expected: DBusTypeCode.INT32, got: typeCode)
        }

        var int32Value: Int32 = 0
        dbus_message_iter_get_basic(&readIterator, &int32Value)
        return int32Value
    }

    public static func firstDouble(_ message: DBusMessageRef) throws -> Double {
        var readIterator = DBusMessageIter()
        guard dbus_message_iter_init(message.raw, &readIterator) != 0 else {
            throw DBusMarshalError.initIterFailed
        }

        let typeCode = dbus_message_iter_get_arg_type(&readIterator)
        guard typeCode == DBusTypeCode.DOUBLE else {
            throw DBusMarshalError.invalidType(expected: DBusTypeCode.DOUBLE, got: typeCode)
        }

        var doubleValue: Double = 0
        dbus_message_iter_get_basic(&readIterator, &doubleValue)
        return doubleValue
    }
}
