import CDbus

public enum DBusMarshalError: Swift.Error, CustomStringConvertible {
    case appendFailed(String)
    case initIterFailed
    case invalidType(expected: Int32, got: Int32)
    case null
    case openContainerFailed(String)
    case closeContainerFailed(String)

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
        case .openContainerFailed(let what):
            return "openContainerFailed(\(what))"
        case .closeContainerFailed(let what):
            return "closeContainerFailed(\(what))"
        }
    }
}

// MARK: - Writer racine pour empiler plusieurs arguments
public struct DBusAppendWriter {
    private var appendIterator: DBusMessageIter

    public init(message: DBusMessageRef) {
        var iterator = DBusMessageIter()
        dbus_message_iter_init_append(message.raw, &iterator)
        self.appendIterator = iterator
    }

    // MARK: - Append de types de base

    public mutating func appendString(_ value: String) throws {
        try value.withCString { cStringPointer in
            var pointerToCString: UnsafePointer<CChar>? = cStringPointer
            let ok = dbus_message_iter_append_basic(
                &appendIterator, DBusTypeCode.STRING, &pointerToCString
            )
            if ok == 0 { throw DBusMarshalError.appendFailed("string") }
        }
    }

    public mutating func appendBool(_ value: Bool) throws {
        var dbusBool: dbus_bool_t = value ? 1 : 0
        let ok = dbus_message_iter_append_basic(&appendIterator, DBusTypeCode.BOOLEAN, &dbusBool)
        if ok == 0 { throw DBusMarshalError.appendFailed("bool") }
    }

    public mutating func appendInt32(_ value: Int32) throws {
        var mutable = value
        let ok = dbus_message_iter_append_basic(&appendIterator, DBusTypeCode.INT32, &mutable)
        if ok == 0 { throw DBusMarshalError.appendFailed("int32") }
    }

    public mutating func appendDouble(_ value: Double) throws {
        var mutable = value
        let ok = dbus_message_iter_append_basic(&appendIterator, DBusTypeCode.DOUBLE, &mutable)
        if ok == 0 { throw DBusMarshalError.appendFailed("double") }
    }

    // MARK: - Conteneurs

    /// Ouvre un conteneur d’array pour éléments **basiques** (ex: "s", "i", "b", "d").
    public mutating func withArray(
        elementSignature: DBusBasicElementSignature,
        _ body: (inout DBusArrayAppender) throws -> Void
    ) throws {
        var subIterator = DBusMessageIter()
        try elementSignature.rawValue.withCString { elementSigPtr in
            let ok = dbus_message_iter_open_container(
                &appendIterator,
                DBusTypeCode.ARRAY,
                elementSigPtr,
                &subIterator
            )
            if ok == 0 {
                throw DBusMarshalError.openContainerFailed("array(\(elementSignature.rawValue))")
            }
        }

        var appender = DBusArrayAppender(iterator: subIterator, elementSignature: elementSignature)
        try body(&appender)

        let closeOk = dbus_message_iter_close_container(&appendIterator, &subIterator)
        if closeOk == 0 { throw DBusMarshalError.closeContainerFailed("array") }
    }

    /// Ouvre un conteneur d’array de **dictionnaires {ss}** (signature `a{ss}`).
    public mutating func withDictionaryStringString(
        _ body: (inout DBusDictStringStringAppender) throws -> Void
    ) throws {
        var subIterator = DBusMessageIter()
        let elementSignature = "{ss}"  // dict-entry (string -> string)

        let openOk = elementSignature.withCString { elementSigPtr in
            dbus_message_iter_open_container(
                &appendIterator, DBusTypeCode.ARRAY, elementSigPtr, &subIterator
            )
        }
        if openOk == 0 { throw DBusMarshalError.openContainerFailed("a{ss}") }

        var appender = DBusDictStringStringAppender(iterator: subIterator)
        try body(&appender)

        let closeOk = dbus_message_iter_close_container(&appendIterator, &subIterator)
        if closeOk == 0 { throw DBusMarshalError.closeContainerFailed("a{ss}") }
    }
}

// MARK: - Appender pour Array de basiques

public struct DBusArrayAppender {
    fileprivate var iterator: DBusMessageIter
    public let elementSignature: DBusBasicElementSignature

    public mutating func appendString(_ value: String) throws {
        guard elementSignature == .string else {
            throw DBusMarshalError.appendFailed("array element is not 's'")
        }
        try value.withCString { cStringPointer in
            var pointerToCString: UnsafePointer<CChar>? = cStringPointer
            let ok = dbus_message_iter_append_basic(&iterator, DBusTypeCode.STRING, &pointerToCString)
            if ok == 0 { throw DBusMarshalError.appendFailed("array<string>") }
        }
    }

