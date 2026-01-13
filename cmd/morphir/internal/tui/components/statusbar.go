package components

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss/v2"
	"github.com/finos/morphir/cmd/morphir/internal/tui/keymap"
	"github.com/finos/morphir/cmd/morphir/internal/tui/styles"
)

// StatusBar displays status information and keybinding hints at the bottom of the screen
type StatusBar struct {
	width       int
	mode        string
	leftInfo    string
	rightInfo   string
	keybindings []string
	keymap      keymap.VimKeyMap
}

// NewStatusBar creates a new status bar component
func NewStatusBar(km keymap.VimKeyMap) *StatusBar {
	return &StatusBar{
		keymap: km,
		mode:   "NORMAL",
	}
}

// Init implements tea.Model
func (s *StatusBar) Init() tea.Cmd {
	return nil
}

// Update implements tea.Model
func (s *StatusBar) Update(msg tea.Msg) (*StatusBar, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		s.width = msg.Width
	}
	return s, nil
}

// View implements tea.Model
func (s *StatusBar) View() string {
	if s.width == 0 {
		return ""
	}

	// Build left section (mode + left info)
	leftSection := s.renderLeftSection()

	// Build center section (keybinding hints)
	centerSection := s.renderCenterSection()

	// Build right section (right info)
	rightSection := s.renderRightSection()

	// Calculate spacing
	leftWidth := lipgloss.Width(leftSection)
	centerWidth := lipgloss.Width(centerSection)
	rightWidth := lipgloss.Width(rightSection)

	// Calculate available space for padding
	totalContent := leftWidth + centerWidth + rightWidth
	availableSpace := s.width - totalContent

	// If we have space, distribute it
	var leftPadding, rightPadding int
	if availableSpace > 0 {
		// Try to center the center section
		leftPadding = (availableSpace - centerWidth) / 2
		rightPadding = availableSpace - leftPadding
		if leftPadding < 0 {
			leftPadding = 0
		}
		if rightPadding < 0 {
			rightPadding = 0
		}
	}

	// Build final status bar
	var parts []string
	parts = append(parts, leftSection)
	if leftPadding > 0 {
		parts = append(parts, strings.Repeat(" ", leftPadding))
	}
	parts = append(parts, centerSection)
	if rightPadding > 0 {
		parts = append(parts, strings.Repeat(" ", rightPadding))
	}
	parts = append(parts, rightSection)

	line := strings.Join(parts, "")

	// Ensure we don't exceed width to prevent wrapping
	lineWidth := lipgloss.Width(line)
	if lineWidth > s.width {
		// Truncate content to fit within width
		overflow := lineWidth - s.width
		// Remove overflow from center section first (keybindings)
		if overflow > 0 && centerWidth > 0 {
			// Rebuild without center section
			parts = []string{leftSection}
			if rightWidth > 0 {
				padding := s.width - leftWidth - rightWidth
				if padding > 0 {
					parts = append(parts, strings.Repeat(" ", padding))
				}
				parts = append(parts, rightSection)
			}
			line = strings.Join(parts, "")
		}
	}

	// Render with explicit height constraint to prevent wrapping to multiple lines
	return styles.StatusBarStyle.
		Width(s.width).
		MaxWidth(s.width).
		Height(1).
		MaxHeight(1).
		Inline(true).
		Render(line)
}

func (s *StatusBar) renderLeftSection() string {
	modeStyle := lipgloss.NewStyle().
		Background(styles.DefaultTheme.Primary).
		Foreground(lipgloss.Color("#FFFFFF")).
		Bold(true).
		Padding(0, 1)

	mode := modeStyle.Render(s.mode)

	if s.leftInfo != "" {
		info := lipgloss.NewStyle().
			Foreground(styles.DefaultTheme.Foreground).
			Padding(0, 1).
			Render(s.leftInfo)
		return mode + info
	}

	return mode
}

func (s *StatusBar) renderCenterSection() string {
	if len(s.keybindings) == 0 {
		// Show default keybindings
		hints := []string{
			styles.RenderKeybinding("?", "help"),
			styles.RenderKeybinding("b", "sidebar"),
			styles.RenderKeybinding("q", "quit"),
		}
		return strings.Join(hints, "  ")
	}

	return strings.Join(s.keybindings, "  ")
}

func (s *StatusBar) renderRightSection() string {
	if s.rightInfo == "" {
		return ""
	}

	return lipgloss.NewStyle().
		Foreground(styles.DefaultTheme.Muted).
		Padding(0, 1).
		Render(s.rightInfo)
}

// SetMode updates the current mode (e.g., "NORMAL", "SEARCH", "HELP")
func (s *StatusBar) SetMode(mode string) {
	s.mode = mode
}

// SetLeftInfo sets the left information text
func (s *StatusBar) SetLeftInfo(info string) {
	s.leftInfo = info
}

// SetRightInfo sets the right information text (e.g., position, file info)
func (s *StatusBar) SetRightInfo(info string) {
	s.rightInfo = info
}

// SetKeybindings sets custom keybinding hints to display
func (s *StatusBar) SetKeybindings(bindings []string) {
	s.keybindings = bindings
}

// SetPosition updates the right info with current position
func (s *StatusBar) SetPosition(line, total int) {
	// Calculate width needed for total to ensure alignment
	totalWidth := len(fmt.Sprintf("%d", total))
	s.rightInfo = fmt.Sprintf("Ln %*d/%d", totalWidth, line, total)
}

// SetWidth updates the width of the status bar
func (s *StatusBar) SetWidth(width int) {
	s.width = width
}
