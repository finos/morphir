package main

import (
	"fmt"
	"os"

	"github.com/finos/morphir/cmd/morphir/internal/tui"
	"github.com/finos/morphir/cmd/morphir/internal/tui/components"
)

func main() {
	// Create sample sidebar items
	items := []*components.SidebarItem{
		{
			ID:    "intro",
			Title: "Introduction",
			Data:  "intro",
		},
		{
			ID:    "features",
			Title: "Features",
			Children: []*components.SidebarItem{
				{
					ID:    "sidebar",
					Title: "Sidebar",
					Data:  "sidebar",
				},
				{
					ID:    "viewer",
					Title: "Viewer",
					Data:  "viewer",
				},
				{
					ID:    "statusbar",
					Title: "Status Bar",
					Data:  "statusbar",
				},
			},
		},
		{
			ID:    "keybindings",
			Title: "Keybindings",
			Data:  "keybindings",
		},
		{
			ID:    "examples",
			Title: "Examples",
			Children: []*components.SidebarItem{
				{
					ID:    "basic",
					Title: "Basic Usage",
					Data:  "basic",
				},
				{
					ID:    "advanced",
					Title: "Advanced",
					Data:  "advanced",
				},
			},
		},
	}

	// Create content map
	content := getContentMap()

	// Initial content
	initialContent := content["intro"]

	// Create the app
	var app *tui.App
	app = tui.NewApp(
		tui.WithTitle("Morphir TUI Demo"),
		tui.WithSidebarTitle("Navigation"),
		tui.WithSidebar(items),
		tui.WithViewerTitle("Content"),
		tui.WithViewer(initialContent),
		tui.WithOnSelect(func(item *components.SidebarItem) error {
			// Load content based on selected item
			if data, ok := item.Data.(string); ok {
				if newContent, exists := content[data]; exists {
					app.SetViewerContent(newContent)
					app.SetViewerTitle(item.Title)
				}
			}
			return nil
		}),
	)

	// Run the app
	if err := app.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error running TUI: %v\n", err)
		os.Exit(1)
	}
}

func getContentMap() map[string]string {
	return map[string]string{
		"intro": `# Morphir TUI Framework

Welcome to the Morphir TUI Framework demonstration!

This framework provides a reusable, vim-style terminal user interface for Morphir commands.

## What You're Looking At

- **Left Panel**: A collapsible sidebar with tree navigation
- **Right Panel**: A markdown viewer with glamour rendering
- **Bottom**: A status bar showing current mode and keybindings

Try navigating with **j/k** or arrow keys!
`,
		"sidebar": `# Sidebar Component

The sidebar provides hierarchical navigation with:

## Features

- **Tree View**: Expandable/collapsible items
- **List View**: Flat list mode
- **Filtering**: Search through items
- **Vim Navigation**: j/k for up/down, h/l for collapse/expand

## Usage

Press **l** to expand an item, **h** to collapse.
Press **Enter** to select an item.

The sidebar can be toggled with **b** or **Ctrl+b**.
`,
		"viewer": `# Viewer Component

The viewer displays beautiful markdown content using Glamour.

## Features

- **Markdown Rendering**: Full CommonMark support
- **Syntax Highlighting**: For code blocks
- **Vim Navigation**: Familiar keybindings
- **Search**: Press **/** to search

## Navigation Keys

- **j/k**: Scroll line by line
- **Ctrl+d/u**: Half page scrolling
- **gg**: Go to top
- **G**: Go to bottom
- **PgUp/PgDn**: Page scrolling

## Code Example

Here's a sample Go code:

` + "```go\n" + `func main() {
    app := tui.NewApp(
        tui.WithTitle("My App"),
        tui.WithSidebar(items),
    )
    app.Run()
}
` + "```\n",
		"statusbar": `# Status Bar Component

The status bar provides contextual information at the bottom of the screen.

## What It Shows

- **Mode**: Current mode (NORMAL, SEARCH, SIDEBAR, VIEWER)
- **Position**: Current line/total lines
- **Keybindings**: Context-sensitive help
- **Messages**: Status messages and errors

## Modes

- **NORMAL**: Default navigation mode
- **SEARCH**: When searching (**/**)
- **SIDEBAR**: When sidebar has focus
- **VIEWER**: When viewer has focus

The status bar automatically updates based on your current context.
`,
		"keybindings": `# Keybindings Reference

All keybindings follow vim-style conventions for familiarity.

## Navigation

| Key | Action |
|-----|--------|
| j/k | Move down/up |
| h/l | Switch panels or collapse/expand |
| gg | Go to top |
| G | Go to bottom |
| Ctrl+d | Half page down |
| Ctrl+u | Half page up |
| PgUp/PgDn | Page up/down |

## Panels

| Key | Action |
|-----|--------|
| Tab | Next panel |
| Shift+Tab | Previous panel |
| b or Ctrl+b | Toggle sidebar |

## Search

| Key | Action |
|-----|--------|
| / | Start search |
| n | Next match |
| N | Previous match |
| Esc | Cancel search |

## General

| Key | Action |
|-----|--------|
| ? | Show help |
| q or Ctrl+c | Quit |
| Enter | Select item |

## Tips

- Press **?** anytime to see the help screen
- Use **Tab** to switch between sidebar and viewer
- Try **/** to search within content
`,
		"basic": `# Basic Usage Example

Here's a simple example of using the TUI framework:

` + "```go\n" + `package main

import (
    "github.com/finos/morphir/cmd/morphir/internal/tui"
    "github.com/finos/morphir/cmd/morphir/internal/tui/components"
)

func main() {
    // Create sidebar items
    items := []*components.SidebarItem{
        {ID: "1", Title: "Item 1"},
        {ID: "2", Title: "Item 2"},
    }

    // Create app
    app := tui.NewApp(
        tui.WithTitle("My App"),
        tui.WithSidebar(items),
        tui.WithViewer("# Welcome\n\nSelect an item from the sidebar."),
    )

    // Run
    if err := app.Run(); err != nil {
        panic(err)
    }
}
` + "```\n" + `
This creates a simple TUI with a sidebar and viewer!
`,
		"advanced": `# Advanced Usage

## Custom Selection Handler

You can provide a callback for when items are selected:

` + "```go\n" + `app := tui.NewApp(
    tui.WithTitle("My App"),
    tui.WithSidebar(items),
    tui.WithOnSelect(func(item *components.SidebarItem) error {
        // Load content based on selection
        content := loadContent(item.ID)
        app.SetViewerContent(content)
        app.SetViewerTitle(item.Title)
        return nil
    }),
)
` + "```\n" + `
## Dynamic Content

You can update content dynamically:

` + "```go\n" + `// Update sidebar
app.SetSidebarItems(newItems)

// Update viewer
app.SetViewerContent("# New Content")
app.SetViewerTitle("New Title")
` + "```\n" + `
## Access Components

Get direct access to components for advanced control:

` + "```go\n" + `sidebar := app.GetSidebar()
viewer := app.GetViewer()
statusBar := app.GetStatusBar()

// Customize as needed
sidebar.SetFilter("search term")
viewer.SetShowLineNumbers(true)
statusBar.SetMode("CUSTOM")
` + "```\n" + `
## Tree Structures

Build complex hierarchical menus:

` + "```go\n" + `items := []*components.SidebarItem{
    {
        ID: "parent",
        Title: "Parent Item",
        Children: []*components.SidebarItem{
            {ID: "child1", Title: "Child 1"},
            {ID: "child2", Title: "Child 2"},
        },
    },
}
` + "```\n",
	}
}
