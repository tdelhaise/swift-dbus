import Foundation
import SwiftDBus

// L’exécutable est construit avec un entry-point custom (voir flags SPM).
struct ExampleApp {
    static func main() {
        do {
            let connection = try DBusConnection(bus: .session)

            let unique = try connection.uniqueName()
            print("Unique name: \(unique)")

            let busId = try connection.getBusId()
            print("Bus ID: \(busId)")

            let names = try connection.listNames()
            let firstFive = names.prefix(5).joined(separator: ", ")
            print("Names on the bus (first 5): \(firstFive)")

            try connection.pingPeer()
            print("Peer Ping OK")

        } catch {
            print("Example failed: \(error)")
        }
    }
}
