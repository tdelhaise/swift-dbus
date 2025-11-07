// Sources/swift-dbus-examples/main.swift
import Foundation
import SwiftDBus

let (major, minor, micro) = DBus.version()
print("libdbus version: \(major).\(minor).\(micro)")

do {
    let conn = try DBusConnection(bus: .session)
    print("Unique name: \(try conn.uniqueName())")

    let stream = try conn.messages()
    Task.detached {
        for await msg in stream {
            // Placeholder: on imprimera le type/headers à M2
            print("Received message ptr: \(msg.raw)")
        }
    }

    // Laisser tourner un court instant pour voir des events (si signal DBus arrive)
    Thread.sleep(forTimeInterval: 1)
    conn.stopPump()
} catch {
    print("DBus error: \(error)")
}
