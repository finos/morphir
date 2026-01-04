package keymap

import "github.com/charmbracelet/bubbles/key"

// VimKeyMap defines vim-style keybindings for TUI navigation
type VimKeyMap struct {
	// Navigation
	Up         key.Binding
	Down       key.Binding
	Left       key.Binding
	Right      key.Binding
	PageUp     key.Binding
	PageDown   key.Binding
	HalfPageUp key.Binding
	HalfPageDown key.Binding
	Top        key.Binding
	Bottom     key.Binding

	// Panel navigation
	NextPanel key.Binding
	PrevPanel key.Binding
	ToggleSidebar key.Binding

	// Search
	Search     key.Binding
	NextMatch  key.Binding
	PrevMatch  key.Binding

	// Actions
	Select     key.Binding
	Help       key.Binding
	Quit       key.Binding
}

// DefaultVimKeyMap returns the default vim-style keybindings
func DefaultVimKeyMap() VimKeyMap {
	return VimKeyMap{
		// Navigation - vim keys
		Up: key.NewBinding(
			key.WithKeys("k", "up"),
			key.WithHelp("k/↑", "up"),
		),
		Down: key.NewBinding(
			key.WithKeys("j", "down"),
			key.WithHelp("j/↓", "down"),
		),
		Left: key.NewBinding(
			key.WithKeys("h", "left"),
			key.WithHelp("h/←", "left"),
		),
		Right: key.NewBinding(
			key.WithKeys("l", "right"),
			key.WithHelp("l/→", "right"),
		),

		// Page navigation
		PageUp: key.NewBinding(
			key.WithKeys("pgup"),
			key.WithHelp("pgup", "page up"),
		),
		PageDown: key.NewBinding(
			key.WithKeys("pgdown"),
			key.WithHelp("pgdown", "page down"),
		),
		HalfPageUp: key.NewBinding(
			key.WithKeys("ctrl+u"),
			key.WithHelp("ctrl+u", "half page up"),
		),
		HalfPageDown: key.NewBinding(
			key.WithKeys("ctrl+d"),
			key.WithHelp("ctrl+d", "half page down"),
		),
		Top: key.NewBinding(
			key.WithKeys("g"),
			key.WithHelp("gg", "go to top"),
		),
		Bottom: key.NewBinding(
			key.WithKeys("G"),
			key.WithHelp("G", "go to bottom"),
		),

		// Panel navigation
		NextPanel: key.NewBinding(
			key.WithKeys("tab", "l"),
			key.WithHelp("tab/l", "next panel"),
		),
		PrevPanel: key.NewBinding(
			key.WithKeys("shift+tab", "h"),
			key.WithHelp("shift+tab/h", "prev panel"),
		),
		ToggleSidebar: key.NewBinding(
			key.WithKeys("b", "ctrl+b"),
			key.WithHelp("b", "toggle sidebar"),
		),

		// Search
		Search: key.NewBinding(
			key.WithKeys("/"),
			key.WithHelp("/", "search"),
		),
		NextMatch: key.NewBinding(
			key.WithKeys("n"),
			key.WithHelp("n", "next match"),
		),
		PrevMatch: key.NewBinding(
			key.WithKeys("N"),
			key.WithHelp("N", "prev match"),
		),

		// Actions
		Select: key.NewBinding(
			key.WithKeys("enter"),
			key.WithHelp("enter", "select"),
		),
		Help: key.NewBinding(
			key.WithKeys("?"),
			key.WithHelp("?", "help"),
		),
		Quit: key.NewBinding(
			key.WithKeys("q", "ctrl+c"),
			key.WithHelp("q", "quit"),
		),
	}
}

// ShortHelp returns a quick help string for the most common keys
func (k VimKeyMap) ShortHelp() []key.Binding {
	return []key.Binding{
		k.Up,
		k.Down,
		k.ToggleSidebar,
		k.Help,
		k.Quit,
	}
}

// FullHelp returns all keybindings for the help screen
func (k VimKeyMap) FullHelp() [][]key.Binding {
	return [][]key.Binding{
		{k.Up, k.Down, k.Left, k.Right},
		{k.PageUp, k.PageDown, k.HalfPageUp, k.HalfPageDown},
		{k.Top, k.Bottom},
		{k.NextPanel, k.PrevPanel, k.ToggleSidebar},
		{k.Search, k.NextMatch, k.PrevMatch},
		{k.Select, k.Help, k.Quit},
	}
}
