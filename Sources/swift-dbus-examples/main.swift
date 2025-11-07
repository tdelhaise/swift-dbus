import Foundation
import SwiftDBus

@main
struct ExampleApp {
    static func main() async {
        do {
            let connection = try DBusConnection(bus: .session)

            // Abonnement à NameOwnerChanged
            let rule = DBusMatchRule.signal(
                interface: "org.freedesktop.DBus",
                member: "NameOwnerChanged"
            )
            let stream = try connection.signals(matching: rule)

            // Déclenche un signal en demandant un nom temporaire
            let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            let tempName = "org.swiftdbus.example.x\(suffix.prefix(8))"
            _ = try connection.requestName(tempName)

            // Consomme quelques événements (pendant ~2 secondes)
            let start = DispatchTime.now().uptimeNanoseconds
            let maxDurationNs: UInt64 = 2_000_000_000
            var iterator = stream.makeAsyncIterator()
            while DispatchTime.now().uptimeNanoseconds - start < maxDurationNs {
                if let signal = await iterator.next() {
                    print("Signal: \(signal)")
                } else {
                    break
                }
            }

            _ = try connection.releaseName(tempName)
            try? await Task.sleep(nanoseconds: 100_000_000)  // petite marge

            print("Example done.")

        } catch {
            print("Example failed: \(error)")
        }
    }
}
