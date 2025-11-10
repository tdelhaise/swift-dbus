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

### Appels multi-arguments & retour typé

```swift
let proxy = DBusProxy(
    connection: connection,
    destination: "org.freedesktop.DBus",
    path: "/org/freedesktop/DBus",
    interface: "org.freedesktop.DBus"
)

let status: UInt32 = try proxy.callExpectingSingle(
    "RequestName",
    typedArguments: DBusArguments("org.example.App", UInt32(0))
)

struct ListNamesResponse: DBusReturnDecodable {
    let names: [String]

    init(from decoder: inout DBusDecoder) throws {
        names = try decoder.next([String].self)
    }
}

let namesResult: ListNamesResponse = try proxy.callExpecting(
    "ListNames",
    as: ListNamesResponse.self
)
print("Bus exposes \(namesResult.names.count) names")

// Helper DBusArguments(...) construit la liste d'arguments (ici String + UInt32)
```

Pour les méthodes qui renvoient plusieurs valeurs, utilisez les helper `DBusTuple2` / `DBusTuple3` ou faites
conformer votre propre struct à `DBusReturnDecodable`.

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
let features: [String] = try proxy.getProperty("Features")
let all = try proxy.getAllProperties()
print(all["Features"] ?? .unsupported(0))

let cache = DBusPropertyCache()
let cachedFeatures: [String] = try proxy.getProperty("Features", cache: cache)
let refreshedFeatures: [String] = try proxy.getProperty(
    "Features",
    cache: cache,
    refreshCache: true
)
print("Cached features \(cachedFeatures), live value \(refreshedFeatures)")

let subscription = try proxy.autoInvalidatePropertyCache(cache)
defer { subscription.cancel() }
// Toute notification PropertiesChanged videra automatiquement les entrées invalides.
```

### Signaux typés via proxy

```swift
struct NameOwnerChangedSignal: DBusSignalPayload {
    static let member = "NameOwnerChanged"

    let name: String
    let oldOwner: String
    let newOwner: String

    init(from decoder: inout DBusDecoder) throws {
        name = try decoder.next()
        oldOwner = try decoder.next()
        newOwner = try decoder.next()
    }
}

let typedStream = try proxy.signals(NameOwnerChangedSignal.self, arg0: "org.example.App")

for await signal in typedStream {
    print("\(signal.name) moved from \(signal.oldOwner) -> \(signal.newOwner)")
}
```

### Exporter un objet DBus (M5 – WIP)

```swift
final class EchoObject: DBusObject {
    static let interface = "org.example.Echo"
    static let path = "/org/example/Echo"
    static let pingedSignal = DBusSignalDescription(
        name: "Pinged",
        arguments: [.field("payload", signature: "s")],
        documentation: "Signale l’envoi d’un message."
    )

    var methods: [DBusMethod] {
        [
            .returning(
                "Echo",
                arguments: [.input("message", signature: "s")],
                returns: [.output("echo", signature: "s")],
                documentation: "Renvoie la chaîne fournie."
            ) { _, decoder in
                try decoder.next(String.self)
            },
            .returning("Send") { call, decoder in
                let payload: String = try decoder.next()
                try call.signalEmitter.emit(Self.pingedSignal) { encoder in
                    encoder.encode(payload)
                }
                return payload
            }
        ]
    }

    var signals: [DBusSignalDescription] { [Self.pingedSignal] }
}

let connection = try DBusConnection(bus: .session)
let exporter = DBusObjectExporter(connection: connection)
let registration = try exporter.register(
    EchoObject(),
    busName: "org.example.Echo",
    requestNameFlags: UInt32(DBUS_NAME_FLAG_DO_NOT_QUEUE)
)
// Libère l'objet & le nom de bus automatiquement
defer { registration.cancel() }
```

Les métadonnées (arguments, docstrings, signaux) sont automatiquement traduites en XML
`org.freedesktop.DBus.Introspectable`, pratique pour les outils ou la génération de code.

### Propriétés exportées + `PropertiesChanged`

```swift
final class SettingsObject: DBusObject {
    static let interface = "org.example.Settings"
    static let path = "/org/example/Settings"

    private var count: Int32 = 0

    var properties: [DBusProperty] {
        [
            .readOnly("Name") { _ in "SwiftDBus" },
            .readWrite(
                "Count",
                get: { _ in self.count },
                set: { newValue, invocation in
                    self.count = newValue
                    try invocation.signalEmitter.emitPropertiesChanged(
                        interface: Self.interface,
                        changed: ["Count": newValue.dbusValue]
                    )
                }
            )
        ]
    }
}
```

L’exporteur gère automatiquement `org.freedesktop.DBus.Properties` (`Get`, `Set`, `GetAll`) et injecte
les propriétés dans l’introspection si vous ne fournissez pas de XML personnalisé.
Utilisez `emitPropertiesChanged` pour prévenir les clients qui mettent en cache leurs valeurs.

Les clients peuvent ensuite appeler `Echo` ou écouter le signal `Pinged` via un `DBusProxy`.

### Consulter l’introspection côté client

```swift
if let interfaceInfo = try proxy.introspectedInterface() {
    print("Méthodes exposées :", interfaceInfo.methods.map(\.name))
    print("Signaux :", interfaceInfo.signals.map(\.name))
    print("Propriétés :", interfaceInfo.properties.map(\.name))
}

// Instancier un proxy avec caches partagés (propriétés + introspection).
let caches = DBusProxyCaches(
    propertyCache: DBusPropertyCache(),
    introspectionCache: DBusIntrospectionCache()
)
let proxy = DBusProxy(
    connection: connection,
    destination: "org.freedesktop.DBus",
    path: "/org/freedesktop/DBus",
    interface: "org.freedesktop.DBus",
    caches: caches
)

// APIs dérivées de l'introspection : propriétés, méthodes et signaux typés.
let metadata = try proxy.metadata()
let featuresHandle = try metadata.property("Features", as: [String].self)
let features = try proxy.getProperty(featuresHandle)

let listNames = try metadata.method("ListNames", returns: [String].self)
let names: [String] = try proxy.call(listNames)

let nameOwnerChanged = try metadata.signal(NameOwnerChangedSignal.self)
let stream = try proxy.signals(nameOwnerChanged, arg0: "org.example.Service")

// Accès au cache (pas de ré-introspection tant que non invalidé).
if let cached = proxy.cachedMetadata {
    print("Metadata en cache pour \(cached.name)")
}
proxy.invalidateCachedMetadata()

// Helpers d'invalidation des propriétés.
try proxy.autoInvalidateCachedPropertyCache()
proxy.invalidateCachedProperties()
```

L’exporteur additionne automatiquement toutes les interfaces présentes sur un même `objectPath`
et expose les sous-nœuds déclarés (`<node name="Child"/>`) via `org.freedesktop.DBus.Introspectable`,
ce qui simplifie la découverte côté client.

## CI (Ubuntu)

Un workflow GitHub Actions est fourni pour builder et tester sur `ubuntu-24.04` avec Swift 6.2.

## 🧭 Roadmap

Le projet **swift-dbus** vise à offrir une couverture complète et moderne de l’API **D-Bus** en Swift (6.2+), pour Linux.

La feuille de route détaillant les différentes étapes (wrappers bas niveau, API Swift, proxies, export d’objets, génération de code, etc.) est disponible ici :

👉 [Consulter la ROADMAP →](./ROADMAP.md)

Tu y trouveras la progression prévue, les milestones et les futurs objectifs de compatibilité et d’outillage.
