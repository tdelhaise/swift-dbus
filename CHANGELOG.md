# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `DBusBasicValue`/`DBusDecoder`: encode/décode des bases étendus (`uint32`, struct, arrays), génération de signatures, variants `{sv}`.
- `DBusProxy` typed APIs: `callExpectingSingle`, `callExpecting(decode:)`, `signals(member:as:)`, propriétés typées (`getProperty<T>`, `setProperty<T>`).
- README exemples : appels multi-arguments, propriétés typées, signaux typés.
- (prévu) Export d’objets Swift (serveur).
- (prévu M6) Générateur de code à partir d’introspection XML.
- `DBusObjectExporter.register` now returns a `DBusObjectRegistration` handle (RAII) and can request/release bus names automatically.
- Introspection responses now aggregate every interface registered on a path and list child nodes, matching DBus expectations.

### Tests
- `ProxyTests`: appels RequestName/ReleaseName, décodage signal typé, propriétés typées, `GetAll`.

---

## [v0.6.0] - 2025-11-07 — **Signals & Bus Helpers (M3 completion)**
### Added
- `DBusMatchRule`, `DBusSignal` et `DBusConnection.signals(matching:)` pour s’abonner aux signaux DBus (tests `SignalsTests` NameOwnerChanged + filtre `arg0`).
- `DBusConnection` : helpers `requestName`, `releaseName`, `listNames`, `getNameOwner`, `getBusId`, `pingPeer`, `getMachineId`.
- Readme : section API (exemples de connexion, signaux) + section “Tests & Qualité”.
- `scripts/test.sh` encapsule `dbus-run-session -- swift test` (utilisé localement et en CI).
- `AGENTS.md` : guide contributeur (structure, conventions, commandes).
- Début de M4 : `DBusProxy` (appels bruts, helper `callExpectingFirstString`, `signals(member:)`).

### Changed
- `ROADMAP.md` : jalons M0-M3 cochés, M3 ➜ done, focus sur M4+.
- `.github/workflows/ci.yml` : les jobs Jammy/Noble utilisent `bash scripts/test.sh -v` pour les tests.
- README/ROADMAP synchronisés avec les nouvelles APIs et scripts.

### Tests
- `scripts/test.sh` (dbus-run-session) devient la commande canonique pour `swift test`.

---

## [v0.4.0] - 2025-11-07
### Added
- `DBusMarshal`: append {String, Bool, Int32, Double} et decode {firstString, firstBool, firstInt32, firstDouble}.
- `DBusMessageBuilder.methodCall1StringArg(...)` pour construire un appel avec 1 argument `String`.
- `DBusConnection.getNameOwner(_:) -> String`.

### Tests
- `MarshalAndCallWithArgsTests`: appel réel `GetNameOwner("org.freedesktop.DBus")` (tolère unique name `:...` ou echo du well-known selon l’environnement).

### CI
- Les tests continuent d’être exécutés sous `dbus-run-session`.

---

## [v0.3.1] - 2025-11-07
### Fixed
- CI: exécute les tests sous `dbus-run-session` et installe `dbus` pour fournir un session bus en environnement conteneurisé (jammy/noble).

---

## [v0.3.0] - 2025-11-07 — **M2: Minimal message call & decode**
### Added
- `DBusCConstants.swift`: miroirs Swift des macros `dbus-protocol.h` (types, fragments de signatures, message types).
- `DBusMessageBuilder.methodCall(...)`: construction d’un `METHOD_CALL` minimal.
- `DBusMessageDecode.firstString(...)`: décodage du **premier argument `string`** d’un `METHOD_RETURN`.
- `DBusConnection.callRaw(...)`: envoi bloquant via `dbus_connection_send_with_reply_and_block`.
- Helpers concrets :
  - `DBusConnection.getBusId()` → `org.freedesktop.DBus.GetId`
  - `DBusConnection.pingPeer()` → `org.freedesktop.DBus.Peer.Ping`
- Tests `CallTests` (GetId non-vide, Ping ne jette pas).

### Changed
- Comparaisons de type message basées sur `DBusMsgType` (Swift), pas sur les macros C.

---

## [v0.2.0] - 2025-11-06 — **M1: Connection & async message pump**
### Added
- `DBusConnection` (session/system), non-bloquant, `uniqueName()`.
- Boucle I/O asynchrone via `DispatchSourceRead` sur le FD libdbus :
  - `messages() -> AsyncStream<DBusMessageRef>`
- Tests `ConnectionTests` :
  - ouverture de session + `uniqueName` commence par `:`
  - démarrage/arrêt propre du flux.
- Exemple CLI : affiche version libdbus, nom unique et draine brièvement le flux.

### Technical
- `DBusConnection` et `DBusMessageRef` marqués `@unchecked Sendable` (interop C avec sérialisation via queue dédiée).

---

## [v0.1.0] - 2025-11-06 — **M0: Foundations & Quality**
### Added
- `DBusErrorSwift` + helper `withDBusError{}` (mapping propre de `DBusError` C → `Error` Swift).
- RAII pour gestion mémoire sûre :
  - `DBusMessageRef` (unref automatique)
  - `DBusPendingCallRef` (unref automatique)
- Tests unitaires :
  - non-throw si aucune erreur n’est posée,
  - erreur forcée via `dbus_set_error_const` (C strings statiques),
  - création d’un `DBusMessage` (unref sur `deinit`).
- CI Linux : jobs containerisés (Swift 6.2) + installation `libdbus-1-dev`.
- Formatage & lint : `swift-format` + `SwiftLint` (+ hook `pre-commit` local).

---

## Links

- [Unreleased]: https://github.com/tdelhaise/swift-dbus/compare/v0.6.0...HEAD
- [v0.6.0]: https://github.com/tdelhaise/swift-dbus/compare/v0.4.0...v0.6.0
- [v0.3.0]: https://github.com/tdelhaise/swift-dbus/compare/v0.2.0...v0.3.0
- [v0.2.0]: https://github.com/tdelhaise/swift-dbus/compare/v0.1.0...v0.2.0
- [v0.1.0]: https://github.com/tdelhaise/swift-dbus/releases/tag/v0.1.0
