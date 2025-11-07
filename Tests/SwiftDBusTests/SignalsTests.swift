import XCTest

@testable import SwiftDBus

final class SignalsTests: XCTestCase {

    func testNameOwnerChanged_isReceived() async throws {
        let connection = try DBusConnection(bus: .session)

        // Règle: signal org.freedesktop.DBus.NameOwnerChanged
        let rule = DBusMatchRule.signal(
            interface: "org.freedesktop.DBus",
            member: "NameOwnerChanged"
        )

        let signalStream = try connection.signals(matching: rule)
        _ = try connection.uniqueName()

        // Choisir un nom temp spécifique à ce test
        let tempName = makeTemporaryBusName()

        // Consommateur: on s'attend à recevoir un signal après acquisition
        let expectation = XCTestExpectation(description: "received NameOwnerChanged")

        let task = Task {
            var iterator = signalStream.makeAsyncIterator()
            // On attend au plus 3s pour le premier signal attendu
            let deadline = DispatchTime.now().uptimeNanoseconds + 3_000_000_000
            while DispatchTime.now().uptimeNanoseconds < deadline {
                if let signal = await iterator.next() {
                    // Signature du signal: (name, old_owner, new_owner) -> (s,s,s)
                    guard signal.member == "NameOwnerChanged",
                        signal.interface == "org.freedesktop.DBus"
                    else { continue }

                    // Vérifier que c'est bien pour notre nom
                    if case .string(let name)? = signal.args.first, name == tempName {
                        // old_owner: "" (empty), new_owner: ":xyz..."
                        if signal.args.count >= 3 {
                            if case .string = signal.args[1],
                                case .string(let newOwner) = signal.args[2] {
                                XCTAssertTrue(newOwner.hasPrefix(":"), "new owner must be unique name")
                                expectation.fulfill()
                                break
                            }
                        }
                    }
                } else {
                    break
                }
            }
        }

        // Déclenchement: acquérir le nom provoque NameOwnerChanged(name, "", unique)
        _ = try connection.requestName(tempName, flags: 0)

        // Attendre le signal
        await fulfillment(of: [expectation], timeout: 3.0)

        // Nettoyage (provoquera un second signal qu'on n'attend pas forcément ici)
        _ = try connection.releaseName(tempName)

        task.cancel()
        try? await Task.sleep(nanoseconds: 50_000_000)  // petite marge
    }

    func testSignalsWithArg0Filter() async throws {
        let connection = try DBusConnection(bus: .session)
        let name = makeTemporaryBusName()

        // Filtrer directement côté bus sur arg0 == name
        let rule = DBusMatchRule.signal(
            interface: "org.freedesktop.DBus",
            member: "NameOwnerChanged",
            arg0: name
        )

        let stream = try connection.signals(matching: rule)
        let gotSignal = XCTestExpectation(description: "received filtered signal")

        let task = Task {
            for await signal in stream {
                guard signal.member == "NameOwnerChanged" else { continue }
                if case .string(let signalName)? = signal.args.first, signalName == name {
                    gotSignal.fulfill()
                    break
                }
            }
        }

        _ = try connection.requestName(name)
        await fulfillment(of: [gotSignal], timeout: 1.5)
        _ = try connection.releaseName(name)

        task.cancel()
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
}

private func makeTemporaryBusName(
    prefix: String = "org.swiftdbus.test",
    suffixLength: Int = 8
) -> String {
    let random = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    return "\(prefix).x\(random.prefix(suffixLength))"
}
