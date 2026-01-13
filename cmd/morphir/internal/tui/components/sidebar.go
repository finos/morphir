package components

import (
	"strings"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss/v2"
	"github.com/finos/morphir/cmd/morphir/internal/tui/keymap"
	"github.com/finos/morphir/cmd/morphir/internal/tui/styles"
)

// SidebarItem represents an item in the sidebar
type SidebarItem struct {
	ID       string
	Title    string
	Children []*SidebarItem
	Data     interface{} // Arbitrary data associated with the item
	expanded bool
	level    int
}

// Sidebar displays a collapsible tree or list view
type Sidebar struct {
	width     int
	height    int
	items     []*SidebarItem
	flatItems []*SidebarItem // Flattened view based on expansion state
	selected  int
	viewport  viewport.Model
	visible   bool
	title     string
	keymap    keymap.VimKeyMap
	filter    string
	treeMode  bool // true for tree, false for flat list
	focused   bool // Whether this sidebar has focus
}

// NewSidebar creates a new sidebar component
func NewSidebar(title string, km keymap.VimKeyMap) *Sidebar {
	vp := viewport.New(0, 0)
	return &Sidebar{
		title:    title,
		keymap:   km,
		visible:  true,
		treeMode: true,
		selected: 0,
		viewport: vp,
		items:    make([]*SidebarItem, 0),
	}
}

// Init implements tea.Model
func (s *Sidebar) Init() tea.Cmd {
	return nil
}

// Update implements tea.Model
func (s *Sidebar) Update(msg tea.Msg) (*Sidebar, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		return s.handleKeyPress(msg)
	case tea.WindowSizeMsg:
		s.width = msg.Width
		s.height = msg.Height
		s.viewport.Width = s.width - 2   // Account for borders
		s.viewport.Height = s.height - 3 // Account for title and borders
	case tea.MouseMsg:
		// Handle mouse wheel scrolling
		if msg.Action == tea.MouseActionPress {
			switch msg.Button {
			case tea.MouseButtonWheelUp:
				s.viewport.ScrollUp(3)
				return s, nil
			case tea.MouseButtonWheelDown:
				s.viewport.ScrollDown(3)
				return s, nil
			}
		}
	}

	var cmd tea.Cmd
	s.viewport, cmd = s.viewport.Update(msg)
	return s, cmd
}

// View implements tea.Model
func (s *Sidebar) View() string {
	if !s.visible {
		return ""
	}

	// Render title
	titleBar := styles.TitleStyle.Width(s.width - 2).Render(s.title)

	// Render items
	s.rebuildFlatItems()
	content := s.renderItems()
	s.viewport.SetContent(content)

	// Combine title and content
	main := lipgloss.JoinVertical(lipgloss.Left, titleBar, s.viewport.View())

	// Add border with focus indication
	borderStyle := styles.BorderStyle
	if s.focused {
		borderStyle = borderStyle.BorderForeground(styles.DefaultTheme.Primary)
	}

	return borderStyle.
		Width(s.width - 2).
		Height(s.height - 2).
		Render(main)
}

func (s *Sidebar) handleKeyPress(msg tea.KeyMsg) (*Sidebar, tea.Cmd) {
	switch {
	case key.Matches(msg, s.keymap.Up):
		s.selectPrevious()
		s.scrollToSelected()
	case key.Matches(msg, s.keymap.Down):
		s.selectNext()
		s.scrollToSelected()
	case key.Matches(msg, s.keymap.Right):
		// Expand current item if it has children
		if s.selected < len(s.flatItems) {
			item := s.flatItems[s.selected]
			if len(item.Children) > 0 {
				item.expanded = true
			}
		}
	case key.Matches(msg, s.keymap.Left):
		// Collapse current item or move to parent
		if s.selected < len(s.flatItems) {
			item := s.flatItems[s.selected]
			if item.expanded {
				item.expanded = false
			} else {
				// Find parent
				s.selectParent(item)
			}
		}
	case msg.String() == " ":
		// Toggle expand/collapse with space bar
		if s.selected < len(s.flatItems) {
			item := s.flatItems[s.selected]
			if len(item.Children) > 0 {
				item.expanded = !item.expanded
			}
		}
	case key.Matches(msg, s.keymap.Select):
		// Return selected event
		return s, s.emitSelectEvent()
	}

	return s, nil
}

func (s *Sidebar) renderItems() string {
	if len(s.flatItems) == 0 {
		return styles.MutedStyle.Render("No items")
	}

	var lines []string
	for i, item := range s.flatItems {
		line := s.renderItem(item, i == s.selected)
		lines = append(lines, line)
	}

	return strings.Join(lines, "\n")
}

