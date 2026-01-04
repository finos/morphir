package tui

import (
	"fmt"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/finos/morphir/cmd/morphir/internal/tui/components"
	"github.com/finos/morphir/cmd/morphir/internal/tui/keymap"
)

// FocusPanel represents which panel currently has focus
type FocusPanel int

const (
	FocusSidebar FocusPanel = iota
	FocusViewer
)

// App is the main TUI application shell
type App struct {
	keymap          keymap.VimKeyMap
	sidebar         *components.Sidebar
	viewer          *components.Viewer
	statusBar       *components.StatusBar
	layout          *Layout
	focus           FocusPanel
	title           string
	width           int
	height          int
	ready           bool
	quitting        bool
	showingHelp     bool
	previousContent string
	previousTitle   string

	// Callbacks
	onSelect func(item *components.SidebarItem) error
	onQuit   func()
}

// AppOption is a functional option for configuring the App
type AppOption func(*App)

// NewApp creates a new TUI application
func NewApp(opts ...AppOption) *App {
	km := keymap.DefaultVimKeyMap()

	app := &App{
		keymap:    km,
		sidebar:   components.NewSidebar("Menu", km),
		viewer:    components.NewViewer("Content", km),
		statusBar: components.NewStatusBar(km),
		layout:    NewLayout(),
		focus:     FocusSidebar,
		title:     "Morphir",
	}

	// Apply options
	for _, opt := range opts {
		opt(app)
	}

	return app
}

// WithTitle sets the application title
func WithTitle(title string) AppOption {
	return func(a *App) {
		a.title = title
	}
}

// WithSidebar configures the sidebar with items
func WithSidebar(items []*components.SidebarItem) AppOption {
	return func(a *App) {
		a.sidebar.SetItems(items)
	}
}

// WithSidebarTitle sets the sidebar title
func WithSidebarTitle(title string) AppOption {
	return func(a *App) {
		a.sidebar = components.NewSidebar(title, a.keymap)
	}
}

// WithViewer sets the initial viewer content
func WithViewer(content string) AppOption {
	return func(a *App) {
		a.viewer.SetContent(content)
	}
}

// WithViewerTitle sets the viewer title
func WithViewerTitle(title string) AppOption {
	return func(a *App) {
		a.viewer.SetTitle(title)
	}
}

// WithOnSelect sets a callback for when a sidebar item is selected
func WithOnSelect(fn func(item *components.SidebarItem) error) AppOption {
	return func(a *App) {
		a.onSelect = fn
	}
}

// WithOnQuit sets a callback for when the app quits
func WithOnQuit(fn func()) AppOption {
	return func(a *App) {
		a.onQuit = fn
	}
}

// Init implements tea.Model
func (a *App) Init() tea.Cmd {
	// Auto-select the first item if we have an onSelect callback and sidebar items
	if a.onSelect != nil {
		items := a.sidebar.GetItems()
		if len(items) > 0 {
			firstItem := findFirstSelectableItem(items)
			if firstItem != nil {
				_ = a.onSelect(firstItem)
			}
		}
	}
	return nil
}

// findFirstSelectableItem recursively finds the first selectable item
func findFirstSelectableItem(items []*components.SidebarItem) *components.SidebarItem {
	for _, item := range items {
		if len(item.Children) > 0 {
			// Try children first
			if child := findFirstSelectableItem(item.Children); child != nil {
				return child
			}
		} else {
			// This is a leaf item, return it
			return item
		}
	}
	return nil
}

// Update implements tea.Model
func (a *App) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		a.width = msg.Width
		a.height = msg.Height
		a.ready = true

		// Update layout
		a.layout.SetSize(a.width, a.height)
		dims := a.layout.CalculateDimensions()
		dims.ApplyToComponents(a.sidebar, a.viewer, a.statusBar)

		// Forward to components
		a.sidebar.Update(msg)
		a.viewer.Update(msg)
		a.statusBar.Update(msg)

		a.updateStatusBar()

	case tea.KeyMsg:
		// If showing help, any key closes it
		if a.showingHelp {
			a.closeHelp()
			return a, nil
		}

		// Handle global keys
		switch {
		case msg.String() == "ctrl+c":
			a.quitting = true
			if a.onQuit != nil {
				a.onQuit()
			}
			return a, tea.Quit

		case msg.String() == "q":
			// Only quit if not in search mode
			if !a.viewer.IsSearchMode() {
				a.quitting = true
				if a.onQuit != nil {
					a.onQuit()
				}
				return a, tea.Quit
			}

		case msg.String() == "b" || msg.String() == "ctrl+b":
			// Toggle sidebar
			a.layout.ToggleSidebar()
			dims := a.layout.CalculateDimensions()
			dims.ApplyToComponents(a.sidebar, a.viewer, a.statusBar)
			return a, nil

		case msg.String() == "tab":
			// Switch focus
			a.switchFocus()
			a.updateStatusBar()
			return a, nil

		case msg.String() == "shift+tab":
			// Switch focus backwards
			a.switchFocusBackwards()
			a.updateStatusBar()
			return a, nil

		case msg.String() == "?":
			// Show help
			a.showHelp()
			return a, nil
		}

		// Route key to focused component
		switch a.focus {
		case FocusSidebar:
			a.sidebar, cmd = a.sidebar.Update(msg)
			cmds = append(cmds, cmd)
		case FocusViewer:
			a.viewer, cmd = a.viewer.Update(msg)
			cmds = append(cmds, cmd)
		}

		a.updateStatusBar()

	case components.SidebarSelectMsg:
		// Handle sidebar selection
		if a.onSelect != nil {
			err := a.onSelect(msg.Item)
			if err != nil {
				a.statusBar.SetMode("ERROR")
				a.statusBar.SetLeftInfo(fmt.Sprintf("Error: %s", err.Error()))
			}
		}
		a.updateStatusBar()

	case components.GotoTopMsg:
		// Handle 'gg' command
		if a.focus == FocusViewer {
			a.viewer.ScrollToTop()
		}

	case tea.MouseMsg:
		// Route mouse events to focused component
		switch a.focus {
		case FocusSidebar:
			a.sidebar, cmd = a.sidebar.Update(msg)
			cmds = append(cmds, cmd)
		case FocusViewer:
			a.viewer, cmd = a.viewer.Update(msg)
			cmds = append(cmds, cmd)
		}
	}

	return a, tea.Batch(cmds...)
}

