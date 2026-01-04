package components

import (
	"strings"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/glamour"
	"github.com/charmbracelet/lipgloss"
	"github.com/finos/morphir/cmd/morphir/internal/tui/keymap"
	"github.com/finos/morphir/cmd/morphir/internal/tui/styles"
)

// Viewer displays markdown content with vim-style navigation
type Viewer struct {
	width        int
	height       int
	content      string // Raw markdown content
	rendered     string // Glamour-rendered content
	viewport     viewport.Model
	title        string
	keymap       keymap.VimKeyMap
	showLineNums bool
	renderer     *glamour.TermRenderer
	searchMode   bool
	searchQuery  string
	searchMatches []int
	currentMatch int
}

// NewViewer creates a new viewer component
func NewViewer(title string, km keymap.VimKeyMap) *Viewer {
	vp := viewport.New(0, 0)
	return &Viewer{
		title:      title,
		keymap:     km,
		viewport:   vp,
		showLineNums: false,
		searchMatches: make([]int, 0),
	}
}

// Init implements tea.Model
func (v *Viewer) Init() tea.Cmd {
	return nil
}

// Update implements tea.Model
func (v *Viewer) Update(msg tea.Msg) (*Viewer, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		if v.searchMode {
			return v.handleSearchKeyPress(msg)
		}
		return v.handleKeyPress(msg)
	case tea.WindowSizeMsg:
		v.width = msg.Width
		v.height = msg.Height
		v.viewport.Width = v.width - 2
		v.viewport.Height = v.height - 3
		// Re-render content with new width
		v.renderContent()
	}

	var cmd tea.Cmd
	v.viewport, cmd = v.viewport.Update(msg)
	return v, cmd
}

// View implements tea.Model
func (v *Viewer) View() string {
	// Render title
	titleBar := styles.TitleStyle.Width(v.width - 2).Render(v.title)

	// Render search bar if in search mode
	var searchBar string
	if v.searchMode {
		searchBar = v.renderSearchBar()
	}

	// Combine components
	var components []string
	components = append(components, titleBar)
	if searchBar != "" {
		components = append(components, searchBar)
	}
	components = append(components, v.viewport.View())

	main := lipgloss.JoinVertical(lipgloss.Left, components...)

	// Add border
	return styles.BorderStyle.
		Width(v.width - 2).
		Height(v.height - 2).
		Render(main)
}

func (v *Viewer) handleKeyPress(msg tea.KeyMsg) (*Viewer, tea.Cmd) {
	switch {
	case key.Matches(msg, v.keymap.Up):
		v.viewport.LineUp(1)
	case key.Matches(msg, v.keymap.Down):
		v.viewport.LineDown(1)
	case key.Matches(msg, v.keymap.PageUp):
		v.viewport.ViewUp()
	case key.Matches(msg, v.keymap.PageDown):
		v.viewport.ViewDown()
	case key.Matches(msg, v.keymap.HalfPageUp):
		v.viewport.HalfViewUp()
	case key.Matches(msg, v.keymap.HalfPageDown):
		v.viewport.HalfViewDown()
	case key.Matches(msg, v.keymap.Top):
		// Handle 'gg' for top - need to track double 'g' press
		if msg.String() == "g" {
			return v, v.waitForSecondG()
		}
	case key.Matches(msg, v.keymap.Bottom):
		v.viewport.GotoBottom()
	case key.Matches(msg, v.keymap.Search):
		v.searchMode = true
		v.searchQuery = ""
		return v, nil
	case key.Matches(msg, v.keymap.NextMatch):
		v.nextSearchMatch()
	case key.Matches(msg, v.keymap.PrevMatch):
		v.prevSearchMatch()
	}

	return v, nil
}

func (v *Viewer) handleSearchKeyPress(msg tea.KeyMsg) (*Viewer, tea.Cmd) {
	switch msg.String() {
	case "enter":
		// Execute search
		v.searchMode = false
		v.executeSearch()
		return v, nil
	case "esc":
		// Cancel search
		v.searchMode = false
		v.searchQuery = ""
		return v, nil
	case "backspace":
		if len(v.searchQuery) > 0 {
			v.searchQuery = v.searchQuery[:len(v.searchQuery)-1]
		}
	default:
		// Append to search query
		v.searchQuery += msg.String()
	}
	return v, nil
}

