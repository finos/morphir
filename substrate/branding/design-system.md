# Morphir Substrate Design System

This is the canonical design system for Morphir Substrate. It is the source of truth for the docs site, the spec editor, and any other surface that needs to look and feel like Substrate.

For geometric construction details (lattice math, logo coordinates), see [`style.md`](./style.md). This document focuses on tokens, usage, and rationale.

---

## Brand palette

Substrate uses a three-color brand palette: two bright signal colors inherited from the Morphir / FINOS family, plus one deep neutral used for type and UI chrome.

| Token              | Role                         | Hex        | Notes                                                       |
| ------------------ | ---------------------------- | ---------- | ----------------------------------------------------------- |
| `--brand-blue`     | Primary signal               | `#16A2DC`  | Logo stroke. Links, primary actions, focus rings.           |
| `--brand-orange`   | Secondary signal             | `#F26A21`  | Logo stroke. Accents, highlights, callouts.                 |
| `--brand-slate`    | Tertiary (ink / neutral)     | `#2C4A5A`  | Body text, headings, UI chrome, dark surfaces.              |

### Why Deep Slate `#2C4A5A` as the third color

The brand signals are a complementary pair — orange (≈20°) and cyan-blue (≈197°) sit almost opposite on the color wheel, which makes them loud together. A saturated third hue would fight them. Deep Slate is chosen for three reasons:

1. **Analogous to the brand blue, but muted.** `#2C4A5A` sits near hue 204°, within a few degrees of `#16A2DC`, so it reads as part of the same family. But its saturation is ~35% (vs. 82% for the brand blue) and its lightness is ~26% (vs. ~48%), so it recedes to a neutral.
2. **It stays out of the way.** Because it is desaturated and dark, it reads as "ink" rather than as a third accent, which keeps the orange ↔ blue brand signals doing the visual work.
3. **It replaces a pine green.** The earlier tertiary was `#2F4738` (pine). The green cast clashed with the orange signal (orange + green = muddy). A cool slate keeps the palette in the blue–orange complementary axis and feels crisper.

Alternatives considered: navy (too blue, competes with the brand blue), teal (too close to brand blue in hue and saturation), graphite (too neutral, loses warmth).

### Supporting neutrals and surfaces

| Token              | Value                              | Use                                           |
| ------------------ | ---------------------------------- | --------------------------------------------- |
| `--surface-1`      | `#F7F9FB`                          | Page background (light mode).                 |
| `--surface-2`      | `#EEF2F6`                          | Cards, elevated panels.                       |
| `--surface-inverse`| `#1A2A34`                          | Dark-mode page background (slate, deepened).  |
| `--ink`            | `#2C4A5A`                          | Default text on light surfaces.               |
| `--ink-muted`      | `rgba(44, 74, 90, 0.70)`           | Secondary text, captions.                     |
| `--ink-subtle`     | `rgba(44, 74, 90, 0.45)`           | Tertiary text, placeholders.                  |
| `--rule`           | `rgba(44, 74, 90, 0.14)`           | Hairlines, dividers, input borders.           |

### Functional tints

Derived from the tertiary, used sparingly.

| Token              | Value                              | Use                                           |
| ------------------ | ---------------------------------- | --------------------------------------------- |
| `--link`           | `#16A2DC`                          | Links on light surfaces.                      |
| `--link-hover`     | `#0E87B8`                          | Hover / active link.                          |
| `--accent`         | `#F26A21`                          | Highlights, badges, focus accents.            |
| `--accent-hover`   | `#D9571A`                          | Hover state on orange accents.                |

---

## Typography

Substrate is an **LLM-native executable specification language** — the product is text. Type choices favor long-form reading and code legibility.

| Role        | Family                                                                                   | Notes                                                |
| ----------- | ---------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| UI / body   | `"Inter", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`                      | Primary UI and prose font.                           |
| Display     | Same as body, heavier weights (600–700)                                                  | No separate display face — one family, many weights. |
| Mono / code | `"JetBrains Mono", "Fira Code", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace`| Code blocks, spec editor.                            |

