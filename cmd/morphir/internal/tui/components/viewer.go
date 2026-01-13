package components

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/glamour"
	"github.com/charmbracelet/lipgloss/v2"
	"github.com/finos/morphir/cmd/morphir/internal/tui/keymap"
	"github.com/finos/morphir/cmd/morphir/internal/tui/styles"
)

// Viewer displays markdown content with vim-style navigation
type Viewer struct {
	width         int
	height        int
	content       string // Raw markdown content
	rendered      string // Glamour-rendered content
	viewport      viewport.Model
	title         string
	keymap        keymap.VimKeyMap
	showLineNums  bool
	showCursor    bool // Show cursor line highlight
	cursorLine    int  // Current cursor line (0-based)
	renderer      *glamour.TermRenderer
	searchMode    bool
	searchQuery   string
	searchMatches []int
	currentMatch  int
	gotoLineMode  bool
	gotoLineInput string
	focused       bool // Whether this viewer has focus
}

// NewViewer creates a new viewer component
func NewViewer(title string, km keymap.VimKeyMap) *Viewer {
	vp := viewport.New(0, 0)
	return &Viewer{
		title:         title,
		keymap:        km,
		viewport:      vp,
		showLineNums:  false, // Line numbers off by default for rendered content
		showCursor:    true,  // Show cursor line highlight by default
		cursorLine:    0,     // Start at first line
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
		if v.gotoLineMode {
			return v.handleGotoLineKeyPress(msg)
		}
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
	case tea.MouseMsg:
		// Handle mouse wheel scrolling
		if msg.Action == tea.MouseActionPress {
			switch msg.Button {
			case tea.MouseButtonWheelUp:
				v.viewport.ScrollUp(3)
				return v, nil
			case tea.MouseButtonWheelDown:
				v.viewport.ScrollDown(3)
				return v, nil
			}
		}
	}

	var cmd tea.Cmd
	v.viewport, cmd = v.viewport.Update(msg)
	return v, cmd
}

// View implements tea.Model
func (v *Viewer) View() string {
	// Use default dimensions if not sized yet
	width := v.width
	height := v.height
	if width == 0 {
		width = 80 // Default width
	}
	if height == 0 {
		height = 24 // Default height
	}

	// Render title with scrollbar indicator
	titleBar := v.renderTitleBar(width)

	// Render input bar if in search or goto-line mode
	var inputBar string
	if v.searchMode {
		inputBar = v.renderSearchBar()
	} else if v.gotoLineMode {
		inputBar = v.renderGotoLineBar()
	}

	// Get viewport content with optional line numbers
	viewportContent := v.getViewportContent()

	// Combine components
	var components []string
	components = append(components, titleBar)
	if inputBar != "" {
		components = append(components, inputBar)
	}
	components = append(components, viewportContent)

	main := lipgloss.JoinVertical(lipgloss.Left, components...)

	// Add border with focus indication
	borderStyle := styles.BorderStyle
	if v.focused {
		borderStyle = borderStyle.BorderForeground(styles.DefaultTheme.Primary)
	}

	return borderStyle.
		Width(width - 2).
		Height(height - 2).
		Render(main)
}