func (v *Viewer) waitForSecondG() tea.Cmd {
	return func() tea.Msg {
		return GotoTopMsg{}
	}
}

func (v *Viewer) renderSearchBar() string {
	searchStyle := lipgloss.NewStyle().
		Foreground(styles.DefaultTheme.Accent).
		Padding(0, 1)

	return searchStyle.Render("/" + v.searchQuery)
}

func (v *Viewer) executeSearch() {
	if v.searchQuery == "" {
		v.searchMatches = make([]int, 0)
		return
	}

	// Search in rendered content
	lines := strings.Split(v.rendered, "\n")
	v.searchMatches = make([]int, 0)

	query := strings.ToLower(v.searchQuery)
	for i, line := range lines {
		if strings.Contains(strings.ToLower(line), query) {
			v.searchMatches = append(v.searchMatches, i)
		}
	}

	if len(v.searchMatches) > 0 {
		v.currentMatch = 0
		v.viewport.YOffset = v.searchMatches[0]
	}
}

func (v *Viewer) nextSearchMatch() {
	if len(v.searchMatches) == 0 {
		return
	}

	v.currentMatch++
	if v.currentMatch >= len(v.searchMatches) {
		v.currentMatch = 0
	}

	v.viewport.YOffset = v.searchMatches[v.currentMatch]
}

func (v *Viewer) prevSearchMatch() {
	if len(v.searchMatches) == 0 {
		return
	}

	v.currentMatch--
	if v.currentMatch < 0 {
		v.currentMatch = len(v.searchMatches) - 1
	}

	v.viewport.YOffset = v.searchMatches[v.currentMatch]
}

func (v *Viewer) renderContent() {
	if v.content == "" {
		v.rendered = ""
		v.viewport.SetContent("")
		return
	}

	// Initialize renderer if needed
	if v.renderer == nil {
		// Use auto-detection for dark/light mode
		renderer, err := glamour.NewTermRenderer(
			glamour.WithAutoStyle(),
			glamour.WithWordWrap(v.viewport.Width),
		)
		if err != nil {
			// Fallback to plain content
			v.rendered = v.content
			v.viewport.SetContent(v.content)
			return
		}
		v.renderer = renderer
	}

	// Render markdown
	rendered, err := v.renderer.Render(v.content)
	if err != nil {
		// Fallback to plain content
		v.rendered = v.content
		v.viewport.SetContent(v.content)
		return
	}

	v.rendered = rendered
	v.viewport.SetContent(v.rendered)
}

// GotoTopMsg is sent when user presses 'gg'
type GotoTopMsg struct{}

// Public API

// SetContent sets the markdown content to display
func (v *Viewer) SetContent(content string) {
	v.content = content
	v.renderContent()
	v.viewport.GotoTop()
}

// SetTitle sets the viewer title
func (v *Viewer) SetTitle(title string) {
	v.title = title
}

// SetShowLineNumbers enables or disables line numbers
func (v *Viewer) SetShowLineNumbers(show bool) {
	v.showLineNums = show
}

// SetWidth sets the viewer width
func (v *Viewer) SetWidth(width int) {
	v.width = width
	v.viewport.Width = width - 2
	// Re-render with new width
	if v.renderer != nil {
		v.renderer = nil // Force re-creation with new width
		v.renderContent()
	}
}

// SetHeight sets the viewer height
func (v *Viewer) SetHeight(height int) {
	v.height = height
	v.viewport.Height = height - 3
}

// GetPosition returns the current line and total lines
func (v *Viewer) GetPosition() (current, total int) {
	lines := strings.Split(v.rendered, "\n")
	return v.viewport.YOffset + 1, len(lines)
}

// ScrollToTop scrolls to the top of the content
func (v *Viewer) ScrollToTop() {
	v.viewport.GotoTop()
}

// ScrollToBottom scrolls to the bottom of the content
func (v *Viewer) ScrollToBottom() {
	v.viewport.GotoBottom()
}

// IsSearchMode returns whether the viewer is in search mode
func (v *Viewer) IsSearchMode() bool {
	return v.searchMode
}

// GetSearchQuery returns the current search query
func (v *Viewer) GetSearchQuery() string {
	return v.searchQuery
}

// GetSearchResults returns the number of search matches
func (v *Viewer) GetSearchResults() int {
	return len(v.searchMatches)
}
