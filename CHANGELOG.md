# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- (prévu M3) Encodeur/décodeur de types de base (bool, int32, double, string, object path, signature) et appels avec arguments.
- (prévu) Proxies haut niveau et export d’objets.
- (prévu) Générateur de code à partir d’introspection XML.

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

- [Unreleased]: https://github.com/tdelhaise/swift-dbus/compare/v0.3.0...HEAD
- [v0.3.0]: https://github.com/tdelhaise/swift-dbus/compare/v0.2.0...v0.3.0
- [v0.2.0]: https://github.com/tdelhaise/swift-dbus/compare/v0.1.0...v0.2.0
- [v0.1.0]: https://github.com/tdelhaise/swift-dbus/releases/tag/v0.1.0

