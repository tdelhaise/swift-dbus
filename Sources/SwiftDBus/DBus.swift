//
//  DBus.swift
//  SwiftDBus
//
//  Minimal placeholder showing libdbus-1 is linkable and callable from Swift.
//  This will evolve into a safe Swift-y wrapper over DBus.
//
//  NOTE: Built for Linux. Requires libdbus-1-dev on build machines.
//
import CDbus

public enum DBus {
    /// Returns the runtime libdbus version (major, minor, micro).
    public static func version() -> (Int32, Int32, Int32) {
        var major: Int32 = 0
        var minor: Int32 = 0
        var micro: Int32 = 0
        dbus_get_version(&major, &minor, &micro)
        return (major, minor, micro)
    }

    /// Quick self-check that libdbus is usable.
    /// In a full implementation, this would expose connections, messages, and bus operations.
    public static func isAvailable() -> Bool {
        let (ma, mi, mc) = version()
        return (ma >= 1) && (mi >= 0) && (mc >= 0)
    }

    /// Renvoie un identifiant machine si possible (APIs Peer/Bus) — placeholder M0.
    public static func machineIdIfAvailable() -> String? {
        // M0: on évite d'ouvrir une vraie connexion ici.
        // On garde ça pour M1. Cette méthode restera un placeholder.
        nil
    }
}
