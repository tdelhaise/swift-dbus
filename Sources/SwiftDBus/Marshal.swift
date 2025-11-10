// swiftlint:disable file_length
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

    public static func decodeAllBasicArgs(_ message: DBusMessageRef) -> [DBusBasicValue] {
        var iterator = DBusMessageIter()
        guard dbus_message_iter_init(message.raw, &iterator) != 0 else { return [] }

        var results: [DBusBasicValue] = []
        while true {
            let typeCode = dbus_message_iter_get_arg_type(&iterator)
            if typeCode == 0 { break }  // DBUS_TYPE_INVALID
            var copy = iterator
            results.append(decodeSingleBasic(&copy))
            _ = dbus_message_iter_next(&iterator)
        }
        return results
    }

    public static func signature(of values: [DBusBasicValue]) -> String {
        values.map { $0.typeSignatureFragment }.joined()
    }

    public static func appendValue(
        _ value: DBusBasicValue,
        into iterator: inout DBusMessageIter
    ) throws {
        switch value {
        case .structure(let fields):
            var structIterator = DBusMessageIter()
            let opened = dbus_message_iter_open_container(
                &iterator,
                DBusTypeCode.STRUCT,
                nil,
                &structIterator
            )
            if opened == 0 {
                throw DBusMarshalError.openContainerFailed("struct")
            }
            for field in fields {
                try appendValue(field, into: &structIterator)
            }
            let closed = dbus_message_iter_close_container(&iterator, &structIterator)
            if closed == 0 {
                throw DBusMarshalError.closeContainerFailed("struct")
            }
        case .stringArray(let strings):
            var arrayIterator = DBusMessageIter()
            let opened = "s".withCString { elementSig in
                dbus_message_iter_open_container(
                    &iterator,
                    DBusTypeCode.ARRAY,
                    elementSig,
                    &arrayIterator
                )
            }
            if opened == 0 {
                throw DBusMarshalError.openContainerFailed("array<string>")
            }
            for string in strings {
                try appendBasic(.string(string), into: &arrayIterator)
            }
            let closed = dbus_message_iter_close_container(&iterator, &arrayIterator)
            if closed == 0 {
                throw DBusMarshalError.closeContainerFailed("array<string>")
            }
        case .dictStringVariant(let dictionary):
            try appendDictStringVariantBasics(dictionary, into: &iterator)
        case .unsupported(let type):
            throw DBusMarshalError.appendFailed("unsupported value type \(type)")
        default:
            try appendBasic(value, into: &iterator)
        }
    }

    public static func appendDictStringVariantBasics(
        _ dictionary: [String: DBusBasicValue],
        into iterator: inout DBusMessageIter
    ) throws {
        var dictIterator = DBusMessageIter()
        let opened = "{sv}".withCString { elementSignature in
            dbus_message_iter_open_container(
                &iterator,
                DBusTypeCode.ARRAY,
                elementSignature,
                &dictIterator
            )
        }
        if opened == 0 {
            throw DBusMarshalError.openContainerFailed("a{sv}")
        }

        for (key, value) in dictionary {
            var entryIterator = DBusMessageIter()
            let entryOpened = dbus_message_iter_open_container(
                &dictIterator,
                DBusTypeCode.DICT_ENTRY,
                nil,
                &entryIterator
            )
            if entryOpened == 0 {
                throw DBusMarshalError.openContainerFailed("dict-entry {sv}")
            }

            try appendBasic(.string(key), into: &entryIterator)
            try appendVariant(of: value, into: &entryIterator)

            let entryClosed = dbus_message_iter_close_container(&dictIterator, &entryIterator)
            if entryClosed == 0 {
                throw DBusMarshalError.closeContainerFailed("dict-entry {sv}")
            }
        }

        let closed = dbus_message_iter_close_container(&iterator, &dictIterator)
        if closed == 0 {
            throw DBusMarshalError.closeContainerFailed("a{sv}")
        }
    }

    public static func appendBasic(
        _ value: DBusBasicValue,
        into iterator: inout DBusMessageIter
    ) throws {
        switch value {
        case .string(let string):
            try string.withCString { cString in
                var pointer: UnsafePointer<CChar>? = cString
                let ok = dbus_message_iter_append_basic(
                    &iterator,
                    DBusTypeCode.STRING,
                    &pointer
                )
                if ok == 0 { throw DBusMarshalError.appendFailed("string") }
            }
        case .int32(var intValue):
            let ok = dbus_message_iter_append_basic(&iterator, DBusTypeCode.INT32, &intValue)
            if ok == 0 { throw DBusMarshalError.appendFailed("int32") }
        case .uint32(var uintValue):
            let ok = dbus_message_iter_append_basic(&iterator, DBusTypeCode.UINT32, &uintValue)
            if ok == 0 { throw DBusMarshalError.appendFailed("uint32") }
        case .bool(let boolValue):
            var dbusBool: dbus_bool_t = boolValue ? 1 : 0
            let ok = dbus_message_iter_append_basic(&iterator, DBusTypeCode.BOOLEAN, &dbusBool)
            if ok == 0 { throw DBusMarshalError.appendFailed("bool") }
        case .double(var doubleValue):
            let ok = dbus_message_iter_append_basic(&iterator, DBusTypeCode.DOUBLE, &doubleValue)
            if ok == 0 { throw DBusMarshalError.appendFailed("double") }
        case .stringArray, .structure, .unsupported, .dictStringVariant:
            throw DBusMarshalError.appendFailed("unsupported basic value")
        }
    }

    public static func appendVariant(
        of value: DBusBasicValue,
        into iterator: inout DBusMessageIter
    ) throws {
        guard let signature = value.typeSignature else {
            throw DBusMarshalError.appendFailed("variant signature unsupported")
        }

        var variantIter = DBusMessageIter()
        let opened = signature.withCString { cSignature in
            dbus_message_iter_open_container(
                &iterator,
                DBusTypeCode.VARIANT,
                cSignature,
                &variantIter
            )
        }
        if opened == 0 {
            throw DBusMarshalError.openContainerFailed("variant")
        }

        try appendValue(value, into: &variantIter)

        let closed = dbus_message_iter_close_container(&iterator, &variantIter)
        if closed == 0 {
            throw DBusMarshalError.closeContainerFailed("variant")
        }
    }

    public static func firstVariantBasic(_ message: DBusMessageRef) throws -> DBusBasicValue {
        var iterator = DBusMessageIter()
        guard dbus_message_iter_init(message.raw, &iterator) != 0 else {
            throw DBusMarshalError.initIterFailed
        }
        return try decodeVariantBasic(&iterator)
    }

    public static func firstDictStringVariantBasics(_ message: DBusMessageRef) throws -> [String: DBusBasicValue] {
        var iterator = DBusMessageIter()
        guard dbus_message_iter_init(message.raw, &iterator) != 0 else {
            throw DBusMarshalError.initIterFailed
        }
        let dictionary = try decodeDictStringVariant(&iterator)
        return dictionary
    }

    public static func decodeVariantBasicValue(_ iterator: inout DBusMessageIter) throws -> DBusBasicValue {
        try decodeVariantBasic(&iterator)
    }

    private static func decodeVariantBasic(_ iterator: inout DBusMessageIter) throws -> DBusBasicValue {
        let type = dbus_message_iter_get_arg_type(&iterator)
        guard type == DBusTypeCode.VARIANT else {
            throw DBusMarshalError.invalidType(expected: DBusTypeCode.VARIANT, got: type)
        }
        var variantIter = DBusMessageIter()
        dbus_message_iter_recurse(&iterator, &variantIter)
        return decodeSingleBasic(&variantIter)
    }

    private static func decodeSingleBasic(_ iterator: inout DBusMessageIter) -> DBusBasicValue {
        let typeCode = dbus_message_iter_get_arg_type(&iterator)

        switch typeCode {
        case DBusTypeCode.STRING:
            var pointer: UnsafePointer<CChar>?
            dbus_message_iter_get_basic(&iterator, &pointer)
            return .string(pointer.map { String(cString: $0) } ?? "")
        case DBusTypeCode.INT32:
            var intValue: Int32 = 0
            dbus_message_iter_get_basic(&iterator, &intValue)
            return .int32(intValue)
        case DBusTypeCode.UINT32:
            var uintValue: UInt32 = 0
            dbus_message_iter_get_basic(&iterator, &uintValue)
            return .uint32(uintValue)
        case DBusTypeCode.BOOLEAN:
            var boolRaw: dbus_bool_t = 0
            dbus_message_iter_get_basic(&iterator, &boolRaw)
            return .bool(boolRaw != 0)
        case DBusTypeCode.DOUBLE:
            var doubleValue: Double = 0
            dbus_message_iter_get_basic(&iterator, &doubleValue)
            return .double(doubleValue)
        case DBusTypeCode.ARRAY:
            let elementType = dbus_message_iter_get_element_type(&iterator)
            if elementType == DBusTypeCode.STRING {
                return decodeStringArray(&iterator)
            } else if elementType == DBusTypeCode.DICT_ENTRY {
                if let dict = try? decodeDictStringVariant(&iterator) {
                    return .dictStringVariant(dict)
                } else {
                    return .unsupported(DBusTypeCode.ARRAY)
                }
            } else if elementType == 0 {
                if isArraySignature(&iterator, equalTo: "as") {
                    return decodeStringArray(&iterator)
                } else if isDictArraySignature(&iterator) {
                    if let dict = try? decodeDictStringVariant(&iterator) {
                        return .dictStringVariant(dict)
                    } else {
                        return .unsupported(DBusTypeCode.ARRAY)
                    }
                } else {
                    return .unsupported(DBusTypeCode.ARRAY)
                }
            } else {
                return .unsupported(DBusTypeCode.ARRAY)
            }
        default:
            return .unsupported(typeCode)
        }
    }

    private static func decodeStringArray(_ iterator: inout DBusMessageIter) -> DBusBasicValue {
        var arrayIter = DBusMessageIter()
        dbus_message_iter_recurse(&iterator, &arrayIter)

        var strings: [String] = []
        while true {
            let elementType = dbus_message_iter_get_arg_type(&arrayIter)
            if elementType == 0 { break }
            guard elementType == DBusTypeCode.STRING else {
                return .unsupported(DBusTypeCode.ARRAY)
            }
            var pointer: UnsafePointer<CChar>?
            dbus_message_iter_get_basic(&arrayIter, &pointer)
            strings.append(pointer.map { String(cString: $0) } ?? "")
            _ = dbus_message_iter_next(&arrayIter)
        }
        return .stringArray(strings)
    }

    private static func decodeDictStringVariant(_ iterator: inout DBusMessageIter) throws -> [String: DBusBasicValue] {
        guard dbus_message_iter_get_arg_type(&iterator) == DBusTypeCode.ARRAY else {
            throw DBusMarshalError.invalidType(
                expected: DBusTypeCode.ARRAY,
                got: dbus_message_iter_get_arg_type(&iterator)
            )
        }
        var dictIter = DBusMessageIter()
        dbus_message_iter_recurse(&iterator, &dictIter)

        var result: [String: DBusBasicValue] = [:]
        while true {
            let entryType = dbus_message_iter_get_arg_type(&dictIter)
            if entryType == 0 { break }
            guard entryType == DBusTypeCode.DICT_ENTRY else {
                throw DBusMarshalError.invalidType(expected: DBusTypeCode.DICT_ENTRY, got: entryType)
            }
            var entryIter = DBusMessageIter()
            dbus_message_iter_recurse(&dictIter, &entryIter)
            guard dbus_message_iter_get_arg_type(&entryIter) == DBusTypeCode.STRING else {
                throw DBusMarshalError.invalidType(
                    expected: DBusTypeCode.STRING,
                    got: dbus_message_iter_get_arg_type(&entryIter)
                )
            }
            var keyPointer: UnsafePointer<CChar>?
            dbus_message_iter_get_basic(&entryIter, &keyPointer)
            let key = keyPointer.map { String(cString: $0) } ?? ""

            guard dbus_message_iter_next(&entryIter) != 0 else {
                result[key] = .unsupported(DBusTypeCode.VARIANT)
                _ = dbus_message_iter_next(&dictIter)
                continue
            }

            var variantIter = entryIter
            let value = try decodeVariantBasic(&variantIter)
            result[key] = value

            _ = dbus_message_iter_next(&dictIter)
        }

        return result
    }

    private static func isArraySignature(
        _ iterator: inout DBusMessageIter,
        equalTo signature: String
    ) -> Bool {
        guard let sig = arraySignature(&iterator) else { return false }
        return sig == signature
    }

    private static func isDictArraySignature(_ iterator: inout DBusMessageIter) -> Bool {
        guard let sig = arraySignature(&iterator) else { return false }
        return sig.hasPrefix("a{")
    }

    private static func arraySignature(_ iterator: inout DBusMessageIter) -> String? {
        var copy = iterator
        guard let cSignature = dbus_message_iter_get_signature(&copy) else { return nil }
        defer { dbus_free(cSignature) }
        return String(cString: cSignature)
    }
}
