# 0006 — Legend appearance is a constrained value-type API

Date: 2026-08-30 · Status: Accepted

## Context

Consumers wanted to brand the legend's typography and colours. The three obvious
shapes each fail, and they fail for different reasons:

- A SwiftUI `Style` protocol hands composition to the adopter. The legend's
  fixed-width column alignment is the thing it exists to guarantee.
- Accepting a SwiftUI `Font` is one-way. `Font` is opaque and cannot be converted
  back to `NSFont`, and the tooltip truncation check has to measure in `NSFont`.
- Accepting an `NSFont` or `NSFontDescriptor` does not compile into
  `LegendOptions`, whose public types are required to stay `Sendable` under
  Swift 6.

## Decision

Expose `LegendAppearance` through `LegendOptions`, with independent `labelFont`,
`shortcutFont`, `headerFont`, `shortcutColor`, `labelColor` and `headerColor`
slots, each defaulting to the built-in appearance.

Model a font as `LegendFont` — a `Sendable`, `Hashable` value type carrying a
`face` and an optional `size`, with weight carried on the face rather than
alongside it. It resolves internally to `NSFont` for measurement and then to
SwiftUI `Font` for rendering, so both stages see one resolved face. `size` stays
optional so ``LegendSize`` keeps driving S/M/L/XL scaling for consumers who only
want to change the typeface.

Default the shortcut slot to Menlo: it separates `I`/`l` and `0`/`O`, and it
carries native glyphs for the legend's modifier symbols, so no per-glyph fallback
breaks monospace alignment.

Keep the hierarchical defaults as `AnyShapeStyle` so `.primary` and `.secondary`
retain material vibrancy; a consumer's explicit colour may be a concrete style.

## Consequences

Apps that need control over composition are pointed at the Core API's shortcut
data to build their own legend. That is the supported escape hatch — not a wider
`LegendOptions`.

Measurement and rendering must keep sharing one resolved `NSFont`. Reconstructing
a font at the measurement site from a "is monospace" flag is what previously made
truncation detection disagree with the visible text.

Named-face fallback is role-specific. A missing shortcut face falls back to a
monospace system font rather than the proportional system font, or the column
alignment this API protects is lost.

Section headers stay dimmer than labels. Applying the label colour to headers
flattens the visual hierarchy the legend depends on.