    public mutating func appendInt32(_ value: Int32) throws {
        guard elementSignature == .int32 else {
            throw DBusMarshalError.appendFailed("array element is not 'i'")
        }
        var mutable = value
        let ok = dbus_message_iter_append_basic(&iterator, DBusTypeCode.INT32, &mutable)
        if ok == 0 { throw DBusMarshalError.appendFailed("array<int32>") }
    }

    public mutating func appendBool(_ value: Bool) throws {
        guard elementSignature == .boolean else {
            throw DBusMarshalError.appendFailed("array element is not 'b'")
        }
        var dbusBool: dbus_bool_t = value ? 1 : 0
        let ok = dbus_message_iter_append_basic(&iterator, DBusTypeCode.BOOLEAN, &dbusBool)
        if ok == 0 { throw DBusMarshalError.appendFailed("array<bool>") }
    }

    public mutating func appendDouble(_ value: Double) throws {
        guard elementSignature == .double else {
            throw DBusMarshalError.appendFailed("array element is not 'd'")
        }
        var mutable = value
        let ok = dbus_message_iter_append_basic(&iterator, DBusTypeCode.DOUBLE, &mutable)
        if ok == 0 { throw DBusMarshalError.appendFailed("array<double>") }
    }
}

// MARK: - Appender pour a{ss}

public struct DBusDictStringStringAppender {
    fileprivate var iterator: DBusMessageIter

    public mutating func appendEntry(key: String, value: String) throws {
        var entryIterator = DBusMessageIter()
        let openOk = dbus_message_iter_open_container(
            &iterator, DBusTypeCode.DICT_ENTRY, nil, &entryIterator
        )
        if openOk == 0 { throw DBusMarshalError.openContainerFailed("dict-entry {ss}") }

        // key (s)
        try key.withCString { cStringPointer in
            var pointerToCString: UnsafePointer<CChar>? = cStringPointer
            let ok = dbus_message_iter_append_basic(
                &entryIterator, DBusTypeCode.STRING, &pointerToCString
            )
            if ok == 0 { throw DBusMarshalError.appendFailed("dict key string") }
        }

        // value (s)
        try value.withCString { cStringPointer in
            var pointerToCString: UnsafePointer<CChar>? = cStringPointer
            let ok = dbus_message_iter_append_basic(
                &entryIterator, DBusTypeCode.STRING, &pointerToCString
            )
            if ok == 0 { throw DBusMarshalError.appendFailed("dict value string") }
        }

        let closeOk = dbus_message_iter_close_container(&iterator, &entryIterator)
        if closeOk == 0 { throw DBusMarshalError.closeContainerFailed("dict-entry {ss}") }
    }
}

// MARK: - Enum utilitaire pour signatures d’éléments basiques

public enum DBusBasicElementSignature: String, Equatable {
    case string = "s"
    case int32 = "i"
    case boolean = "b"
    case double = "d"
}

// MARK: - Decodeurs (premier argument)

public enum DBusMarshal {
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
        guard let nonNull = cStringPointer else { throw DBusMarshalError.null }
        return String(cString: nonNull)
    }

    /// Décoder un tableau de `String` en premier argument (`as`).
    public static func firstArrayOfStrings(_ message: DBusMessageRef) throws -> [String] {
        var readIterator = DBusMessageIter()
        guard dbus_message_iter_init(message.raw, &readIterator) != 0 else {
            throw DBusMarshalError.initIterFailed
        }

        // 1) Premier arg: ARRAY
        let topType = dbus_message_iter_get_arg_type(&readIterator)
        guard topType == DBusTypeCode.ARRAY else {
            throw DBusMarshalError.invalidType(expected: DBusTypeCode.ARRAY, got: topType)
        }

        // 2) Entrer dans l’array et vérifier que l’élément est un STRING
        var arrayIterator = DBusMessageIter()
        dbus_message_iter_recurse(&readIterator, &arrayIterator)

        var result: [String] = []
        while true {
            let elementType = dbus_message_iter_get_arg_type(&arrayIterator)
            if elementType == 0 { break }  // DBUS_TYPE_INVALID == 0

            guard elementType == DBusTypeCode.STRING else {
                throw DBusMarshalError.invalidType(expected: DBusTypeCode.STRING, got: elementType)
            }
            var cStringPointer: UnsafePointer<CChar>?
            dbus_message_iter_get_basic(&arrayIterator, &cStringPointer)
            guard let nonNull = cStringPointer else { throw DBusMarshalError.null }
            result.append(String(cString: nonNull))

            dbus_message_iter_next(&arrayIterator)
        }
        return result
    }
}