func (s *Sidebar) renderItem(item *SidebarItem, selected bool) string {
	indent := strings.Repeat("  ", item.level)

	var icon string
	if len(item.Children) > 0 {
		if item.expanded {
			icon = "▼ "
		} else {
			icon = "▶ "
		}
	} else {
		icon = "  "
	}

	text := indent + icon + item.Title

	// Calculate available width for text (account for borders and padding)
	maxWidth := s.width - 4
	if len(text) > maxWidth {
		// Truncate and add ellipsis
		text = text[:maxWidth-3] + "..."
	}

	// Create style with fixed width to prevent wrapping
	style := styles.NormalItemStyle.Width(maxWidth)
	if selected {
		style = styles.SelectedItemStyle.Width(maxWidth)
	}

	return style.Render(text)
}

func (s *Sidebar) rebuildFlatItems() {
	s.flatItems = make([]*SidebarItem, 0)
	for _, item := range s.items {
		s.flattenItem(item, 0)
	}
}

func (s *Sidebar) flattenItem(item *SidebarItem, level int) {
	item.level = level

	// Apply filter if set
	if s.filter == "" || strings.Contains(strings.ToLower(item.Title), strings.ToLower(s.filter)) {
		s.flatItems = append(s.flatItems, item)
	}

	// Add children if expanded or in flat list mode
	if (item.expanded || !s.treeMode) && len(item.Children) > 0 {
		for _, child := range item.Children {
			s.flattenItem(child, level+1)
		}
	}
}

func (s *Sidebar) selectNext() {
	if len(s.flatItems) == 0 {
		return
	}
	s.selected++
	if s.selected >= len(s.flatItems) {
		s.selected = len(s.flatItems) - 1
	}
}

func (s *Sidebar) selectPrevious() {
	if len(s.flatItems) == 0 {
		return
	}
	s.selected--
	if s.selected < 0 {
		s.selected = 0
	}
}

func (s *Sidebar) selectParent(item *SidebarItem) {
	if item.level == 0 {
		return
	}

	// Find the parent by looking backward for an item with level-1
	targetLevel := item.level - 1
	for i := s.selected - 1; i >= 0; i-- {
		if s.flatItems[i].level == targetLevel {
			s.selected = i
			break
		}
	}
}

func (s *Sidebar) scrollToSelected() {
	// Calculate the line position of the selected item
	lineHeight := 1
	selectedPos := s.selected * lineHeight

	// Scroll viewport to show selected item
	if selectedPos < s.viewport.YOffset {
		s.viewport.YOffset = selectedPos
	} else if selectedPos >= s.viewport.YOffset+s.viewport.Height {
		s.viewport.YOffset = selectedPos - s.viewport.Height + 1
	}
}

func (s *Sidebar) emitSelectEvent() tea.Cmd {
	if s.selected < len(s.flatItems) {
		item := s.flatItems[s.selected]
		return func() tea.Msg {
			return SidebarSelectMsg{Item: item}
		}
	}
	return nil
}

// SidebarSelectMsg is sent when an item is selected
type SidebarSelectMsg struct {
	Item *SidebarItem
}

// Public API

// SetItems sets the sidebar items (for tree mode)
func (s *Sidebar) SetItems(items []*SidebarItem) {
	s.items = items
	s.selected = 0
	s.rebuildFlatItems()
}

// GetItems returns the current sidebar items
func (s *Sidebar) GetItems() []*SidebarItem {
	return s.items
}

// AddItem adds a single item to the sidebar
func (s *Sidebar) AddItem(item *SidebarItem) {
	s.items = append(s.items, item)
	s.rebuildFlatItems()
}

// Toggle toggles sidebar visibility
func (s *Sidebar) Toggle() {
	s.visible = !s.visible
}

// SetVisible sets sidebar visibility
func (s *Sidebar) SetVisible(visible bool) {
	s.visible = visible
}

// IsVisible returns whether the sidebar is visible
func (s *Sidebar) IsVisible() bool {
	return s.visible
}

// SetFilter sets a filter string for items
func (s *Sidebar) SetFilter(filter string) {
	s.filter = filter
	s.selected = 0
	s.rebuildFlatItems()
}

// GetSelected returns the currently selected item
func (s *Sidebar) GetSelected() *SidebarItem {
	if s.selected < len(s.flatItems) {
		return s.flatItems[s.selected]
	}
	return nil
}

// SetWidth sets the sidebar width
func (s *Sidebar) SetWidth(width int) {
	s.width = width
	s.viewport.Width = width - 2
}

// SetHeight sets the sidebar height
func (s *Sidebar) SetHeight(height int) {
	s.height = height
	s.viewport.Height = height - 3
}

// GetWidth returns the current width
func (s *Sidebar) GetWidth() int {
	return s.width
}

// SetTreeMode enables or disables tree mode
func (s *Sidebar) SetTreeMode(enabled bool) {
	s.treeMode = enabled
	s.rebuildFlatItems()
}

// SetExpanded sets the expanded state of a sidebar item
func (item *SidebarItem) SetExpanded(expanded bool) {
	item.expanded = expanded
}

// SetFocused sets whether this sidebar has focus
func (s *Sidebar) SetFocused(focused bool) {
	s.focused = focused
}

// IsFocused returns whether this sidebar has focus
func (s *Sidebar) IsFocused() bool {
	return s.focused
}
