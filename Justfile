[private]
default:
    @just --list

# Prepare this checkout for work: dependencies, hooks, then verify.
setup:
    @swift package resolve
    @lefthook install
    @just doctor

# Verify the tools and checkout state this repo needs.
doctor:
    #!/usr/bin/env bash
    set -uo pipefail
    fail=0
    need() {
        if command -v "$1" >/dev/null 2>&1; then
            printf '  ok       %s\n' "$1"
        else
            printf '  MISSING  %-12s install: %s\n' "$1" "$2"; fail=1
        fi
    }
    need python3 "brew install python"
    need swift "xcode-select --install"
    need swiftformat "brew install swiftformat"
    need swiftlint "brew install swiftlint"
    need xcodebuild "install Xcode from the App Store"
    need lefthook "brew install lefthook"
    if [ -f "$(git rev-parse --git-path hooks/pre-commit)" ]; then
        printf '  ok       git hooks\n'
    else
        printf '  MISSING  %-12s run: just setup\n' 'git hooks'; fail=1
    fi
    [ "$fail" -eq 0 ] && printf 'Everything in place.\n'
    exit $fail

build:
    @swift build -Xswiftc -warnings-as-errors

test:
    @swift test

# Format check, lint, strict build and tests. The pre-push gate.
check:
    @python3 -B -m unittest discover -s scripts -p 'test_release*.py'
    @swiftformat --lint .
    @swiftlint --strict .
    @swift build -Xswiftc -warnings-as-errors
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

example:
    @xcodebuild -project Example/ShortcutKitExample.xcodeproj \
        -scheme ShortcutKitExample -configuration Debug \
        -derivedDataPath .build/Example build
    @open -n .build/Example/Build/Products/Debug/ShortcutKitExample.app

# Clear all persisted shortcut overrides for the example app so it starts
# fresh on the next launch. Useful after experimenting with re-bindings in
# Settings → Shortcuts.
reset-example:
    @defaults delete com.nielsmadan.shortcutkit.ShortcutKitExample shortcutkit.overrides 2>/dev/null \
        && echo "Cleared shortcutkit.overrides for ShortcutKitExample." \
        || echo "No overrides to clear (or app preferences not yet written)."

[positional-arguments]
release *args:
    python3 scripts/release.py "$@"
