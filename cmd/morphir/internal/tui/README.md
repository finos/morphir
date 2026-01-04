# Morphir TUI Framework

A reusable Terminal User Interface (TUI) framework for Morphir commands, built with [Bubble Tea](https://github.com/charmbracelet/bubbletea) and featuring vim-style keybindings.

## Overview

This framework provides a consistent, professional TUI experience across Morphir commands with:

- **Collapsible Sidebar**: Tree/list navigation with vim keybindings
- **Markdown Viewer**: Beautiful rendering with [Glamour](https://github.com/charmbracelet/glamour)
- **Status Bar**: Contextual information and keybinding hints
- **Vim-style Navigation**: Familiar j/k, gg/G, and search with /

## Architecture

```
cmd/morphir/internal/tui/
├── app.go              # Main application shell
├── layout.go           # Layout manager
├── components/
│   ├── sidebar.go      # Tree/list navigation
│   ├── viewer.go       # Markdown viewer
│   └── statusbar.go    # Status and help bar
├── styles/
│   └── theme.go        # Consistent styling
└── keymap/
    └── vim.go          # Vim keybindings
```

## Quick Start

### Basic Example

```go
package main

import (
    "github.com/finos/morphir/cmd/morphir/internal/tui"
    "github.com/finos/morphir/cmd/morphir/internal/tui/components"
)

func main() {
    // Create sidebar items
    items := []*components.SidebarItem{
        {ID: "1", Title: "Introduction"},
        {ID: "2", Title: "Documentation"},
    }

    // Create and run app
    app := tui.NewApp(
        tui.WithTitle("My App"),
        tui.WithSidebar(items),
        tui.WithViewer("# Welcome\n\nSelect an item from the sidebar."),
    )

    app.Run()
}
```

### With Selection Handler

```go
app := tui.NewApp(
    tui.WithTitle("Morphir Validator"),
    tui.WithSidebar(fileItems),
    tui.WithOnSelect(func(item *components.SidebarItem) error {
        content := loadFileContent(item.ID)
        app.SetViewerContent(content)
        app.SetViewerTitle(item.Title)
        return nil
    }),
)
```

## Components

### AppShell

The main application container that manages layout, focus, and global keybindings.

**Options:**
- `WithTitle(string)` - Set application title
- `WithSidebar([]*SidebarItem)` - Configure sidebar items
- `WithSidebarTitle(string)` - Set sidebar title
- `WithViewer(string)` - Set initial viewer content
- `WithViewerTitle(string)` - Set viewer title
- `WithOnSelect(func)` - Callback for item selection
- `WithOnQuit(func)` - Callback on quit

### Sidebar

Hierarchical navigation with tree/list modes.

**Features:**
- Tree view with expand/collapse
- Flat list mode
- Filtering/search
- Vim navigation (j/k, h/l)

**Example:**
```go
items := []*components.SidebarItem{
    {
        ID: "parent",
        Title: "Parent",
        Children: []*components.SidebarItem{
            {ID: "child1", Title: "Child 1"},
            {ID: "child2", Title: "Child 2"},
        },
    },
}

sidebar := components.NewSidebar("Menu", keymap.DefaultVimKeyMap())
sidebar.SetItems(items)
```

### Viewer

Markdown content viewer with glamour rendering.

**Features:**
- CommonMark markdown support
- Syntax highlighting for code blocks
- Vim navigation
- Search functionality (/)

**Example:**
```go
viewer := components.NewViewer("Content", keymap.DefaultVimKeyMap())
viewer.SetContent("# Hello\n\nThis is **markdown**!")
```

### StatusBar

Bottom status bar with mode, position, and hints.

**Features:**
- Mode indicator (SIDEBAR, VIEWER, SEARCH)
- Position tracking (line/total)
- Keybinding hints
- Custom messages

**Example:**
```go
statusBar := components.NewStatusBar(keymap.DefaultVimKeyMap())
statusBar.SetMode("VIEWER")
statusBar.SetPosition(10, 100)
```

## Keybindings

### Navigation
| Key | Action |
|-----|--------|
| j/k or ↑/↓ | Move up/down |
| h/l or ←/→ | Switch panels or collapse/expand |
| gg | Go to top |
| G | Go to bottom |
| Ctrl+d | Half page down |
| Ctrl+u | Half page up |
| PgUp/PgDn | Page up/down |

### Panels
| Key | Action |
|-----|--------|
| Tab | Next panel |
| Shift+Tab | Previous panel |
| b or Ctrl+b | Toggle sidebar |

### Search
| Key | Action |
|-----|--------|
| / | Start search |
| n | Next match |
| N | Previous match |
| Esc | Cancel search |

### View Options
| Key | Action |
|-----|--------|
| Ctrl+n | Toggle line numbers |
| :number | Go to line number |

### General
| Key | Action |
|-----|--------|
| ? | Show help |
| q or Ctrl+c | Quit |
| Enter | Select item |

## Styling

The framework uses a consistent theme defined in `styles/theme.go`:

```go
import "github.com/finos/morphir/cmd/morphir/internal/tui/styles"

// Use predefined styles
title := styles.TitleStyle.Render("My Title")
error := styles.ErrorStyle.Render("Error message")
success := styles.SuccessStyle.Render("Success!")

// Access theme colors
primaryColor := styles.DefaultTheme.Primary
```

## Demo Application

Run the demo to see all features in action:

```bash
cd cmd/morphir/examples
go run tui_demo.go
```

The demo showcases:
- Hierarchical navigation
- Dynamic content loading
- Markdown rendering
- All keybindings

## Usage in Morphir Commands

### Interactive Validate Command

```go
// In cmd/morphir/commands/validate.go
func runInteractiveValidation(results []ValidationResult) error {
    // Build sidebar from results
    items := buildSidebarFromResults(results)

    app := tui.NewApp(
        tui.WithTitle("Validation Results"),
        tui.WithSidebarTitle("Files"),
        tui.WithSidebar(items),
        tui.WithOnSelect(func(item *components.SidebarItem) error {
            content := formatValidationResult(item.Data)
            app.SetViewerContent(content)
            return nil
        }),
    )

    return app.Run()
}
```

### Main Morphir Command

```go
// In cmd/morphir/main.go
func runInteractiveMode() error {
    commands := []*components.SidebarItem{
        {ID: "validate", Title: "Validate"},
        {ID: "test", Title: "Test"},
        {ID: "build", Title: "Build"},
    }

    app := tui.NewApp(
        tui.WithTitle("Morphir"),
        tui.WithSidebarTitle("Commands"),
        tui.WithSidebar(commands),
    )

    return app.Run()
}
```

## Dependencies

- [github.com/charmbracelet/bubbletea](https://github.com/charmbracelet/bubbletea) - TUI framework
- [github.com/charmbracelet/bubbles](https://github.com/charmbracelet/bubbles) - TUI components
- [github.com/charmbracelet/lipgloss](https://github.com/charmbracelet/lipgloss) - Styling
- [github.com/charmbracelet/glamour](https://github.com/charmbracelet/glamour) - Markdown rendering

## Design Principles

1. **Vim-first**: All navigation follows vim conventions
2. **Reusable**: Components can be used independently
3. **Consistent**: Unified theme and keybindings across all commands
4. **Accessible**: Clear visual hierarchy and status feedback
5. **Functional**: Follows Morphir's functional programming principles

## Contributing

When extending the TUI framework:

1. Maintain vim-style keybindings
2. Use the theme from `styles/theme.go`
3. Follow the existing component patterns
4. Test with the demo application
5. Update this README with new features

## License

Copyright (c) 2024 FINOS - The Fintech Open Source Foundation

Licensed under the Apache License, Version 2.0
