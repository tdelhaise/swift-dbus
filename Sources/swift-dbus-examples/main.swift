import SwiftDBus

let (major, minor, micro) = DBus.version()
print("libdbus version: \(major).\(minor).\(micro)")
print("DBus available: \(DBus.isAvailable())")

do {
    let conn = try DBusConnection(sessionBus: true)
    print("Connected to session bus. Unique name: \(try conn.uniqueName())")
} catch {
    print("DBus error: \(error)")
}
