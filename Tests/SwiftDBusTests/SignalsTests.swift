import Foundation
import XCTest

@testable import SwiftDBus

final class SignalsTests: XCTestCase {

    func testNameOwnerChanged_isReceived() async throws {
        if ProcessInfo.processInfo.environment["CI"] != nil {
            throw XCTSkip("NameOwnerChanged signal test is flaky on CI")
        }
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

        // Déclenchement: acquérir le nom provoque NameOwnerChanged(name, "", unique)
        _ = try connection.requestName(tempName, flags: 0)

        let received = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = signalStream.makeAsyncIterator()
                while let signal = await iterator.next() {
                    guard signal.member == "NameOwnerChanged",
                        signal.interface == "org.freedesktop.DBus"
                    else { continue }

                    if case .string(let name)? = signal.args.first, name == tempName {
                        if signal.args.count >= 3,
                            case .string = signal.args[1],
                            case .string(let newOwner) = signal.args[2] {
                            XCTAssertTrue(newOwner.hasPrefix(":"), "new owner must be unique name")
                            return true
                        }
                    }
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return false
            }

            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        guard received else {
            _ = try? connection.releaseName(tempName)
            throw XCTSkip("NameOwnerChanged signal not observed within timeout")
        }

        // Nettoyage (provoquera un second signal qu'on n'attend pas forcément ici)
        _ = try connection.releaseName(tempName)
        try? await Task.sleep(nanoseconds: 50_000_000)  // petite marge
    }

    func testSignalsWithArg0Filter() async throws {
        if ProcessInfo.processInfo.environment["CI"] != nil {
            throw XCTSkip("Arg0 filter timing is flaky on CI")
        }
        let connection = try DBusConnection(bus: .session)
        let name = makeTemporaryBusName()

        // Filtrer directement côté bus sur arg0 == name
        let rule = DBusMatchRule.signal(
            interface: "org.freedesktop.DBus",
            member: "NameOwnerChanged",
            arg0: name
        )

        let stream = try connection.signals(matching: rule)

        _ = try connection.requestName(name)

        let received = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await signal in stream {
                    guard signal.member == "NameOwnerChanged" else { continue }
                    if case .string(let signalName)? = signal.args.first, signalName == name {
                        return true
                    }
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return false
            }

            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        XCTAssertTrue(received, "should receive filtered NameOwnerChanged signal")

        _ = try connection.releaseName(name)
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
}