### Type scale (1.250 – major third)

| Token         | Size      | Line-height | Use                         |
| ------------- | --------- | ----------- | --------------------------- |
| `--step--1`   | `0.833rem`| `1.5`       | Captions, fine print.       |
| `--step-0`    | `1rem`    | `1.6`       | Body.                       |
| `--step-1`    | `1.25rem` | `1.5`       | Lead, subheads.             |
| `--step-2`    | `1.563rem`| `1.35`      | H3.                         |
| `--step-3`    | `1.953rem`| `1.25`      | H2.                         |
| `--step-4`    | `2.441rem`| `1.2`       | H1.                         |
| `--step-5`    | `3.052rem`| `1.1`       | Hero display.               |

---

## Spacing

8-pt base with a T-shirt scale.

| Token       | Value  |
| ----------- | ------ |
| `--space-1` | `4px`  |
| `--space-2` | `8px`  |
| `--space-3` | `12px` |
| `--space-4` | `16px` |
| `--space-5` | `24px` |
| `--space-6` | `32px` |
| `--space-7` | `48px` |
| `--space-8` | `64px` |
| `--space-9` | `96px` |

## Radii

| Token           | Value   | Use                  |
| --------------- | ------- | -------------------- |
| `--radius-sm`   | `4px`   | Inputs, small chips. |
| `--radius-md`   | `8px`   | Cards, buttons.      |
| `--radius-lg`   | `12px`  | Panels, modals.      |
| `--radius-pill` | `999px` | Pills, tags.         |

## Elevation

Elevation is kept minimal — rely on the rule color and surface shifts rather than drop shadows.

| Token           | Value                                         |
| --------------- | --------------------------------------------- |
| `--shadow-1`    | `0 1px 2px rgba(44, 74, 90, 0.06)`            |
| `--shadow-2`    | `0 4px 12px rgba(44, 74, 90, 0.08)`           |
| `--shadow-focus`| `0 0 0 3px rgba(22, 162, 220, 0.35)`          |

---

## Logo

The canonical mark is defined in [`style.md` § Logo](./style.md#logo) and rendered in [`logo.html`](./logo.html). See [`logo.svg`](./logo.svg) for the production asset, and [`wordmark.svg`](./wordmark.svg) for the horizontal lockup used in the docs site header.

### Alignment rules

- The mark's **geometric bounding box is centered on its own origin** in `logo.svg` (the polylines are shifted so the bbox midpoint is `(0, 0)`). Any container that centers the SVG will visually center the mark — no manual nudging required.
- In horizontal lockups, the wordmark **"substrate"** sits to the right of the mark with its **cap-height midline aligned to the mark's vertical center**. Use `display: flex; align-items: center;` with the wordmark rendered as SVG text with `dominant-baseline="central"` anchored at the mark's y-midpoint.
- Minimum clear space around the mark is `0.5 · s` on all sides (where `s` is the lattice spacing at the logo's render size).

### Wordmark

| Property        | Value                                            |
| --------------- | ------------------------------------------------ |
| Family          | `Inter`                                          |
| Weight          | `600` (Semibold)                                 |
| Tracking        | `-0.01em`                                        |
| Case            | lowercase "substrate"                            |
| Color           | `--brand-slate` (`#2C4A5A`) on light surfaces    |

---

## Background — triangular lattice

See [`style.md` § Triangular Lattice](./style.md#triangular-lattice-background-pattern) for geometry. Implementation notes for the docs site:

- The lattice is rendered as a tinted overlay at **8–12% opacity** on hero sections only; body pages use plain `--surface-1` to maximize reading comfort.
- Dot and line colors use the slate tertiary: `rgba(44, 74, 90, 0.50)` (dots) and `rgba(44, 74, 90, 0.25)` (lines).
- Spacing `s = 40px` on screen; `s = 24px` for dense hero compositions.

---

## Tokens file

All of the tokens above are exported as CSS custom properties in [`tokens.css`](./tokens.css). Consumers (docs site, spec editor) should `@import` that file and reference the variables — never hard-code hex values outside of `tokens.css`.
