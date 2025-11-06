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

## Structure

- `Package.swift` – Dépendance système vers `libdbus-1` via un target `.systemLibrary` (`CDbus`).
- `Sources/CDbus` – Module système SPM avec `module.modulemap` pointant vers `shim.h` qui inclut `<dbus/dbus.h>`.
- `Sources/SwiftDBus` – API Swift de plus haut niveau (placeholder à étendre).
- `Sources/swift-dbus-examples` – Petit binaire de démonstration.
- `Tests/SwiftDBusTests` – Tests unitaires minimalistes.

## CI (Ubuntu)

Un workflow GitHub Actions est fourni pour builder et tester sur `ubuntu-24.04` avec Swift 6.2.

## Roadmap (à adapter)

- Enveloppe Swift sûre pour : connexions (session/system), messages, bus names, introspection.
- Intégration avec `Dispatch`/`async`/`await` et gestion fine des erreurs.
- Couverture de test + exemples plus complets.
