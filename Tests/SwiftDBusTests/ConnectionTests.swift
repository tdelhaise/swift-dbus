import XCTest

@testable import SwiftDBus

final class ConnectionTests: XCTestCase {

    func testOpenSessionAndUniqueName() throws {
        let conn = try DBusConnection(bus: .session)
        let name = try conn.uniqueName()
        // libdbus assigne un nom unique commençant par ":" après Hello
        XCTAssertTrue(name.hasPrefix(":"), "Unique name should start with ':', got \(name)")
    }

    func testMessagesStreamStartsAndStops() async throws {
        let conn = try DBusConnection(bus: .session)
        let stream = try conn.messages()

        // Lancer un lecteur dédié qui se termine quand le flux se ferme
        let reader = Task {
            for await _ in stream {
                // Pour M1, on ne vérifie pas le contenu; on lit au plus 1 message puis on sort
                break
            }
        }

        // Petite fenêtre pour laisser la source démarrer
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50 ms

        // Arrêter la pompe -> le flux doit se terminer et le task 'reader' finir proprement
        conn.stopPump()

        // Attendre la fin du lecteur (ignore les erreurs/cancel)
        _ = await reader.result
    }
}
