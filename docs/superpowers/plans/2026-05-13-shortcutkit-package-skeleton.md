# ShortcutKit Package Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the ShortcutKit Swift package skeleton — `Package.swift`, three library/test target pairs, repo tooling (lint/format/CI/hooks), DocC catalog stubs, and user-facing docs — so subsequent phase implementations have a clean home. **No feature code in this plan.**

**Architecture:** One Swift Package with three library products (`ShortcutKit`, `ShortcutKitUI`, `ShortcutKitGlobal`) and three matching test targets. `ShortcutField 2.0.0+` is a hard dependency of Core and UI. Repo tooling mirrors ShortcutField exactly (`.swiftlint.yml`, `.swiftformat`, `lefthook.yml`, `Justfile`, GitHub Actions CI). Each target has its own DocC catalog with a stub landing article.

**Tech Stack:** Swift 6.2, macOS 13+, SwiftPM, SwiftLint, SwiftFormat, lefthook (pre-commit/pre-push), GitHub Actions, Swift Testing (`@Test`/`#expect`), Swift-DocC.

**Spec reference:** [`docs/superpowers/specs/2026-05-13-shortcutkit-package-design.md`](../specs/2026-05-13-shortcutkit-package-design.md) — especially §1.1 (implementation deliverable for this plan), §3 (package layout), §7 (cross-phase invariants), §8 (repo tooling).

**Deviation from spec:** The spec lists an `Example/ShortcutKitExample.xcodeproj` skeleton in §1.1 / §11. This plan creates the `Example/` directory with a README placeholder but **does not create the Xcode project**, because: (a) generating a working `.xcodeproj` from CLI without XcodeGen (not installed) means hand-writing `project.pbxproj` (error-prone, several hundred lines), (b) the example has nothing to demo until Phase 1 ships some API. The Xcode project will be added as the first task of Phase 1's plan (when there's a Core API to wire up). The `Justfile`'s `example` recipe is omitted until then.

**Working directory:** All paths are absolute under `/Users/nielsmadan/wrksp/juggler/ShortcutKit/` unless noted.

---

## File Structure (end state)

```
ShortcutKit/
├── .git/                                          (already exists)
├── .github/
│   └── workflows/
│       └── ci.yml                                 ← Task 5
├── .gitignore                                     ← Task 2
├── .spi.yml                                       ← Task 6
├── .swiftformat                                   ← Task 2
├── .swiftlint.yml                                 ← Task 2
├── AGENTS.md                                      ← Task 8
├── CHANGELOG.md                                   ← Task 7
├── CLAUDE.md                                      ← Task 8
├── Example/
│   └── README.md                                  ← Task 10
├── Justfile                                       ← Task 3
├── LICENSE                                        ← Task 7
├── Package.swift                                  ← Task 1
├── README.md                                      ← Task 7
├── ShortcutKitDevelopment.md                      (already exists)
├── Sources/
│   ├── ShortcutKit/
│   │   ├── ShortcutKit.swift                      ← Task 1
│   │   └── ShortcutKit.docc/
│   │       └── ShortcutKit.md                     ← Task 9
│   ├── ShortcutKitUI/
│   │   ├── ShortcutKitUI.swift                    ← Task 1
│   │   └── ShortcutKitUI.docc/
│   │       └── ShortcutKitUI.md                   ← Task 9
│   └── ShortcutKitGlobal/
│       ├── ShortcutKitGlobal.swift                ← Task 1
│       └── ShortcutKitGlobal.docc/
│           └── ShortcutKitGlobal.md               ← Task 9
├── Tests/
│   ├── ShortcutKitTests/
│   │   └── ShortcutKitTests.swift                 ← Task 1
│   ├── ShortcutKitUITests/
│   │   └── ShortcutKitUITests.swift               ← Task 1
│   └── ShortcutKitGlobalTests/
│       └── ShortcutKitGlobalTests.swift           ← Task 1
├── docs/
│   └── superpowers/
│       ├── plans/
│       │   └── 2026-05-13-shortcutkit-package-skeleton.md (this file)
│       └── specs/
│           └── 2026-05-13-shortcutkit-package-design.md
└── lefthook.yml                                   ← Task 4
```

---

## Task 1: Package.swift + minimum sources to build

**Goal:** Package builds and tests pass with empty placeholder modules. ShortcutField dependency resolves.

