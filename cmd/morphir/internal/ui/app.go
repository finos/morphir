package ui

import (
	"fmt"

	tea "github.com/charmbracelet/bubbletea"
)

// Model represents the TUI application state
type Model struct {
	// State fields - kept immutable through functional updates
	message  string
	quitting bool
}

// NewModel creates a new initial model
func NewModel() Model {
	return Model{
		message:  "Welcome to Morphir CLI",
		quitting: false,
	}
}

// Init returns the initial command for the program
func (m Model) Init() tea.Cmd {
	return nil
}

// Update handles messages and returns a new model (functional update)
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c", "esc":
			m.quitting = true
			return m, tea.Quit
		case "enter":
			m.message = "You pressed enter!"
			return m, nil
		}
	}

	return m, nil
}

// View renders the UI (pure render function)
func (m Model) View() string {
	if m.quitting {
		return "Goodbye!\n"
	}

	return fmt.Sprintf(
		"\n%s\n\n%s\n\n%s\n",
		m.message,
		"Press 'q' to quit, 'enter' to interact",
		"(This is a placeholder TUI - full implementation coming soon)",
	)
}
