# Workbench visual assets

`morphir-logo.svg` is the FINOS Morphir vector logo, copied unchanged from
[2020_Morphir_Logo_Horizontal.svg](https://github.com/finos/morphir/blob/main/docs/assets/2020_Morphir_Logo_Horizontal.svg).
`morphir-mark.svg` crops its cube mark into a compact viewBox. The crop retains
the source geometry and original colors, blue `#16a2dc` and orange `#f26a21`.
The upstream repository distributes its source under Apache-2.0. Morphir's name
and logo remain FINOS Morphir brand assets.

`icon-model.svg`, `icon-code.svg`, `icon-sidebar.svg`, `icon-back.svg`, `icon-workspace.svg`,
`icon-folder.svg`, `icon-document.svg`, `icon-download.svg`, `icon-expand.svg`, `icon-restore.svg` and `icon-chevron.svg`
are original workbench drawings under this repository's license. They are
functional icons, not official Morphir brand marks. CSS masks let navigation
icons inherit the control's text color; labels provide their accessible names.
The workspace icon marks workspaces in the header picker. `icon-home.svg`, `icon-idea.svg`, `icon-plus.svg`,
`icon-explorer.svg`, `icon-sidebar-right.svg`, `icon-move.svg` and `icon-concept.svg` are original drawings under the
same terms, for the rail, getting started, sidebars and drafts.

The project explorer and command palette icons are original workbench drawings under the same terms:
`icon-file-new.svg`, `icon-import.svg`, `icon-collapse-all.svg`, `icon-more.svg`, `icon-folder-open.svg`,
`icon-exposed.svg`, `icon-command.svg` and `icon-choice.svg`. The file-type icons `icon-lang-elm.svg` (a tangram
square), `icon-lang-moonbit.svg` (a crescent), `icon-lang-scheme.svg` (a lambda) and `icon-lang-json.svg` (braces)
are simple line drawings, not the languages' official logos.

The rail's settings and theme icons are original drawings under the same terms: `icon-settings.svg` (a gear) and
`icon-theme-system.svg` (a monitor), `icon-theme-light.svg` (a sun) and `icon-theme-dark.svg` (a moon), which repeat
the shapes of the Morphir site's theme toggle.

UI colors follow the computed theme of [morphir.finos.org](https://morphir.finos.org/),
checked on 01 October 2026. Its final CSS override specifies primary `#00a3e2`,
primary darkest `#00729e`, secondary `#ff6a00` and secondary dark `#e65f00`.
The logo's source colors are preserved independently of the UI theme tokens.
All SVGs are packaged locally and require no network access at runtime.