**Files:**
- Create: `Package.swift`
- Create: `Sources/ShortcutKit/ShortcutKit.swift`
- Create: `Sources/ShortcutKitUI/ShortcutKitUI.swift`
- Create: `Sources/ShortcutKitGlobal/ShortcutKitGlobal.swift`
- Create: `Tests/ShortcutKitTests/ShortcutKitTests.swift`
- Create: `Tests/ShortcutKitUITests/ShortcutKitUITests.swift`
- Create: `Tests/ShortcutKitGlobalTests/ShortcutKitGlobalTests.swift`

- [ ] **Step 1: Write `Package.swift`**

Content:
```swift
// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ShortcutKit",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "ShortcutKit",       targets: ["ShortcutKit"]),
        .library(name: "ShortcutKitUI",     targets: ["ShortcutKitUI"]),
        .library(name: "ShortcutKitGlobal", targets: ["ShortcutKitGlobal"]),
    ],
    dependencies: [
        .package(url: "https://github.com/nielsmadan/ShortcutField", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "ShortcutKit",
            dependencies: [.product(name: "ShortcutField", package: "ShortcutField")]
        ),
        .target(
            name: "ShortcutKitUI",
            dependencies: [
                "ShortcutKit",
                .product(name: "ShortcutField", package: "ShortcutField"),
            ]
        ),
        .target(
            name: "ShortcutKitGlobal",
            dependencies: ["ShortcutKit"]
        ),
        .testTarget(name: "ShortcutKitTests",       dependencies: ["ShortcutKit"]),
        .testTarget(name: "ShortcutKitUITests",     dependencies: ["ShortcutKitUI"]),
        .testTarget(name: "ShortcutKitGlobalTests", dependencies: ["ShortcutKitGlobal"]),
    ]
)
```

- [ ] **Step 2: Create the Core module file with the ShortcutField re-export**

Path: `Sources/ShortcutKit/ShortcutKit.swift`
```swift
// ShortcutKit — public umbrella module.
//
// Re-exports ShortcutField so adopters get the `Shortcut`, `ContinuousShortcut`,
// and related types with a single `import ShortcutKit`. Phase 1 adds the public
// registry, dispatch, and persistence APIs on top.

@_exported import ShortcutField
```

- [ ] **Step 3: Create the UI module placeholder**

Path: `Sources/ShortcutKitUI/ShortcutKitUI.swift`
```swift
// ShortcutKitUI — auto-generated settings UI, legend, and discoverability HUD.
// Public API arrives in Phase 2.

import ShortcutKit
```

- [ ] **Step 4: Create the Global module placeholder**

Path: `Sources/ShortcutKitGlobal/ShortcutKitGlobal.swift`
```swift
// ShortcutKitGlobal — system-wide hotkeys via Carbon RegisterEventHotKey.
// Public API arrives in Phase 3.

import ShortcutKit
```

- [ ] **Step 5: Create the three test placeholders**

Path: `Tests/ShortcutKitTests/ShortcutKitTests.swift`
```swift
import Testing

@Test func corePlaceholder() {
    // Replaced by Phase 1 tests.
}
```

Path: `Tests/ShortcutKitUITests/ShortcutKitUITests.swift`
```swift
import Testing

@Test func uiPlaceholder() {
    // Replaced by Phase 2 tests.
}
```

Path: `Tests/ShortcutKitGlobalTests/ShortcutKitGlobalTests.swift`
```swift
import Testing

@Test func globalPlaceholder() {
    // Replaced by Phase 3 tests.
}
```

- [ ] **Step 6: Verify `swift build` succeeds**

Run from the package root:
```bash
swift build
```

Expected: Resolves `ShortcutField 2.0.0+` from GitHub, compiles all three targets with no errors. Output ends with `Build complete!`.

Troubleshooting if it fails:
- "no such package 'ShortcutField'" — confirm ShortcutField repo is publicly accessible at `github.com/nielsmadan/ShortcutField` and has a `v2.0.0` tag.
- "platform 'macOS 13.0' is not supported" — confirm running on macOS / Xcode toolchain (not Linux).

- [ ] **Step 7: Verify `swift test` succeeds**

Run:
```bash
swift test
```

