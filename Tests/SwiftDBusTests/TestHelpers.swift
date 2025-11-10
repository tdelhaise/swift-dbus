import Foundation

@testable import SwiftDBus

func makeTemporaryBusName(
    prefix: String = "org.swiftdbus.test",
    suffixLength: Int = 8
) -> String {
    let random = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    return "\(prefix).x\(random.prefix(suffixLength))"
}

func makeBusProxy(
    _ connection: DBusConnection,
    caches: DBusProxyCaches = DBusProxyCaches()
) -> DBusProxy {
    DBusProxy(
        connection: connection,
        destination: "org.freedesktop.DBus",
        path: "/org/freedesktop/DBus",
        interface: "org.freedesktop.DBus",
        caches: caches
    )
}