func (v *Viewer) handleKeyPress(msg tea.KeyMsg) (*Viewer, tea.Cmd) {
	lines := strings.Split(v.rendered, "\n")
	maxLine := len(lines) - 1

	switch {
	case key.Matches(msg, v.keymap.Up):
		if v.cursorLine > 0 {
			v.cursorLine--
			v.ensureCursorVisible()
		}
		return v, nil
	case key.Matches(msg, v.keymap.Down):
		if v.cursorLine < maxLine {
			v.cursorLine++
			v.ensureCursorVisible()
		}
		return v, nil
	case key.Matches(msg, v.keymap.PageUp):
		v.viewport.PageUp()
	case key.Matches(msg, v.keymap.PageDown):
		v.viewport.PageDown()
	case key.Matches(msg, v.keymap.HalfPageUp):
		v.viewport.HalfPageUp()
	case key.Matches(msg, v.keymap.HalfPageDown):
		v.viewport.HalfPageDown()
	case key.Matches(msg, v.keymap.Top):
		// Handle 'gg' for top - need to track double 'g' press
		if msg.String() == "g" {
			return v, v.waitForSecondG()
		}
	case key.Matches(msg, v.keymap.Bottom):
		v.cursorLine = maxLine
		v.ensureCursorVisible()
	case key.Matches(msg, v.keymap.Search):
		v.searchMode = true
		v.searchQuery = ""
		return v, nil
	case key.Matches(msg, v.keymap.NextMatch):
		v.nextSearchMatch()
	case key.Matches(msg, v.keymap.PrevMatch):
		v.prevSearchMatch()
	case key.Matches(msg, v.keymap.ToggleLineNumbers):
		v.showLineNums = !v.showLineNums
		v.renderContent()
		return v, nil
	case key.Matches(msg, v.keymap.GotoLine):
		v.gotoLineMode = true
		v.gotoLineInput = ""
		return v, nil
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

func (v *Viewer) handleGotoLineKeyPress(msg tea.KeyMsg) (*Viewer, tea.Cmd) {
	switch msg.String() {
	case "enter":
		// Execute goto line
		v.gotoLineMode = false
		v.executeGotoLine()
		return v, nil
	case "esc":
		// Cancel goto line
		v.gotoLineMode = false
		v.gotoLineInput = ""
		return v, nil
	case "backspace":
		if len(v.gotoLineInput) > 0 {
			v.gotoLineInput = v.gotoLineInput[:len(v.gotoLineInput)-1]
		}
	default:
		// Only accept digits
		if len(msg.String()) == 1 && msg.String()[0] >= '0' && msg.String()[0] <= '9' {
			v.gotoLineInput += msg.String()
		}
	}
	return v, nil
}

func (v *Viewer) waitForSecondG() tea.Cmd {
	return func() tea.Msg {
		return GotoTopMsg{}
	}
}

func (v *Viewer) renderTitleBar(width int) string {
	// Create title text
	titleText := v.title

	// Add scrollbar indicator if content is scrollable
	scrollIndicator := v.getScrollIndicator()
	if scrollIndicator != "" {
		// Reserve space for scroll indicator on the right
		availableWidth := width - 4 - len(scrollIndicator)
		if availableWidth < len(titleText) {
			titleText = titleText[:availableWidth-3] + "..."
		}

		titleStyle := styles.TitleStyle.Width(availableWidth)
		indicatorStyle := lipgloss.NewStyle().
			Foreground(styles.DefaultTheme.Muted).
			Padding(0, 1)

		title := titleStyle.Render(titleText)
		indicator := indicatorStyle.Render(scrollIndicator)

		return lipgloss.JoinHorizontal(lipgloss.Top, title, indicator)
	}

	return styles.TitleStyle.Width(width - 2).Render(titleText)
}

func (v *Viewer) getScrollIndicator() string {
	lines := strings.Split(v.rendered, "\n")
	totalLines := len(lines)

	if totalLines == 0 || v.viewport.Height == 0 {
		return ""
	}

	// Only show scrollbar if content is larger than viewport
	if totalLines <= v.viewport.Height {
		return ""
	}

	// Calculate scroll percentage
	viewportTop := v.viewport.YOffset
	viewportBottom := viewportTop + v.viewport.Height
	if viewportBottom > totalLines {
		viewportBottom = totalLines
	}

	// Show position like "1-20/100" or use scroll percentage
	scrollPercent := int(float64(viewportTop) / float64(totalLines-v.viewport.Height) * 100)
	if scrollPercent > 100 {
		scrollPercent = 100
	}
	if scrollPercent < 0 {
		scrollPercent = 0
	}

	// Return indicator showing current position
	if viewportTop == 0 {
		return "Top"
	} else if viewportBottom >= totalLines {
		return "Bot"
	} else {
		return fmt.Sprintf("%d%%", scrollPercent)
	}
}

func (v *Viewer) renderSearchBar() string {
	searchStyle := lipgloss.NewStyle().
		Foreground(styles.DefaultTheme.Accent).
		Padding(0, 1)

	return searchStyle.Render("/" + v.searchQuery)
}

func (v *Viewer) renderGotoLineBar() string {
	gotoStyle := lipgloss.NewStyle().
		Foreground(styles.DefaultTheme.Accent).
		Padding(0, 1)

	return gotoStyle.Render(":" + v.gotoLineInput)
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

func (v *Viewer) executeGotoLine() {
	if v.gotoLineInput == "" {
		return
	}

	lineNum, err := strconv.Atoi(v.gotoLineInput)
	if err != nil {
		return
	}

	// Convert to 0-based index
	lineNum--

	// Clamp to valid range
	lines := strings.Split(v.rendered, "\n")
	if lineNum < 0 {
		lineNum = 0
	}
	if lineNum >= len(lines) {
		lineNum = len(lines) - 1
	}

	v.viewport.YOffset = lineNum
}

func (v *Viewer) getViewportContent() string {
	if !v.showLineNums {
		return v.viewport.View()
	}

	// Add line numbers to viewport content
	lines := strings.Split(v.rendered, "\n")
	maxLineNum := len(lines)
	lineNumWidth := len(fmt.Sprintf("%d", maxLineNum))

	numberedLines := make([]string, 0, len(lines))
	for i, line := range lines {
		lineNum := i + 1
		lineNumStr := fmt.Sprintf("%*d ", lineNumWidth, lineNum)
		lineNumStyle := lipgloss.NewStyle().
			Foreground(styles.DefaultTheme.Muted)

		// Highlight cursor line
		styledLine := line
		if v.showCursor && i == v.cursorLine {
			// Calculate available width for the line (viewport width minus line number width)
			availableWidth := v.viewport.Width - lineNumWidth - 1
			if availableWidth < 0 {
				availableWidth = 0
			}

			cursorStyle := lipgloss.NewStyle().
				Background(styles.DefaultTheme.SelectedBg).
				Foreground(styles.DefaultTheme.Foreground).
				Width(availableWidth)
			styledLine = cursorStyle.Render(line)
		}

		numberedLines = append(numberedLines, lineNumStyle.Render(lineNumStr)+styledLine)
	}

	numberedContent := strings.Join(numberedLines, "\n")

	// Create a temporary viewport with numbered content
	// Use actual viewport dimensions, or defaults if not sized yet
	vpWidth := v.viewport.Width
	vpHeight := v.viewport.Height
	if vpWidth == 0 {
		vpWidth = 78 // Default width minus borders (80-2)
	}
	if vpHeight == 0 {
		vpHeight = 21 // Default height minus title and borders (24-3)
	}

	tempViewport := viewport.New(vpWidth, vpHeight)
	tempViewport.SetContent(numberedContent)
	tempViewport.YOffset = v.viewport.YOffset

	return tempViewport.View()
}

// ensureCursorVisible scrolls the viewport to ensure the cursor line is visible
func (v *Viewer) ensureCursorVisible() {
	viewportTop := v.viewport.YOffset
	viewportBottom := v.viewport.YOffset + v.viewport.Height - 1

	// If cursor is above viewport, scroll up
	if v.cursorLine < viewportTop {
		v.viewport.YOffset = v.cursorLine
	}
	// If cursor is below viewport, scroll down
	if v.cursorLine > viewportBottom {
		v.viewport.YOffset = v.cursorLine - v.viewport.Height + 1
	}
}

func (v *Viewer) renderContent() {
	if v.content == "" {
		v.rendered = ""
		v.viewport.SetContent("")
		return
	}

	// Determine wrap width - use a reasonable default if viewport not sized yet
	wrapWidth := v.viewport.Width
	if wrapWidth == 0 {
		wrapWidth = 80 // Default width before first resize
	}

	// Initialize renderer if needed or if width changed significantly
	if v.renderer == nil {
		// Use auto-detection for dark/light mode
		renderer, err := glamour.NewTermRenderer(
			glamour.WithAutoStyle(),
			glamour.WithWordWrap(wrapWidth),
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

	// Use rendered content as-is - glamour handles spacing
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
	// Return cursor line position, not viewport offset
	return v.cursorLine + 1, len(lines)
}

// ScrollToTop scrolls to the top of the content
func (v *Viewer) ScrollToTop() {
	v.cursorLine = 0
	v.viewport.GotoTop()
}

// ScrollToBottom scrolls to the bottom of the content
func (v *Viewer) ScrollToBottom() {
	lines := strings.Split(v.rendered, "\n")
	v.cursorLine = len(lines) - 1
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

// GetContent returns the current raw markdown content
func (v *Viewer) GetContent() string {
	return v.content
}

// GetTitle returns the current viewer title
func (v *Viewer) GetTitle() string {
	return v.title
}

// IsGotoLineMode returns whether the viewer is in goto-line mode
func (v *Viewer) IsGotoLineMode() bool {
	return v.gotoLineMode
}

// GetGotoLineInput returns the current goto-line input
func (v *Viewer) GetGotoLineInput() string {
	return v.gotoLineInput
}

// ToggleLineNumbers toggles line number display
func (v *Viewer) ToggleLineNumbers() {
	v.showLineNums = !v.showLineNums
	v.renderContent()
}

// GetShowLineNumbers returns whether line numbers are shown
func (v *Viewer) GetShowLineNumbers() bool {
	return v.showLineNums
}

// SetFocused sets whether this viewer has focus
func (v *Viewer) SetFocused(focused bool) {
	v.focused = focused
}

// IsFocused returns whether this viewer has focus
func (v *Viewer) IsFocused() bool {
	return v.focused
}
