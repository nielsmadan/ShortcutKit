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

example:
    @xcodebuild -project Example/ShortcutKitExample.xcodeproj \
        -scheme ShortcutKitExample -configuration Debug \
        -derivedDataPath .build/Example build
    @.build/Example/Build/Products/Debug/ShortcutKitExample.app/Contents/MacOS/ShortcutKitExample

# Clear all persisted shortcut overrides for the example app so it starts
# fresh on the next launch. Useful after experimenting with re-bindings in
# Settings → Shortcuts.
reset-example:
    @defaults delete com.nielsmadan.shortcutkit.ShortcutKitExample shortcutkit.overrides 2>/dev/null \
        && echo "Cleared shortcutkit.overrides for ShortcutKitExample." \
        || echo "No overrides to clear (or app preferences not yet written)."

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
    LATEST_TAG=$(git tag --list 'v*' --sort=-v:refname | head -1 | sed 's/^v//')
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
