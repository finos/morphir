---
title: Design system
description: Colors, typography, spacing, and brand usage for Morphir Substrate.
breadcrumb: ["Brand", "Design system"]
---

Substrate's full design system reference lives in the [`branding/` folder](https://github.com/AttilaMihaly/morphir-substrate/tree/main/branding). The canonical source of truth is [`branding/design-system.md`](https://github.com/AttilaMihaly/morphir-substrate/blob/main/branding/design-system.md).

## At a glance

| Token            | Value      | Role                              |
| ---------------- | ---------- | --------------------------------- |
| Brand blue       | `#16A2DC`  | Primary signal — logo, links.     |
| Brand orange     | `#F26A21`  | Secondary signal — accents.       |
| Deep Slate       | `#2C4A5A`  | Tertiary — ink, chrome, surfaces. |

### Why Deep Slate

The two brand signals (orange and blue) are a complementary pair and already do the visual work. The third color is a **neutral ink**, not a third accent. Deep Slate `#2C4A5A`:

- sits in the same hue family as the brand blue (≈204°) so it reads as part of the palette,
- is desaturated (~35%) and dark (~26% lightness) so it recedes to a neutral, and
- replaces the earlier pine green `#2F4738`, whose green cast muddled the orange signal.

## Logo

The mark's geometric bounding box is centered on its own origin — any container that centers the SVG visually centers the mark. In horizontal lockups (mark + "substrate" wordmark), the wordmark's cap-height midline aligns to the mark's vertical center.

See [`branding/logo.svg`](https://github.com/AttilaMihaly/morphir-substrate/blob/main/branding/logo.svg) and [`branding/wordmark.svg`](https://github.com/AttilaMihaly/morphir-substrate/blob/main/branding/wordmark.svg).

## Typography

- **Display:** Fraunces (serif, weight 500) — section headings and hero.
- **UI / body:** Inter.
- **Code:** JetBrains Mono.

## Spacing

4-pt base scale, `--s-1` (4px) through `--s-24` (96px).

## Background lattice

Substrate uses a triangular (A₂) lattice as its signature background texture. Geometry and rendering parameters are in [`branding/style.md`](https://github.com/AttilaMihaly/morphir-substrate/blob/main/branding/style.md).
