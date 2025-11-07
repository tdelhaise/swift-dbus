# swift-dbus

[![CI (Linux)](https://github.com/tdelhaise/swift-dbus/actions/workflows/ci.yml/badge.svg)](https://github.com/tdelhaise/swift-dbus/actions/workflows/ci.yml)


> Squelette SPM minimal pour un binding Swift de **D-Bus** sous Linux.
> Cible : Ubuntu 24.04.3 + Swift 6.2 (installé via Swiftly).

## Pré-requis (Ubuntu 24.04.3)

```bash
# Swift via Swiftly (https://swiftlang.github.io/swiftly/)
# Assurez-vous d'avoir Swift 6.2 actif dans votre shell.
swift --version

# Headers/SDK D-Bus
sudo apt update
sudo apt install -y libdbus-1-dev
```

## Construction

```bash
git clone <votre-repo-ou-ce-dossier> swift-dbus
cd swift-dbus

# Construire la librairie et l'exécutable d'exemple
swift build

# Lancer l'exemple
swift run swift-dbus-examples
```

Vous devriez voir la version de `libdbus` ainsi qu'un indicateur de disponibilité.

## Tests & Qualité

- `bash scripts/test.sh` – lance `swift test` dans un `dbus-run-session` dédié (utile sur CI/sandbox).
- `bash scripts/format.sh` – applique `swift-format` puis `swiftlint --fix && lint --strict`.

Les tests d’intégration ouvrent un vrai bus session temporaire, requièrent donc `libdbus-1` et `dbus-run-session`.

## Structure

- `Package.swift` – Dépendance système vers `libdbus-1` via un target `.systemLibrary` (`CDbus`).
- `Sources/CDbus` – Module système SPM avec `module.modulemap` pointant vers `shim.h` qui inclut `<dbus/dbus.h>`.
- `Sources/SwiftDBus` – API Swift de plus haut niveau (placeholder à étendre).
- `Sources/swift-dbus-examples` – Petit binaire de démonstration.
- `Tests/SwiftDBusTests` – Tests unitaires minimalistes.

## Aperçu API

### Connexion & appels bus

```swift
let connection = try DBusConnection(bus: .session)

_ = try connection.requestName("org.example.App")
let id = try connection.getBusId()
let machineId = try connection.getMachineId()
let names = try connection.listNames()
let owner = try connection.getNameOwner("org.freedesktop.DBus")
try connection.pingPeer()
```

### Écouter un signal typé

```swift
let rule = DBusMatchRule.signal(
    interface: "org.freedesktop.DBus",
    member: "NameOwnerChanged",
    arg0: "org.example.App"
)

for await signal in try connection.signals(matching: rule) {
    print("Signal from \(signal.sender ?? "-"): \(signal.args)")
}
```

L’API `signals(matching:)` inscrit automatiquement la règle côté bus (`AddMatch`) et la retire (`RemoveMatch`) à la fin du flux.

### Proxy haut niveau (WIP M4)

```swift
let proxy = DBusProxy(
    connection: connection,
    destination: "org.freedesktop.DBus",
    path: "/org/freedesktop/DBus",
    interface: "org.freedesktop.DBus"
)

let busId = try proxy.callExpectingFirstString("GetId")

for await change in try proxy.signals(member: "NameOwnerChanged", arg0: "org.example.App") {
    print("Change: \(change.args)")
}
```

### Propriétés via `org.freedesktop.DBus.Properties`

```swift
if case .stringArray(let features) = try proxy.getProperty("Features") {
    print("Bus features: \(features)")
}

let all = try proxy.getAllProperties()
print(all.keys)
```

## CI (Ubuntu)

Un workflow GitHub Actions est fourni pour builder et tester sur `ubuntu-24.04` avec Swift 6.2.

## 🧭 Roadmap

Le projet **swift-dbus** vise à offrir une couverture complète et moderne de l’API **D-Bus** en Swift (6.2+), pour Linux.

La feuille de route détaillant les différentes étapes (wrappers bas niveau, API Swift, proxies, export d’objets, génération de code, etc.) est disponible ici :

👉 [Consulter la ROADMAP →](./ROADMAP.md)

Tu y trouveras la progression prévue, les milestones et les futurs objectifs de compatibilité et d’outillage.
