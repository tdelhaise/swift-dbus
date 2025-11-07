import Foundation

func makeTemporaryBusName(
    prefix: String = "org.swiftdbus.test",
    suffixLength: Int = 8
) -> String {
    let random = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    return "\(prefix).x\(random.prefix(suffixLength))"
}
