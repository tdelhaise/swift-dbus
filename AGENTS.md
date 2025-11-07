# Repository Guidelines

## Project Structure & Module Organization
`Package.swift` wires three SPM targets: `CDbus` (system module exposing `dbus/dbus.h`), `SwiftDBus` (high-level API), and the example binary in `Sources/swift-dbus-examples`. Core sources live in `Sources/SwiftDBus`, while raw FFI shims and module maps sit in `Sources/CDbus`. Keep runnable samples under `Sources/swift-dbus-examples` and place new unit specs in `Tests/SwiftDBusTests`. Shared scripts, including format hooks, belong in `scripts/`. Avoid adding assets outside these directories unless the package manifest is updated accordingly.

## Build, Test, and Development Commands
- `swift build` — compiles the library and demo executable with the current toolchain.
- `swift run swift-dbus-examples` — launches the sample client that prints `libdbus` metadata; use it to sanity-check wiring against a live session bus.
- `swift test` — executes all test bundles inside `Tests/`, mirroring CI.
- `bash scripts/format.sh` — runs `swift-format` and `swiftlint` to enforce style before raising a PR.

## Coding Style & Naming Conventions
Adopt Swift API Design Guidelines: UpperCamelCase for types/modules, lowerCamelCase for functions, methods, and properties. Prefer explicit access control and keep public surface APIs documented with Swift comments. Indent using four spaces; avoid tabs. Run `scripts/format.sh` prior to pushing to ensure `swift-format` (configured by `.swift-format`) and `swiftlint` stay in sync with CI. Organize files by feature (marshalling, proxies, session helpers) rather than type to mirror the roadmap modules.

## Testing Guidelines
Unit tests use XCTest within `Tests/SwiftDBusTests`. Name test files after the class under test (`FooMarshallingTests.swift`) and keep individual methods prefixed with `test_` for grepability. Aim to cover new marshalling paths plus failure modes (e.g., invalid signatures) and run `swift test --enable-code-coverage` locally if you touch critical encoding/decoding logic. For bus-dependent flows, wrap calls inside `dbus-run-session` the way CI does to avoid leaking into the system bus.

## Commit & Pull Request Guidelines
Follow the existing Conventional Commits style visible in `git log` (e.g., `feat(M2.2): …`, `ci: …`). Scope names should match roadmap modules or layers (`marshal`, `calls`, `docs`). Keep commits focused and include concise French or English summaries. Pull requests must explain the feature slice, list test evidence (`swift test`, `swift run swift-dbus-examples`), and link any roadmap issue. Add screenshots or logs only when they materially clarify behavior, such as new example output or coverage deltas. Ensure CI passes before requesting review.
