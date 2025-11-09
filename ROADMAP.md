# ROADMAP

> Objectif : couvrir **l’ensemble des API DBus** utiles côté client *et* serveur en Swift moderne (Swift 6.2), avec une ergonomie Swifty, de la sûreté mémoire et un modèle async/await. Implémentation basée sur **libdbus-1** via le target `.systemLibrary` CDbus (pas de dépendance GLib/GIO).

---

## Principes & Architecture

- **Couches** :
  1. **FFI Bas Niveau** (interop C direct) — type-safe wrappers, gestion des `DBusError`, RAII/ARC, conversions.
  2. **Core Swift** — `DBusConnection`, `DBusMessage`, `DBusBusName`, `DBusObjectPath`, `DBusSignature`, `DBusVariant`, encodage/décodage.
  3. **API Haute Niveau** — appels de méthodes typées, signaux via `AsyncStream`, propriétés, proxies (`DBusProxy`), export d’objets Swift.
  4. **Utilitaires** — introspection XML, **codegen** (proxy & serveurs Swift), monitoring, outillage CLI.
- **Concurrence** : Async/Await + `AsyncStream` pour signaux, intégration `DispatchSource`/`epoll` + `FileDescriptor` Swift 6 (Linux).
- **Sécurité** : erreurs Swifty, validation signatures, limites taille messages, *timeouts*, polkit (facultatif), contrôle des noms.
- **Stabilité API** : SemVer, migrations documentées, tests de compatibilité libdbus (1.12+).

---

## Milestones

### M0 — Foundations & Qualité
- [x] **Erreurs** : `DBusError` ↔︎ `Swift Error`, helpers (init/free), mapping codes.
- [x] **Gestion mémoire** : wrappers RAII pour `DBusMessage`, `DBusPendingCall`, `DBusConnection` (unref/ref).
- [ ] **Build Matrix CI** : Ubuntu 24.04 + Swift 6.2 (déjà fait), ajouter 22.04 & 24.10 si possible.
- [x] **Lint/format** : `swift-format`/`swiftlint` (optionnel).

### M1 — Connexions & Boucle I/O
- [x] `DBusConnection(session|system)` + options (auth, unique name).
- [x] **Integr. I/O** : *non-blocking* file descriptor, intégration `epoll`/`DispatchSource` -> *pump* de la connexion.
- [x] **Async** : `receive()` async, `messages()` -> `AsyncStream<DBusMessage>`.
- [x] **Ping/Self-Test** : appel `org.freedesktop.DBus.Hello`, `GetId`.

### M2 — Messages & Types
- [ ] **Construction/parse** de `DBusMessage` (Call, Return, Error, Signal).
- [ ] **Marshalling/Unmarshalling** complet : `Byte`, `Bool`, `Int{16,32,64}`, `UInt{16,32,64}`, `Double`, `String`, `ObjectPath`, `Signature`, `Array`, `Dict`, `Struct`, `Variant`, `UnixFD`.
- [ ] **Signatures** : parseur & validateurs Swifty (`DBusSignature`), helpers pour builder.
- [ ] **Codable Bridge** (v1) : `DBusEncodable/DBusDecodable` minimal pour structs Swift.

### M3 — Bus API (org.freedesktop.DBus)
- [x] **Request/ReleaseName**, **ListNames**, **NameOwnerChanged** (signal -> `AsyncStream`).
- [x] **Add/RemoveMatch** pour filtres signaux.
- [x] **Peer**: `Ping`, `GetMachineId`.
- [ ] **Monitoring** (optionnel, behind a flag).

### M4 — Proxies Client
- [x] `DBusProxy` générique : cible = (busName, objectPath, interface) + écoute de signaux.
- [x] `call(method:args:signature:) async throws -> Return` (helpers `call(arguments:)`, `callExpectingBasics)`).
- [x] **Signaux** : `proxy.signals("Interface", "Signal") -> AsyncStream<T>` (avec decode).
- [x] **Propriétés** (org.freedesktop.DBus.Properties) : `Get`, `Set`, `GetAll` typés (variants basiques).
- [ ] Hook d’invalidation auto du cache de propriétés (brancher sur signaux `PropertiesChanged`).

### M5 — Serveur / Export d’objets
- [ ] `DBusObject` protocole Swift (méthodes, signaux, propriétés).
- [ ] Enregistrement sur un `objectPath`, publication d’un **bus name** (avec `requestName`).
- [ ] Dispatch des appels entrants -> méthodes Swift async, encodage réponses/erreurs.
- [ ] Émission de **signaux** depuis Swift.
- [ ] **Introspection** auto (`org.freedesktop.DBus.Introspectable`) générée à partir des métadonnées Swift.

### M6 — Codegen & Outils
- [ ] **Introspection XML → Proxy Swift** (tool SPM `swift-dbus-gen`).
- [ ] **Stubs Serveur** générés à partir d’un schéma Swift/annotations.
- [ ] Exemple : proxy vers `org.freedesktop.login1`, `org.freedesktop.NetworkManager`, `org.freedesktop.timedate1`.

