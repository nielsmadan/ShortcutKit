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

# Build DocC docs for all three libraries and fail on any diagnostic (e.g. unresolved
# symbol links). `xcodebuild docbuild` exits 0 even on warnings, so inspect the
# diagnostics file each module writes. Dependency modules build too; only ours are gated.
build-docs:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf .build/docc
    for scheme in ShortcutKit ShortcutKitUI ShortcutKitGlobal; do
        xcodebuild docbuild -scheme "$scheme" -destination 'platform=macOS' -derivedDataPath .build/docc
    done
    total=0
    for scheme in ShortcutKit ShortcutKitUI ShortcutKitGlobal; do
        diag=$(find .build/docc -name "$scheme-diagnostics.json" | head -1)
        if [ -z "$diag" ]; then
            echo "error: no DocC diagnostics file for $scheme — docc did not run" >&2
            exit 1
        fi
        count=$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['diagnostics']))" "$diag")
        if [ "$count" -ne 0 ]; then
            echo "$scheme:" >&2
            python3 -c "import json,sys; [print('  -', x.get('summary','')) for x in json.load(open(sys.argv[1]))['diagnostics']]" "$diag" >&2
        fi
        total=$((total + count))
    done
    if [ "$total" -ne 0 ]; then
        echo "error: DocC reported $total diagnostic(s)." >&2
        exit 1
    fi
    echo "DocC: no diagnostics."

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
    @curtains "$@"
