package styles

import (
	"github.com/charmbracelet/lipgloss/v2"
	"github.com/charmbracelet/lipgloss/v2/compat"
)

// Theme defines the color palette and styles for the TUI
type Theme struct {
	Primary    compat.AdaptiveColor
	Secondary  compat.AdaptiveColor
	Accent     compat.AdaptiveColor
	Muted      compat.AdaptiveColor
	Background compat.AdaptiveColor
	Foreground compat.AdaptiveColor
	Border     compat.AdaptiveColor
	SelectedBg compat.AdaptiveColor
	SelectedFg compat.AdaptiveColor
	ErrorFg    compat.AdaptiveColor
	WarningFg  compat.AdaptiveColor
	SuccessFg  compat.AdaptiveColor
	InfoFg     compat.AdaptiveColor
}

// DefaultTheme provides a professional, terminal-friendly color scheme
var DefaultTheme = Theme{
	Primary:    compat.AdaptiveColor{Light: lipgloss.Color("#7D56F4"), Dark: lipgloss.Color("#7D56F4")},
	Secondary:  compat.AdaptiveColor{Light: lipgloss.Color("#3C3C3C"), Dark: lipgloss.Color("#DDDDDD")},
	Accent:     compat.AdaptiveColor{Light: lipgloss.Color("#F25D94"), Dark: lipgloss.Color("#F25D94")},
	Muted:      compat.AdaptiveColor{Light: lipgloss.Color("#888888"), Dark: lipgloss.Color("#666666")},
	Background: compat.AdaptiveColor{Light: lipgloss.Color("#FFFFFF"), Dark: lipgloss.Color("#1A1A1A")},
	Foreground: compat.AdaptiveColor{Light: lipgloss.Color("#1A1A1A"), Dark: lipgloss.Color("#DDDDDD")},
	Border:     compat.AdaptiveColor{Light: lipgloss.Color("#CCCCCC"), Dark: lipgloss.Color("#444444")},
	SelectedBg: compat.AdaptiveColor{Light: lipgloss.Color("#E0E0E0"), Dark: lipgloss.Color("#2A2A2A")},
	SelectedFg: compat.AdaptiveColor{Light: lipgloss.Color("#000000"), Dark: lipgloss.Color("#FFFFFF")},
	ErrorFg:    compat.AdaptiveColor{Light: lipgloss.Color("#D70000"), Dark: lipgloss.Color("#FF5555")},
	WarningFg:  compat.AdaptiveColor{Light: lipgloss.Color("#FF8700"), Dark: lipgloss.Color("#FFAA00")},
	SuccessFg:  compat.AdaptiveColor{Light: lipgloss.Color("#008700"), Dark: lipgloss.Color("#50FA7B")},
	InfoFg:     compat.AdaptiveColor{Light: lipgloss.Color("#0087D7"), Dark: lipgloss.Color("#8BE9FD")},
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
