# Spec Editor · UI Kit

The Substrate **markdown-native debugger** and impact-analysis surface.
This is a hi-fi design proposal for the concepts in
`specs/vision.md` §11 (Live Data Binding) and §12 (Immediate Impact
Analysis). The specification document itself is the debugger interface:
table cells annotate with live values, rule conditions light up as they
are evaluated, and the active step is highlighted within the prose.

**What's mocked:**
- Reading pane rendering a user module (`order-total.md` as sample)
- Left rail: module tree + declared inputs
- Right rail: live value inspector + test-case runner
- Toolbar with Bind / Step / Replay actions
- Inline dataflow annotations (value chips beside table cells)
- Impact diff mode (shows old → new when a rule is edited)

**Fidelity:** cosmetic. No real evaluation; values are scripted.

**Files:**
- `index.html` — interactive click-through
- `SpecEditor.jsx` — shell, rails, toolbar
- `SpecDocument.jsx` — rendered markdown with live overlays
- `Inspector.jsx` — right-rail value / test inspector
- `ModuleTree.jsx` — left-rail navigation
