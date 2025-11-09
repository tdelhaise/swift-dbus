import Foundation

public enum DBusDecodeError: Error, CustomStringConvertible {
    case missingValue(expected: String)
    case typeMismatch(expected: String, value: DBusBasicValue)

    public var description: String {
        switch self {
        case .missingValue(let expected):
            return "Missing value expected: \(expected)"
        case .typeMismatch(let expected, let value):
            return "Type mismatch: expected \(expected), got \(value)"
        }
    }
}

public enum DBusBasicValue: CustomStringConvertible, Equatable, Sendable {
    case string(String)
    case int32(Int32)
    case uint32(UInt32)
    case bool(Bool)
    case double(Double)
    case stringArray([String])
    case structure([DBusBasicValue])
    /// Rencontré mais non géré (struct/array/variant/other types)
    case unsupported(Int32)

    public var description: String {
        switch self {
        case .string(let value):
            return "string(\(value))"
        case .int32(let value):
            return "int32(\(value))"
        case .uint32(let value):
            return "uint32(\(value))"
        case .bool(let value):
            return "bool(\(value))"
        case .double(let value):
            return "double(\(value))"
        case .stringArray(let values):
            return "stringArray(\(values))"
        case .structure(let values):
            return "structure(\(values))"
        case .unsupported(let typeCode):
            return "unsupported(type:\(typeCode))"
        }
    }

    var dbusTypeCode: Int32? {
        switch self {
        case .string:
            return DBusTypeCode.STRING
        case .int32:
            return DBusTypeCode.INT32
        case .uint32:
            return DBusTypeCode.UINT32
        case .bool:
            return DBusTypeCode.BOOLEAN
        case .double:
            return DBusTypeCode.DOUBLE
        case .stringArray, .structure, .unsupported:
            return nil
        }
    }

    var typeSignatureFragment: String {
        switch self {
        case .string:
            return "s"
        case .int32:
            return "i"
        case .uint32:
            return "u"
        case .bool:
            return "b"
        case .double:
            return "d"
        case .stringArray:
            return "as"
        case .structure(let values):
            let inner = values.map { $0.typeSignatureFragment }.joined()
            return "(\(inner))"
        case .unsupported:
            return ""
        }
    }

    var typeSignature: String? {
        let fragment = typeSignatureFragment
        return fragment.isEmpty ? nil : fragment
    }
}

public protocol DBusReturnDecodable {
    init(from decoder: inout DBusDecoder) throws
}

public protocol DBusPropertyConvertible: DBusBasicEncodable, DBusBasicDecodable {}

public protocol DBusArgumentEncodable {
    func encodeArguments(into encoder: inout DBusArgumentEncoder) throws
}

public struct DBusArgumentEncoder {
    fileprivate(set) var values: [DBusBasicValue] = []

    public mutating func encode(_ value: DBusBasicValue) {
        values.append(value)
    }
}

public protocol DBusBasicEncodable: DBusArgumentEncodable {
    var dbusValue: DBusBasicValue { get }
}

public protocol DBusBasicDecodable: DBusReturnDecodable {
    static func decode(from value: DBusBasicValue) throws -> Self
}

extension String: DBusBasicEncodable, DBusBasicDecodable, DBusPropertyConvertible {
    public var dbusValue: DBusBasicValue { .string(self) }
    public static func decode(from value: DBusBasicValue) throws -> String {
        guard case .string(let string) = value else {
            throw DBusDecodeError.typeMismatch(expected: "string", value: value)
        }
        return string
    }
}

extension Int32: DBusBasicEncodable, DBusBasicDecodable, DBusPropertyConvertible {
    public var dbusValue: DBusBasicValue { .int32(self) }
    public static func decode(from value: DBusBasicValue) throws -> Int32 {
        guard case .int32(let intValue) = value else {
            throw DBusDecodeError.typeMismatch(expected: "int32", value: value)
        }
        return intValue
    }
}

extension UInt32: DBusBasicEncodable, DBusBasicDecodable, DBusPropertyConvertible {
    public var dbusValue: DBusBasicValue { .uint32(self) }
    public static func decode(from value: DBusBasicValue) throws -> UInt32 {
        switch value {
        case .uint32(let value):
            return value
        case .int32(let value) where value >= 0:
            return UInt32(value)
        default:
            throw DBusDecodeError.typeMismatch(expected: "uint32", value: value)
        }
    }
}

extension Bool: DBusBasicEncodable, DBusBasicDecodable, DBusPropertyConvertible {
    public var dbusValue: DBusBasicValue { .bool(self) }
    public static func decode(from value: DBusBasicValue) throws -> Bool {
        guard case .bool(let boolValue) = value else {
            throw DBusDecodeError.typeMismatch(expected: "bool", value: value)
        }
        return boolValue
    }
}