### M7 — Robustesse, Perf & DX
- [ ] **Timeouts** & cancellation (Task) pour RPC.
- [ ] **Retry/backoff** optionnel lors des pertes de bus.
- [ ] **Bench** (taille messages, latence, allocation).
- [ ] **Observabilité** : trace simple (log niveaux, hexdump marshalling sous flag).
- [ ] **Docs** DocC + guides : *Getting started*, *Client proxy*, *Export server*, *Signals*, *Properties*, *Codegen*.
- [ ] **Exemples** complets dans `Sources/swift-dbus-examples/` (client & serveur).

---

## Détails d’implémentation

### Connexion & I/O
- Exposer `DBusConnection` avec :
  - `init(bus: .session | .system, options: …)`
  - `requestName(_:)`, `releaseName(_:)`
  - `uniqueName`, `machineId`
  - `send(_ msg)`, `flush()`, `readWriteDispatch()`
- I/O loop :
  - Récupérer `dbus_connection_get_unix_fd()` (ou `dbus_watch` callbacks) et intégrer à `DispatchSource` (read).
  - Pumper `dbus_connection_read_write_dispatch` sans bloquer ; *coalesce* des événements.

### Messages & Types
- `DBusMessage` Swift (enum `case methodCall, methodReturn, error, signal`).
- Builders sûrs : `DBusEncoder`/`DBusDecoder` internes, garantissant la **validité des signatures** (tests exhaustifs).
- Support `UnixFD` via `SCM_RIGHTS` (si accessible via libdbus-1 sur Linux).

### Proxies & Propriétés
- `DBusProxy` minimal :
  ```swift
  let nm = DBusProxy(bus: .system, name: "org.freedesktop.NetworkManager",
                     path: "/org/freedesktop/NetworkManager",
                     interface: "org.freedesktop.NetworkManager")
  let version: String = try await nm.call("Version") // exemple si la méthode existe
  for await sig in nm.signals("PropertiesChanged") { ... }
  ```
- Propriétés : wrappers typés autour de `org.freedesktop.DBus.Properties` avec caching optionnel.

### Export Serveur
- Protocole :
  ```swift
  protocol DBusObject {
    static var interface: String { get }
    static var path: String { get }
    // annotations pour méthodes/propriétés/signaux
  }
  ```
- Génération dynamique de l’introspection à partir des métadonnées.
- Handlers de méthodes asynchrones ; mapping des erreurs Swift → `DBusError` (nom + message).

### Codegen
- Binaire `swift-dbus-gen` (SPM) :
  - Input : XML introspection / IDL maison.
  - Output : fichier Swift avec proxy/structs (types, enums, methods, signals).
  - Option `--server` pour générer un squelette d’export d’objets.

---

## Testing & Qualité

- **Unit tests** : marshalling, signatures, erreurs.
- **Integration tests** : contre un bus *session* lancé par test (`dbus-launch` ou session existante).
- **Samples e2e** : client/serveur local (mêmes process, bus privé avec `dbus_server_listen` ?).
- **CI** :
  - matrix Ubuntu (22.04, 24.04), Swift (6.2, 6.3 si dispo).
  - cache `.build` conditionnel.
  - job “Examples” qui exécutent de vrais appels sur le bus (marqué `needs: dbus`).
- **Fuzz** (optionnel) : fuzzer simple sur parseur de signatures/messages.

---

## Compat & Dépendances

- **libdbus-1** `>= 1.12` (Ubuntu 22.04+ OK).
- Linux only. (Cibler macOS > plus tard via `launchd`/XPC n’est pas prévu dans ce repo.)
- Sans dépendance GLib / GIO (GDBus), pour rester léger et natif Swift.

---

## Versioning & Releases

- `v0.1.0` : M0‑M1 stables (connexions + boucle I/O de base).
- `v0.2.0` : M2 (types/signatures) + premiers appels simples.
- `v0.3.0` : M3‑M4 (bus API + proxies).
- `v0.4.0` : M5 (serveur/export).
- `v0.5.0` : M6 (codegen) + examples avancés.
- `v1.0.0` : M7 finition, DocC + stabilité API.

---

## Tâches rapides à créer (Issues)

- [ ] M0: DBusError wrapper + tests
- [ ] M1: Connection async + `AsyncStream<DBusMessage>`
- [ ] M2: Encoder/Decoder + Signatures (100% types)
- [ ] M3: Bus API (names, matches, signals)
- [ ] M4: Proxy générique + Propriétés typées
- [ ] M5: Export d’objets + Introspection auto
- [ ] M6: Codegen (XML → Swift)
- [ ] M7: Timeouts/cancel + Logs + DocC
- [ ] Examples: login1, NetworkManager, timedate1
- [ ] CI: matrix + tests d’intégration bus