// View implements tea.Model
func (a *App) View() string {
	if !a.ready {
		return "Loading..."
	}

	if a.quitting {
		return "Goodbye!\n"
	}

	dims := a.layout.CalculateDimensions()
	return RenderLayout(a.sidebar, a.viewer, a.statusBar, dims)
}

// Run starts the TUI application
func (a *App) Run() error {
	p := tea.NewProgram(
		a,
		tea.WithAltScreen(),
		tea.WithMouseCellMotion(),
	)

	_, err := p.Run()
	return err
}

// Helper methods

func (a *App) switchFocus() {
	switch a.focus {
	case FocusSidebar:
		if a.layout.IsSidebarVisible() {
			a.focus = FocusViewer
		}
	case FocusViewer:
		if a.layout.IsSidebarVisible() {
			a.focus = FocusSidebar
		}
	}
}

func (a *App) switchFocusBackwards() {
	switch a.focus {
	case FocusViewer:
		if a.layout.IsSidebarVisible() {
			a.focus = FocusSidebar
		}
	case FocusSidebar:
		if a.layout.IsSidebarVisible() {
			a.focus = FocusViewer
		}
	}
}

func (a *App) updateStatusBar() {
	// Update mode based on focus and state
	switch a.focus {
	case FocusSidebar:
		a.statusBar.SetMode("SIDEBAR")
	case FocusViewer:
		if a.viewer.IsSearchMode() {
			a.statusBar.SetMode("SEARCH")
			a.statusBar.SetLeftInfo(a.viewer.GetSearchQuery())
		} else if a.viewer.IsGotoLineMode() {
			a.statusBar.SetMode("GOTO")
			a.statusBar.SetLeftInfo(a.viewer.GetGotoLineInput())
		} else {
			a.statusBar.SetMode("VIEWER")
			// Update position
			current, total := a.viewer.GetPosition()
			a.statusBar.SetPosition(current, total)
		}
	}
}

func (a *App) showHelp() {
	// Save current viewer state
	a.previousContent = a.viewer.GetContent()
	a.previousTitle = a.viewer.GetTitle()
	a.showingHelp = true

	helpContent := `# Morphir TUI Help

## Navigation

| Key | Action |
|-----|--------|
| j/k or ↑/↓ | Move up/down |
| h/l or ←/→ | Switch panels or collapse/expand |
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

## View Options

| Key | Action |
|-----|--------|
| Ctrl+n | Toggle line numbers |
| :line | Go to line number |

## General

| Key | Action |
|-----|--------|
| ? | Show this help |
| q or Ctrl+c | Quit |
| Enter | Select item |

Press any key to return.
`
	a.viewer.SetContent(helpContent)
	a.viewer.SetTitle("Help")
	a.focus = FocusViewer
}

func (a *App) closeHelp() {
	// Restore previous viewer state
	a.viewer.SetContent(a.previousContent)
	a.viewer.SetTitle(a.previousTitle)
	a.showingHelp = false
}

// Public API

// SetSidebarItems updates the sidebar items
func (a *App) SetSidebarItems(items []*components.SidebarItem) {
	a.sidebar.SetItems(items)
}

// SetViewerContent updates the viewer content
func (a *App) SetViewerContent(content string) {
	a.viewer.SetContent(content)
}

// SetViewerTitle updates the viewer title
func (a *App) SetViewerTitle(title string) {
	a.viewer.SetTitle(title)
}

// GetSidebar returns the sidebar component
func (a *App) GetSidebar() *components.Sidebar {
	return a.sidebar
}

// GetViewer returns the viewer component
func (a *App) GetViewer() *components.Viewer {
	return a.viewer
}

// GetStatusBar returns the status bar component
func (a *App) GetStatusBar() *components.StatusBar {
	return a.statusBar
}