Expected: All three placeholder tests pass. Output includes `Test Suite 'All tests' passed`.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources/ Tests/
git commit -m "feat: package skeleton with three targets and ShortcutField re-export"
```

---

## Task 2: Static analysis configs (.gitignore, .swiftlint.yml, .swiftformat)

**Goal:** Lint and format configs match ShortcutField. Running them on the placeholder sources produces no violations.

**Files:**
- Create: `.gitignore`
- Create: `.swiftlint.yml`
- Create: `.swiftformat`

- [ ] **Step 1: Write `.gitignore`**

Content (identical to ShortcutField's):
```
.DS_Store
.build/
.swiftpm/
Example/.DS_Store
Example/*/xcuserdata/
Example/*.xcodeproj/project.xcworkspace/xcuserdata/
Example/*.xcodeproj/xcuserdata/
.claude/
```

- [ ] **Step 2: Write `.swiftlint.yml`**

Content (identical to ShortcutField's — verified by `cat /Users/nielsmadan/wrksp/juggler/ShortcutField/.swiftlint.yml`):
```yaml
disabled_rules:
  - trailing_whitespace
  - trailing_comma
  - opening_brace
  - line_length
  - type_body_length
  - file_length
  - static_over_final_class

opt_in_rules:
  - empty_count
  - explicit_init
  - first_where
  - toggle_bool
  - unavailable_function

excluded:
  - .build

identifier_name:
  min_length: 1
  max_length: 50

type_name:
  min_length: 2
  max_length: 50

cyclomatic_complexity:
  warning: 15
  error: 30

function_body_length:
  warning: 80
  error: 150

function_parameter_count:
  warning: 8
  error: 10

nesting:
  type_level: 2

large_tuple:
  warning: 3
```

- [ ] **Step 3: Write `.swiftformat`**

Content (identical to ShortcutField's):
```
--indent 4
--indentcase false
--trimwhitespace always
--voidtype void
--semicolons inline
--swiftversion 6.0
--maxwidth 120
```

- [ ] **Step 4: Verify swiftlint passes on the placeholder sources**

Run:
```bash
swiftlint --strict
```

Expected: `Done linting! Found 0 violations, 0 serious in N files.` (exit 0).

If swiftlint isn't installed: `brew install swiftlint` then retry.

- [ ] **Step 5: Verify swiftformat doesn't want changes**

Run:
```bash
swiftformat --lint .
```

Expected: `0/N files would have been formatted` (exit 0). If files would be reformatted, run `swiftformat .` to apply the changes, re-verify with `swiftformat --lint .`, then proceed.

If swiftformat isn't installed: `brew install swiftformat` then retry.

- [ ] **Step 6: Commit**

```bash
git add .gitignore .swiftlint.yml .swiftformat
git commit -m "chore: add SwiftLint, SwiftFormat, and gitignore configs"
```

---

## Task 3: Justfile

**Goal:** `just build`, `just test`, `just lint`, `just format` work from day 1. Tag-release recipes wired up. `example` recipe is omitted (no Xcode project yet).

**Files:**
- Create: `Justfile`

- [ ] **Step 1: Write `Justfile`** (adapted from ShortcutField — `example` recipe removed pending Phase 1)

Content:
```make
[private]
default:
    @just --list

build:
    @swift build -Xswiftc -warnings-as-errors

test:
    @swift test

lint *files:
    @swiftlint --strict {{ if files == "" { "." } else { files } }}

lint-fix *files:
    @swiftlint --fix {{ if files == "" { "." } else { files } }}

format *files:
    @swiftformat {{ if files == "" { "." } else { files } }}

clean:
    @rm -rf .build
    @echo "Build directory cleaned."

# Usage: just tag-release-patch, just tag-release-minor, just tag-release-major
tag-release-patch:
    @just tag-release patch

tag-release-minor:
    @just tag-release minor

tag-release-major:
    @just tag-release major

tag-release bump:
    #!/usr/bin/env bash
    set -euo pipefail
    LATEST_TAG=$(git tag --sort=-v:refname | head -1 | sed 's/^v//')
    if [ -z "$LATEST_TAG" ]; then
        VERSION="0.1.0"
        case "{{bump}}" in
            patch) VERSION="0.0.1" ;;
            minor) VERSION="0.1.0" ;;
            major) VERSION="1.0.0" ;;
        esac
    else
        MAJOR=$(echo "$LATEST_TAG" | cut -d. -f1)
        MINOR=$(echo "$LATEST_TAG" | cut -d. -f2)
        PATCH=$(echo "$LATEST_TAG" | cut -d. -f3)
        case "{{bump}}" in
            patch) PATCH=$((PATCH + 1)) ;;
            minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
            major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
            *) echo "Error: bump must be patch, minor, or major"; exit 1 ;;
        esac
        VERSION="$MAJOR.$MINOR.$PATCH"
    fi
    echo "Tagging v$VERSION..."
    git tag "v$VERSION" && git push origin main "v$VERSION" && \
    echo "Tagged and pushed v$VERSION"
```

- [ ] **Step 2: Verify `just --list` shows the recipes**

Run:
```bash
just --list
```

Expected output (order may vary):
```
Available recipes:
    build
    clean
    format *files
    lint *files
    lint-fix *files
    tag-release bump
    tag-release-major
    tag-release-minor
    tag-release-patch
    test
```

If `just` isn't installed: `brew install just` then retry.

- [ ] **Step 3: Verify `just build` succeeds**

Run:
```bash
just build
```

Expected: Same as `swift build -Xswiftc -warnings-as-errors`. Exit 0, `Build complete!`.

- [ ] **Step 4: Verify `just test` succeeds**

Run:
```bash
just test
```

Expected: All three placeholder tests pass.

- [ ] **Step 5: Verify `just lint` passes**

Run:
```bash
just lint
```

Expected: `Done linting! Found 0 violations`.

- [ ] **Step 6: Commit**

```bash
git add Justfile
git commit -m "chore: add Justfile with build/test/lint/format/tag recipes"
```

---

## Task 4: lefthook pre-commit/pre-push hooks

**Goal:** Git hooks installed. Pre-commit auto-formats and lints staged Swift files. Pre-push runs build (warnings-as-errors) and tests.

**Files:**
- Create: `lefthook.yml`

- [ ] **Step 1: Write `lefthook.yml`** (identical to ShortcutField's)

Content:
```yaml
pre-commit:
  commands:
    format:
      glob: "*.swift"
      run: swiftformat {staged_files} && git add {staged_files}
      stage_fixed: true
    lint:
      glob: "*.swift"
      run: swiftlint --strict {staged_files}

pre-push:
  commands:
    build:
      run: swift build -Xswiftc -warnings-as-errors
    test:
      run: swift test
```

- [ ] **Step 2: Install hooks**

Run:
```bash
lefthook install
```

Expected output: `sync hooks: ✔️ (pre-commit, pre-push)`.

If lefthook isn't installed: `brew install lefthook` then retry. (Verified available at `/opt/homebrew/bin/lefthook`.)

- [ ] **Step 3: Verify hooks file exists in `.git/hooks/`**

Run:
```bash
ls .git/hooks/pre-commit .git/hooks/pre-push
```

Expected: Both files exist (lefthook installs shims here).

- [ ] **Step 4: Sanity-check the pre-commit hook runs cleanly**

Run:
```bash
lefthook run pre-commit
```

Expected: `pre-commit ❯ all done in N ms` with both `format` and `lint` reporting no staged files to act on (since nothing is staged at this moment). Exit 0.

- [ ] **Step 5: Commit**

```bash
git add lefthook.yml
git commit -m "chore: add lefthook pre-commit and pre-push hooks"
```

Note: This commit itself goes through the pre-commit hook, which is a real end-to-end check that the hook is wired correctly. If `swiftformat` or `swiftlint` reports issues on `lefthook.yml`, that's a bug — `lefthook.yml` is YAML, not Swift, so the glob `*.swift` should skip it.

---

## Task 5: GitHub Actions CI workflow

**Goal:** `swift build`, `swift test`, and `swiftlint .` run on macOS-26 runners on every push and PR to `main`.

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Write `.github/workflows/ci.yml`** (identical to ShortcutField's)

Content:
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  build-and-test:
    runs-on: macos-26
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4

      - name: Build
        run: swift build

      - name: Test
        run: swift test

  lint:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4

      - name: Install SwiftLint
        run: brew install swiftlint

      - name: Lint
        run: swiftlint .
```

- [ ] **Step 2: Verify the workflow file is syntactically valid YAML**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"
```

Expected: No output (exit 0). Errors would print a yaml parse exception.

If `python3` isn't available or you prefer `yq`: `yq '.' .github/workflows/ci.yml > /dev/null` works equivalently.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add GitHub Actions workflow for build, test, and lint"
```

Note: When this commit is pushed, CI runs automatically on GitHub. Watch for the first run on the next push.

---

## Task 6: Swift Package Index config

**Goal:** When the repo is indexed by [Swift Package Index](https://swiftpackageindex.com), it builds DocC for all three targets.

**Files:**
- Create: `.spi.yml`

- [ ] **Step 1: Write `.spi.yml`**

Content (mirrors ShortcutField's structure, lists all three ShortcutKit targets):
```yaml
version: 1
builder:
  configs:
    - documentation_targets: ['ShortcutKit', 'ShortcutKitUI', 'ShortcutKitGlobal']
```

- [ ] **Step 2: Commit**

```bash
git add .spi.yml
git commit -m "chore: add Swift Package Index config with three doc targets"
```

---

## Task 7: User-facing docs (README, CHANGELOG, LICENSE)

**Goal:** Repo has a recognizable README skeleton, a CHANGELOG with an `[Unreleased]` section, and an MIT license.

**Files:**
- Create: `README.md`
- Create: `CHANGELOG.md`
- Create: `LICENSE`

- [ ] **Step 1: Write `README.md`** (skeleton — no pre-1.0 install instructions yet)

Content:
```markdown
# ShortcutKit

[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)](https://developer.apple.com/macos/)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](LICENSE)

VS Code–style keybindings for native macOS apps. Higher-level shortcut management built on top of [ShortcutField](https://github.com/nielsmadan/ShortcutField).

> ⚠️ **Pre-release.** ShortcutKit is under active development. Public API stabilizes at 1.0 alongside the documentation site at `shortcutkit.dev`. Track progress against the [phase plan](ShortcutKitDevelopment.md).

## Products

| Product | Purpose |
|---|---|
| `ShortcutKit` | Action registry, context activation, dispatch + notify, persistence, conflict detection. |
| `ShortcutKitUI` | Auto-generated settings view, legend, discoverability HUD. |
| `ShortcutKitGlobal` | System-wide (global) hotkeys integrated with the registry. |

## Installation

Swift Package Manager (once a pre-release tag exists):

\`\`\`swift
dependencies: [
    .package(url: "https://github.com/nielsmadan/ShortcutKit", from: "0.1.0")
]
\`\`\`

Per-target imports:

\`\`\`swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "ShortcutKit",       package: "ShortcutKit"),
        .product(name: "ShortcutKitUI",     package: "ShortcutKit"),
        .product(name: "ShortcutKitGlobal", package: "ShortcutKit"),
    ]
)
\`\`\`

## Status

Phase 1 (Core) — in design.

See [`ShortcutKitDevelopment.md`](ShortcutKitDevelopment.md) for the vision document and [`docs/superpowers/specs/`](docs/superpowers/specs/) for the package design meta-spec.

## License

[MIT](LICENSE).
```

Note: In the actual file, replace the escaped `\`\`\`` with real triple-backticks.

- [ ] **Step 2: Write `CHANGELOG.md`**

Content:
```markdown
# Changelog

All notable changes to ShortcutKit are documented here.

Entries are prefixed `[Core]`, `[UI]`, or `[Global]` so adopters can scan what affects them. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Package skeleton: three library products (`ShortcutKit`, `ShortcutKitUI`, `ShortcutKitGlobal`), test targets, DocC catalogs, repo tooling (SwiftLint, SwiftFormat, lefthook, Justfile, GitHub Actions CI), Swift Package Index config.
```

- [ ] **Step 3: Write `LICENSE`** (MIT, mirroring ShortcutField's style)

Content:
```
MIT License

Copyright (c) 2026 Niels Madan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md LICENSE
git commit -m "docs: add README skeleton, CHANGELOG, and MIT LICENSE"
```

---

## Task 8: AI-agent docs (CLAUDE.md, AGENTS.md)

**Goal:** Project guidance for AI coding agents — build commands, architecture, code style. Mirrors ShortcutField's pattern.

**Files:**
- Create: `CLAUDE.md`
- Create: `AGENTS.md`

- [ ] **Step 1: Write `CLAUDE.md`** (adapted from ShortcutField's pattern)

Content:
```markdown
# CLAUDE.md

## Build & Run

\`\`\`bash
just build    # Build the package
just test     # Run tests
just lint     # Run SwiftLint
just format   # Run SwiftFormat
just lint-fix # Auto-fix SwiftLint violations
just clean    # Remove build directory
just tag-release-patch  # Tag and push a patch release
just tag-release-minor  # Tag and push a minor release
\`\`\`

`just example` is omitted until the Phase 1 Xcode example app is added.

## Architecture

ShortcutKit is a Swift package providing higher-level shortcut management for macOS apps, built on top of [ShortcutField](https://github.com/nielsmadan/ShortcutField). Three library products:

- **`ShortcutKit` (Core)** — Action registry, context activation, dispatch + notify, persistence with append-only migrations, conflict detection, lookup API (`shortcut(for:)`, `displayString(for:)`, `isCustomized(_:)`, `bindingChanges(for:)`), menu helpers. Re-exports ShortcutField's `Shortcut` and related types via `@_exported import`.
- **`ShortcutKitUI`** — Auto-generated settings view (`KeyBindingsView`), legend (`KeyBindingsLegendView`), and discoverability HUD (`ShortcutHintHUD`).
- **`ShortcutKitGlobal`** — System-wide hotkeys via Carbon `RegisterEventHotKey`; no external dependency on `KeyboardShortcuts`.

## Phase status

| Phase | Target | Status |
|---|---|---|
| Phase 1 | `ShortcutKit` (Core) | Not started |
| Phase 2 | `ShortcutKitUI` | Not started |
| Phase 3 | `ShortcutKitGlobal` | Not started |
| Phase 4 | `shortcutkit.dev` docs site | Not started |

Vision doc: [`ShortcutKitDevelopment.md`](ShortcutKitDevelopment.md).
Package design meta-spec: [`docs/superpowers/specs/2026-05-13-shortcutkit-package-design.md`](docs/superpowers/specs/2026-05-13-shortcutkit-package-design.md).

## Code Style

- SwiftLint (`--strict`) and SwiftFormat configured.
- 4-space indentation, 120 char max width.
- Swift Testing framework (`@Test`, `#expect`).
- Swift 6.2 language mode (strict concurrency — all public types must be `Sendable`).
- macOS 13+ minimum deployment target.
- Pre-commit hook (via `lefthook`) auto-formats and lints staged Swift files; pre-push runs `swift build -Xswiftc -warnings-as-errors` and `swift test`.

## Cross-phase invariants

All 12 invariants in §7 of the package design spec are load-bearing. The high-impact ones for day-to-day work:

1. **Stable persistence IDs** — action raw values and context IDs persist forever; renames go through declared migrations.
2. **Headless-first** — every UI affordance has a `Sendable` data type in Core, with the SwiftUI view layered in UI.
3. **Append-only migrations** — adopter appends to the migration list; library tracks `migrationsApplied: N` in persistence.
4. **ShortcutField is canonical** — never redefine `Shortcut` / `Step` / `Kind`.
5. **Public symbol minimalism** — default `internal`; promote to `public` only when adopters need it.
```

Note: Replace escaped `\`\`\`` with real triple-backticks in the file.

- [ ] **Step 2: Write `AGENTS.md`** (mirrors ShortcutField's style — repository-guidelines format)

Content:
```markdown
# Repository Guidelines

## Project Structure & Module Organization

`ShortcutKit` is a Swift Package for macOS. Three library products live under `Sources/`:

- `Sources/ShortcutKit/` — Core: registry, dispatch, persistence, conflicts. Re-exports `ShortcutField`.
- `Sources/ShortcutKitUI/` — Auto-generated settings UI, legend, and discoverability HUD.
- `Sources/ShortcutKitGlobal/` — System-wide hotkeys via Carbon.

Tests mirror the source layout under `Tests/`. Each target has its own DocC catalog (`Sources/<Target>/<Target>.docc/`).

Specs and plans are tracked under `docs/superpowers/specs/` and `docs/superpowers/plans/`. The vision doc is `ShortcutKitDevelopment.md` at the repo root.

## Build, Test, and Development Commands

Use `just` for the common workflow:

- `just build` builds the Swift package with `swift build -Xswiftc -warnings-as-errors`.
- `just test` runs the full test suite with `swift test`.
- `just lint` checks style with SwiftLint (`--strict`).
- `just format` formats the repository with SwiftFormat.
- `just lint-fix` applies SwiftLint auto-corrections before submitting.

`pre-commit` (via `lefthook`) auto-runs `swiftformat` + `swiftlint --strict` on staged Swift files; `pre-push` runs `swift build` + `swift test`. Install hooks with `lefthook install` on a fresh checkout.

## Coding Style & Naming Conventions

This package targets Swift 6.2 and macOS 13+. Follow the existing style: 4-space indentation, 120-character line width, and `Sendable`-safe code for new types. UpperCamelCase for types (`ShortcutContext`), lowerCamelCase for properties and methods (`displayString`), and keep file names aligned with the primary type or extension they contain (`Shortcut+Matching.swift`-style extension files).

## Testing Guidelines

Tests use Swift Testing (`@Test`, `#expect`). Test files live in the target's matching `Tests/<Target>Tests/` directory. Cross-target integration tests live in the consuming target's test suite (e.g., UI ↔ Core integration goes in `ShortcutKitUITests/`, not `ShortcutKitTests/`).

When adding a DocC code example longer than 3 lines, add a matching test named `test_DocExample_<topicSlug>` in the target's test suite — keeps documentation from silently drifting from the API.

## Phase-aware work

Implementation proceeds in 4 sequential phases (see `ShortcutKitDevelopment.md` and the package design spec). Each phase has its own brainstorm → spec → plan → execute cycle. Avoid pulling work from a later phase into an earlier one without revisiting the phase boundaries.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md AGENTS.md
git commit -m "docs: add CLAUDE.md and AGENTS.md project guidance"
```

---

## Task 9: DocC catalogs

**Goal:** Each of the three targets has a DocC catalog containing a stub landing article. Xcode and Swift Package Index can render the docs from day 1.

**Files:**
- Create: `Sources/ShortcutKit/ShortcutKit.docc/ShortcutKit.md`
- Create: `Sources/ShortcutKitUI/ShortcutKitUI.docc/ShortcutKitUI.md`
- Create: `Sources/ShortcutKitGlobal/ShortcutKitGlobal.docc/ShortcutKitGlobal.md`

- [ ] **Step 1: Create the Core DocC landing article**

Path: `Sources/ShortcutKit/ShortcutKit.docc/ShortcutKit.md`
Content:
```markdown
# ``ShortcutKit``

Action registry, context activation, dispatch, and persistence for macOS apps.

## Overview

ShortcutKit lets you declare shortcut **actions** as Swift enums, group them into **contexts**, and bind callbacks declaratively. The registry handles user customization persistence, conflict detection, and exposes a read API for showing the currently-effective binding in menus and other UI.

This module also re-exports [ShortcutField](https://github.com/nielsmadan/ShortcutField) — `Shortcut`, `Shortcut.Step`, `ContinuousShortcut`, and related types are available with a single `import ShortcutKit`.

> Public API arrives in Phase 1. See the [package design spec](https://github.com/nielsmadan/ShortcutKit/blob/main/docs/superpowers/specs/2026-05-13-shortcutkit-package-design.md) for the current state.

## Topics

### Phase 1 — Coming soon

- Action declaration (the `ShortcutAction` protocol)
- Context registration and activation
- Dispatch and notify
- Persistence and append-only migrations
- Within-context and cross-context conflict detection
- Lookup API: `shortcut(for:)`, `displayString(for:)`, `isCustomized(_:)`, `bindingChanges(for:)`
- Menu helpers: `NSMenuItem` and SwiftUI `KeyEquivalent` bridges
```

- [ ] **Step 2: Create the UI DocC landing article**

Path: `Sources/ShortcutKitUI/ShortcutKitUI.docc/ShortcutKitUI.md`
Content:
```markdown
# ``ShortcutKitUI``

Auto-generated settings view, legend, and discoverability HUD for ShortcutKit-driven apps.

## Overview

ShortcutKitUI provides the default SwiftUI rendering of the headless data types defined in ShortcutKit. Adopters who want bespoke visuals can consume the same data types from ShortcutKit and skip this module entirely.

> Public API arrives in Phase 2. See the [package design spec](https://github.com/nielsmadan/ShortcutKit/blob/main/docs/superpowers/specs/2026-05-13-shortcutkit-package-design.md) for the current state.

## Topics

### Phase 2 — Coming soon

- `KeyBindingsView` — rendered settings table
- `KeyBindingsLegendView` — rendered shortcut cheatsheet
- `ShortcutHintHUD` — discoverability overlay
- View modifiers for style customization
```

- [ ] **Step 3: Create the Global DocC landing article**

Path: `Sources/ShortcutKitGlobal/ShortcutKitGlobal.docc/ShortcutKitGlobal.md`
Content:
```markdown
# ``ShortcutKitGlobal``

System-wide (global) hotkeys integrated with the ShortcutKit action registry.

## Overview

ShortcutKitGlobal reimplements global hotkey support on top of Carbon's `RegisterEventHotKey` and `NSEvent` monitors, without depending on third-party libraries. Each action in the registry can have a global binding in addition to its in-app binding.

> Public API arrives in Phase 3. See the [package design spec](https://github.com/nielsmadan/ShortcutKit/blob/main/docs/superpowers/specs/2026-05-13-shortcutkit-package-design.md) for the current state.

## Topics

### Phase 3 — Coming soon

- Global hotkey registration
- Permission/accessibility prompt flow
- Coexistence rules with in-app bindings
```

- [ ] **Step 4: Verify `swift build` still succeeds with the catalogs in place**

Run:
```bash
swift build
```

Expected: Build succeeds. (SwiftPM picks up `.docc` directories automatically as documentation bundles.)

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortcutKit/ShortcutKit.docc/ \
        Sources/ShortcutKitUI/ShortcutKitUI.docc/ \
        Sources/ShortcutKitGlobal/ShortcutKitGlobal.docc/
git commit -m "docs: add DocC catalog stubs for all three targets"
```

---

## Task 10: Example directory placeholder

**Goal:** `Example/` directory exists with a README explaining that the Xcode project ships with Phase 1.

**Files:**
- Create: `Example/README.md`

- [ ] **Step 1: Write `Example/README.md`**

Content:
```markdown
# ShortcutKitExample

This directory will hold the `ShortcutKitExample.xcodeproj` — a single Xcode macOS app that demos each ShortcutKit target via tabs (Core, Settings UI, Legend, HUD, Global).

The Xcode project is deferred until Phase 1 ships, since there's no API to demo yet. Phase 1's implementation plan adds the project as its first task.

Once present, `just example` from the repo root will build and run the app.
```

- [ ] **Step 2: Commit**

```bash
git add Example/README.md
git commit -m "docs: add Example/ directory placeholder pending Phase 1"
```

---

## Task 11: Final verification

**Goal:** Confirm the skeleton is in a clean, releasable state. All hooks pass, all CI checks would pass.

- [ ] **Step 1: Verify clean working tree**

Run:
```bash
git status
```

Expected: `nothing to commit, working tree clean`.

- [ ] **Step 2: Run the full build + test + lint suite**

Run:
```bash
just build && just test && just lint
```

Expected: All three succeed with exit 0. Final output ends with `Done linting! Found 0 violations, 0 serious in N files`.

- [ ] **Step 3: Verify swiftformat sees no pending changes**

Run:
```bash
swiftformat --lint .
```

Expected: `0/N files would have been formatted`.

- [ ] **Step 4: Verify lefthook hooks still installed**

Run:
```bash
ls .git/hooks/pre-commit .git/hooks/pre-push && lefthook run pre-commit
```

Expected: Both files exist; `lefthook run pre-commit` exits 0.

- [ ] **Step 5: Inspect final commit log**

Run:
```bash
git log --oneline
```

Expected: Approximately the following commit sequence (in addition to any prior `initial commit`):
```
chore: <task 11 verification — no commit, just sanity>
docs: add Example/ directory placeholder pending Phase 1
docs: add DocC catalog stubs for all three targets
docs: add CLAUDE.md and AGENTS.md project guidance
docs: add README skeleton, CHANGELOG, and MIT LICENSE
chore: add Swift Package Index config with three doc targets
ci: add GitHub Actions workflow for build, test, and lint
chore: add lefthook pre-commit and pre-push hooks
chore: add Justfile with build/test/lint/format/tag recipes
chore: add SwiftLint, SwiftFormat, and gitignore configs
feat: package skeleton with three targets and ShortcutField re-export
initial commit
```

- [ ] **Step 6: Update CHANGELOG with the now-completed skeleton work** (optional polish)

If desired, refine the `[Unreleased]` entry in `CHANGELOG.md` to reflect the actual state. No new commit required if the wording in Task 7 already covers it.

- [ ] **Step 7: Confirm spec deviation is documented**

The plan deviates from spec §1.1 / §11 in deferring the `Example/ShortcutKitExample.xcodeproj` creation to Phase 1. This deviation is captured at the top of this plan and in `Example/README.md`. No action needed; this step is a checkpoint.

---

## Done

After Task 11, ShortcutKit is a buildable, lint-clean, test-passing, CI-ready Swift package with:
- 3 library products + 3 test targets compiling against ShortcutField 2.0.0+.
- All static analysis tooling (SwiftLint, SwiftFormat, lefthook, GitHub Actions CI) active from the first commit.
- DocC catalogs for all three targets with stub landing articles.
- README, CHANGELOG, LICENSE, CLAUDE.md, AGENTS.md filled in.
- Swift Package Index config wired up.

Phase 1 (Core) can now start with its own brainstorm → spec → plan → execute cycle on a clean foundation.
