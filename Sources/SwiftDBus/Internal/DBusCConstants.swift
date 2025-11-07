// swiftlint:disable identifier_name
// Sources/SwiftDBus/Internal/DBusCConstants.swift
//
// Swift mirrors of selected libdbus C macros (dbus-protocol.h).
// Many DBus C macros aren't imported into Swift directly, so we re-declare
// the essentials here in a Swift-friendly way.

// MARK: - Helpers

@inline(__always)
private func ascii(_ ch: Character) -> Int32 {
    Int32(ch.asciiValue!)
}

// MARK: - DBus basic type codes (as Int32), equivalent to DBUS_TYPE_* ((int) 'x')

public enum DBusTypeCode {
    // Basic types
    public static let BYTE: Int32 = ascii("y")  // UInt8
    public static let BOOLEAN: Int32 = ascii("b")  // Bool
    public static let INT16: Int32 = ascii("n")
    public static let UINT16: Int32 = ascii("q")
    public static let INT32: Int32 = ascii("i")
    public static let UINT32: Int32 = ascii("u")
    public static let INT64: Int32 = ascii("x")
    public static let UINT64: Int32 = ascii("t")
    public static let DOUBLE: Int32 = ascii("d")
    public static let STRING: Int32 = ascii("s")
    public static let OBJECT_PATH: Int32 = ascii("o")
    public static let SIGNATURE: Int32 = ascii("g")
    public static let VARIANT: Int32 = ascii("v")
    public static let ARRAY: Int32 = ascii("a")
    public static let UNIX_FD: Int32 = ascii("h")
    public static let DICT_ENTRY: Int32 = ascii("e")
    public static let STRUCT: Int32 = ascii("r")

    // Container delimiters (used by the low-level iter API)
    public static let STRUCT_BEGIN: Int32 = ascii("(")
    public static let STRUCT_END: Int32 = ascii(")")
    public static let DICT_ENTRY_BEGIN: Int32 = ascii("{")
    public static let DICT_ENTRY_END: Int32 = ascii("}")
}

// MARK: - Signature fragments (as String), equivalent to *_AS_STRING macros

public enum DBusSig {
    public static let BYTE = "y"
    public static let BOOLEAN = "b"
    public static let INT16 = "n"
    public static let UINT16 = "q"
    public static let INT32 = "i"
    public static let UINT32 = "u"
    public static let INT64 = "x"
    public static let UINT64 = "t"
    public static let DOUBLE = "d"
    public static let STRING = "s"
    public static let OBJECT_PATH = "o"
    public static let SIGNATURE = "g"
    public static let VARIANT = "v"
    public static let ARRAY = "a"
    public static let UNIX_FD = "h"

    public static let STRUCT_BEGIN = "("
    public static let STRUCT_END = ")"
    public static let DICT_ENTRY_BEGIN = "{"
    public static let DICT_ENTRY_END = "}"
}

// MARK: - Message type codes (dbus_message_get_type returns Int32)

public enum DBusMsgType {
    public static let METHOD_CALL: Int32 = 1
    public static let METHOD_RETURN: Int32 = 2
    public static let ERROR: Int32 = 3
    public static let SIGNAL: Int32 = 4
}

// MARK: - Utilities

@inline(__always)
public func dbusIsBasicType(_ typeCode: Int32) -> Bool {
    switch typeCode {
    case DBusTypeCode.BYTE,
        DBusTypeCode.BOOLEAN,
        DBusTypeCode.INT16,
        DBusTypeCode.UINT16,
        DBusTypeCode.INT32,
        DBusTypeCode.UINT32,
        DBusTypeCode.INT64,
        DBusTypeCode.UINT64,
        DBusTypeCode.DOUBLE,
        DBusTypeCode.STRING,
        DBusTypeCode.OBJECT_PATH,
        DBusTypeCode.SIGNATURE,
        DBusTypeCode.UNIX_FD:
        return true
    default:
        return false
    }
}

@inline(__always)
public func dbusTypeDebugString(_ typeCode: Int32) -> String {
    switch typeCode {
    case DBusTypeCode.BYTE:
        return "BYTE(y)"
    case DBusTypeCode.BOOLEAN:
        return "BOOLEAN(b)"
    case DBusTypeCode.INT16:
        return "INT16(n)"
    case DBusTypeCode.UINT16:
        return "UINT16(q)"
    case DBusTypeCode.INT32:
        return "INT32(i)"
    case DBusTypeCode.UINT32:
        return "UINT32(u)"
    case DBusTypeCode.INT64:
        return "INT64(x)"
    case DBusTypeCode.UINT64:
        return "UINT64(t)"
    case DBusTypeCode.DOUBLE:
        return "DOUBLE(d)"
    case DBusTypeCode.STRING:
        return "STRING(s)"
    case DBusTypeCode.OBJECT_PATH:
        return "OBJECT_PATH(o)"
    case DBusTypeCode.SIGNATURE:
        return "SIGNATURE(g)"
    case DBusTypeCode.VARIANT:
        return "VARIANT(v)"
    case DBusTypeCode.ARRAY:
        return "ARRAY(a)"
    case DBusTypeCode.UNIX_FD:
        return "UNIX_FD(h)"
    case DBusTypeCode.STRUCT_BEGIN:
        return "STRUCT_BEGIN(()"
    case DBusTypeCode.STRUCT_END:
        return "STRUCT_END())"
    case DBusTypeCode.DICT_ENTRY_BEGIN:
        return "DICT_ENTRY_BEGIN({"
    case DBusTypeCode.DICT_ENTRY_END:
        return "DICT_ENTRY_END(})"
    default:
        return "UNKNOWN(\(typeCode))"
    }
}
// swiftlint:enable identifier_name
