# Refactor

The `substrate refactor` command group provides safe, automated refactoring of
specification files and sections. Every reference in the project is updated
automatically to reflect the change.

## `rename`

```
substrate refactor rename <from> <to>
```

Renames a file or section, or moves a section between files.

### Arguments

| Argument | Description                                                                               |
| -------- | ----------------------------------------------------------------------------------------- |
| `<from>` | Source reference: `file.md` (file) or `file.md#section-anchor` (section)                 |
| `<to>`   | Destination reference: `file.md` (file) or `file.md#section-anchor` (section or parent)  |

### Operations

The operation is determined by the shape of the arguments:

**File rename** — `from` and `to` are both plain file paths:

```
substrate refactor rename specs/old-name.md specs/new-name.md
```

Renames the file on disk and rewrites every link that resolved to the old
path.

**Section rename** — `from` and `to` reference the same file but different anchors:

```
substrate refactor rename specs/foo.md#old-section specs/foo.md#new-section
```

Finds the heading whose GFM anchor is `old-section`, changes its text to a
value that produces the anchor `new-section`, then rewrites every same-file and
cross-file reference to the old anchor.

The new heading text is derived from the anchor slug: hyphens become spaces and
the first word is capitalised. For example, `my-new-section` becomes
`My new section`.

**Section move** — `from` contains a section anchor and `to` is a different file:

```
substrate refactor rename specs/a.md#my-section specs/b.md
substrate refactor rename specs/a.md#my-section specs/b.md#parent-section
substrate refactor rename specs/a.md#my-section specs/b.md root
```

Removes the section (and all its sub-sections) from the source file and
appends it in the target file. Every reference in the project that pointed to
any of the moved anchors is rewritten to point to the target file.

The insertion point is resolved from the `<to>` argument:

- With an anchor (`specs/b.md#parent-section`) — inserts after that section's subtree.
- Without an anchor (`specs/b.md`) — shows an interactive prompt to choose the position.

Sections are always **appended below** the chosen position; heading depth is not adjusted.

### Anchor collision check

When moving a section, the tool checks whether any anchor in the moved subtree
already exists in the target file. If a collision is found the command errors
before making any changes:

```
Error: Section "#my-section" already exists in specs/b.md.
Rename the conflicting section first before moving.
```

### Interactive prompt

When no insertion point is specified the tool shows the target file's heading
hierarchy and lets you pick a section with the arrow keys:

```
Select section to append below in specs/b.md (↑↓ to move, Enter to confirm):

▶ (root — append at end of file)
  # Introduction
    ## Prerequisites
  # Getting Started
    ## Installation
```

Press **Enter** to confirm, **Ctrl+C** or **Esc** to cancel.

If stdin is not a TTY (piped input, CI), the prompt cannot be shown — include
the parent anchor directly in the `<to>` argument instead.


# TODO

- Add split/merge commands to break up a large document into smaller ones using the document include feature or merge a directory into a single document.