extension Double: DBusBasicEncodable, DBusBasicDecodable, DBusPropertyConvertible {
    public var dbusValue: DBusBasicValue { .double(self) }
    public static func decode(from value: DBusBasicValue) throws -> Double {
        guard case .double(let doubleValue) = value else {
            throw DBusDecodeError.typeMismatch(expected: "double", value: value)
        }
        return doubleValue
    }
}

extension Array: DBusBasicEncodable, DBusBasicDecodable, DBusReturnDecodable,
    DBusPropertyConvertible
where Element == String {
    public var dbusValue: DBusBasicValue { .stringArray(self) }
    public static func decode(from value: DBusBasicValue) throws -> [String] {
        guard case .stringArray(let strings) = value else {
            throw DBusDecodeError.typeMismatch(expected: "string array", value: value)
        }
        return strings
    }
}

extension DBusBasicValue: DBusBasicEncodable, DBusPropertyConvertible {
    public var dbusValue: DBusBasicValue { self }
}

extension DBusBasicValue: DBusBasicDecodable {
    public static func decode(from value: DBusBasicValue) throws -> DBusBasicValue {
        value
    }
}

extension DBusBasicDecodable {
    public init(from decoder: inout DBusDecoder) throws {
        let value = try decoder.nextValue()
        self = try Self.decode(from: value)
    }
}

extension DBusBasicEncodable {
    public func encodeArguments(into encoder: inout DBusArgumentEncoder) throws {
        encoder.encode(dbusValue)
    }
}

extension Array: DBusArgumentEncodable where Element: DBusBasicEncodable {
    public func encodeArguments(into encoder: inout DBusArgumentEncoder) throws {
        for element in self {
            try element.encodeArguments(into: &encoder)
        }
    }
}

public struct DBusArgumentList: DBusArgumentEncodable, ExpressibleByArrayLiteral {
    public var values: [DBusBasicValue]

    public init(values: [DBusBasicValue]) {
        self.values = values
    }

    public init(arrayLiteral elements: DBusBasicValue...) {
        self.values = elements
    }

    public func encodeArguments(into encoder: inout DBusArgumentEncoder) throws {
        for value in values {
            encoder.encode(value)
        }
    }

    public static var empty: DBusArgumentList { DBusArgumentList(values: []) }
}

public func DBusArguments(_ values: DBusBasicEncodable...) -> DBusArgumentList {
    DBusArgumentList(values: values.map { $0.dbusValue })
}

public struct DBusDecoder {
    private var values: ArraySlice<DBusBasicValue>

    public init(values: [DBusBasicValue]) {
        self.values = ArraySlice(values)
    }

    public var isAtEnd: Bool { values.isEmpty }

    public mutating func nextValue() throws -> DBusBasicValue {
        guard let value = values.popFirst() else {
            throw DBusDecodeError.missingValue(expected: "next value")
        }
        return value
    }

    public mutating func next<T: DBusBasicDecodable>(_ type: T.Type = T.self) throws -> T {
        let value = try nextValue()
        return try type.decode(from: value)
    }

    public mutating func decode<T: DBusReturnDecodable>(_ type: T.Type = T.self) throws -> T {
        try type.init(from: &self)
    }
}

public struct DBusTuple2<First, Second>: DBusReturnDecodable, CustomStringConvertible, Sendable
where First: DBusReturnDecodable & Sendable, Second: DBusReturnDecodable & Sendable {
    public let first: First
    public let second: Second

    public init(from decoder: inout DBusDecoder) throws {
        self.first = try decoder.decode(First.self)
        self.second = try decoder.decode(Second.self)
    }

    public var value: (First, Second) { (first, second) }

    public var description: String {
        "(\(first), \(second))"
    }
}

public struct DBusTuple3<First, Second, Third>: DBusReturnDecodable, CustomStringConvertible,
    Sendable
where
    First: DBusReturnDecodable & Sendable,
    Second: DBusReturnDecodable & Sendable,
    Third: DBusReturnDecodable & Sendable {
    public let first: First
    public let second: Second
    public let third: Third

    public init(from decoder: inout DBusDecoder) throws {
        self.first = try decoder.decode(First.self)
        self.second = try decoder.decode(Second.self)
        self.third = try decoder.decode(Third.self)
    }

    public var value: (First, Second, Third) { (first, second, third) }

    public var description: String {
        "(\(first), \(second), \(third))"
    }
}
