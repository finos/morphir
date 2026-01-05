package styles

import "github.com/charmbracelet/lipgloss"

// Theme defines the color palette and styles for the TUI
type Theme struct {
	Primary    lipgloss.AdaptiveColor
	Secondary  lipgloss.AdaptiveColor
	Accent     lipgloss.AdaptiveColor
	Muted      lipgloss.AdaptiveColor
	Background lipgloss.AdaptiveColor
	Foreground lipgloss.AdaptiveColor
	Border     lipgloss.AdaptiveColor
	SelectedBg lipgloss.AdaptiveColor
	SelectedFg lipgloss.AdaptiveColor
	ErrorFg    lipgloss.AdaptiveColor
	WarningFg  lipgloss.AdaptiveColor
	SuccessFg  lipgloss.AdaptiveColor
	InfoFg     lipgloss.AdaptiveColor
}

// DefaultTheme provides a professional, terminal-friendly color scheme
var DefaultTheme = Theme{
	Primary:    lipgloss.AdaptiveColor{Light: "#7D56F4", Dark: "#7D56F4"},
	Secondary:  lipgloss.AdaptiveColor{Light: "#3C3C3C", Dark: "#DDDDDD"},
	Accent:     lipgloss.AdaptiveColor{Light: "#F25D94", Dark: "#F25D94"},
	Muted:      lipgloss.AdaptiveColor{Light: "#888888", Dark: "#666666"},
	Background: lipgloss.AdaptiveColor{Light: "#FFFFFF", Dark: "#1A1A1A"},
	Foreground: lipgloss.AdaptiveColor{Light: "#1A1A1A", Dark: "#DDDDDD"},
	Border:     lipgloss.AdaptiveColor{Light: "#CCCCCC", Dark: "#444444"},
	SelectedBg: lipgloss.AdaptiveColor{Light: "#E0E0E0", Dark: "#2A2A2A"},
	SelectedFg: lipgloss.AdaptiveColor{Light: "#000000", Dark: "#FFFFFF"},
	ErrorFg:    lipgloss.AdaptiveColor{Light: "#D70000", Dark: "#FF5555"},
	WarningFg:  lipgloss.AdaptiveColor{Light: "#FF8700", Dark: "#FFAA00"},
	SuccessFg:  lipgloss.AdaptiveColor{Light: "#008700", Dark: "#50FA7B"},
	InfoFg:     lipgloss.AdaptiveColor{Light: "#0087D7", Dark: "#8BE9FD"},
}

// Common style definitions
var (
	// TitleStyle for panel titles
	TitleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(DefaultTheme.Primary).
			Padding(0, 1)

	// SubtitleStyle for section headers
	SubtitleStyle = lipgloss.NewStyle().
			Foreground(DefaultTheme.Secondary).
			Padding(0, 1)

	// BorderStyle for panel borders
	BorderStyle = lipgloss.NewStyle().
			BorderStyle(lipgloss.RoundedBorder()).
			BorderForeground(DefaultTheme.Border).
			Padding(0, 1)

	// SelectedItemStyle for selected list/tree items
	SelectedItemStyle = lipgloss.NewStyle().
				Background(DefaultTheme.SelectedBg).
				Foreground(DefaultTheme.SelectedFg).
				Bold(true)

	// NormalItemStyle for unselected items
	NormalItemStyle = lipgloss.NewStyle().
			Foreground(DefaultTheme.Foreground)

	// MutedStyle for less important text
	MutedStyle = lipgloss.NewStyle().
			Foreground(DefaultTheme.Muted)

	// ErrorStyle for error messages
	ErrorStyle = lipgloss.NewStyle().
			Foreground(DefaultTheme.ErrorFg).
			Bold(true)

	// WarningStyle for warnings
	WarningStyle = lipgloss.NewStyle().
			Foreground(DefaultTheme.WarningFg)

	// SuccessStyle for success messages
	SuccessStyle = lipgloss.NewStyle().
			Foreground(DefaultTheme.SuccessFg)

	// InfoStyle for informational messages
	InfoStyle = lipgloss.NewStyle().
			Foreground(DefaultTheme.InfoFg)

	// StatusBarStyle for the bottom status bar
	StatusBarStyle = lipgloss.NewStyle().
			Foreground(DefaultTheme.Foreground).
			Background(DefaultTheme.SelectedBg).
			Padding(0, 1)

	// KeybindingStyle for keybinding hints
	KeybindingStyle = lipgloss.NewStyle().
			Foreground(DefaultTheme.Primary).
			Bold(true)

	// KeybindingDescStyle for keybinding descriptions
	KeybindingDescStyle = lipgloss.NewStyle().
				Foreground(DefaultTheme.Muted)
)

// Render helpers

// RenderKeybinding formats a keybinding hint like "q quit"
func RenderKeybinding(key, desc string) string {
	return KeybindingStyle.Render(key) + " " + KeybindingDescStyle.Render(desc)
}

// RenderSeparator creates a vertical separator
func RenderSeparator(height int) string {
	style := lipgloss.NewStyle().
		Foreground(DefaultTheme.Border).
		Height(height)
	return style.Render("│")
}
