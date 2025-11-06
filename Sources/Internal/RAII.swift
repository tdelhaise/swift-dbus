// Sources/SwiftDBus/Internal/RAII.swift
import CDbus

/// RAII pour DBusMessage*
public final class DBusMessageRef {
    public let raw: OpaquePointer

    /// Prend "possession" d'un pointeur DBusMessage* (référence déjà détenue par l'appelant).
    public init(taking raw: OpaquePointer) {
        self.raw = raw
    }

    /// Crée un DBusMessageRef à partir d'un appel C qui peut retourner nil.
    /// Jette si nil, avec un message explicite.
    public static func wrapOrThrow(_ make: () -> OpaquePointer?, _ context: @autoclosure () -> String) throws -> DBusMessageRef {
        guard let msg = make() else {
            throw DBusErrorSwift(name: "org.freedesktop.DBus.Error.Failed",
                                 message: "Failed to create DBusMessage: \(context())")
        }
        return DBusMessageRef(taking: msg)
    }

    deinit {
        dbus_message_unref(raw)
    }
}

public final class DBusPendingCallRef {
    public let raw: OpaquePointer

    public init(taking raw: OpaquePointer) {
        self.raw = raw
    }

    deinit {
        dbus_pending_call_unref(raw)
    }
}

