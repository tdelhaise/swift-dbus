// Sources/SwiftDBus/Internal/Errors.swift
import CDbus

/// Erreur Swift "Swifty" construite à partir d'un DBusError C.
public struct DBusErrorSwift: Swift.Error, CustomStringConvertible, Equatable {
    public let name: String
    public let message: String

    public var description: String { "[\(name)] \(message)" }
}

extension DBusErrorSwift {
    /// Construit à partir d'un DBusError C initialisé et potentiellement "set".
    static func fromC(_ err: CDbus.DBusError) -> DBusErrorSwift {
        let name = err.name.map { String(cString: $0) } ?? "org.freedesktop.DBus.Error.Failed"
        let msg = err.message.map { String(cString: $0) } ?? "Unknown DBus error"
        return DBusErrorSwift(name: name, message: msg)
    }
}

/// Helper générique : fournit un DBusError initialisé au corps.
/// Si le corps "set" l'erreur, on jette `DBusErrorSwift`.
@inline(__always)
internal func withDBusError<R>(_ body: (UnsafeMutablePointer<CDbus.DBusError>) -> R) throws -> R {
    var err = CDbus.DBusError()
    dbus_error_init(&err)
    defer { dbus_error_free(&err) }

    let result = body(&err)
    if dbus_error_is_set(&err) != 0 {
        throw DBusErrorSwift.fromC(err)
    }
    return result
}

