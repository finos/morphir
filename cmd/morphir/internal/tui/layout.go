package tui

import (
	"github.com/charmbracelet/lipgloss/v2"
	"github.com/finos/morphir/cmd/morphir/internal/tui/components"
	"github.com/finos/morphir/cmd/morphir/internal/tui/styles"
)

// Layout manages the positioning and sizing of TUI components
type Layout struct {
	width           int
	height          int
	sidebarWidth    int
	minSidebarWidth int
	maxSidebarWidth int
	sidebarVisible  bool
}

// NewLayout creates a new layout manager
func NewLayout() *Layout {
	return &Layout{
		sidebarWidth:    30,
		minSidebarWidth: 20,
		maxSidebarWidth: 60,
		sidebarVisible:  true,
	}
}

// SetSize updates the total available size
func (l *Layout) SetSize(width, height int) {
	l.width = width
	l.height = height
}

// SetSidebarWidth sets the sidebar width (clamped to min/max)
func (l *Layout) SetSidebarWidth(width int) {
	if width < l.minSidebarWidth {
		width = l.minSidebarWidth
	}
	if width > l.maxSidebarWidth {
		width = l.maxSidebarWidth
	}
	l.sidebarWidth = width
}

// SetSidebarVisible sets whether the sidebar is visible
func (l *Layout) SetSidebarVisible(visible bool) {
	l.sidebarVisible = visible
}

// ToggleSidebar toggles sidebar visibility
func (l *Layout) ToggleSidebar() {
	l.sidebarVisible = !l.sidebarVisible
}

// IsSidebarVisible returns whether the sidebar is visible
func (l *Layout) IsSidebarVisible() bool {
	return l.sidebarVisible
}

// GetSidebarWidth returns the current sidebar width
func (l *Layout) GetSidebarWidth() int {
	if !l.sidebarVisible {
		return 0
	}
	return l.sidebarWidth
}

// GetViewerWidth returns the available width for the viewer
func (l *Layout) GetViewerWidth() int {
	if !l.sidebarVisible {
		return l.width
	}
	return l.width - l.sidebarWidth - 1 // -1 for separator
}

// GetContentHeight returns the height available for content (excluding status bar)
func (l *Layout) GetContentHeight() int {
	return l.height - 1 // -1 for status bar
}

// CalculateDimensions returns the dimensions for all components
func (l *Layout) CalculateDimensions() LayoutDimensions {
	contentHeight := l.GetContentHeight()

	return LayoutDimensions{
		SidebarWidth:   l.GetSidebarWidth(),
		SidebarHeight:  contentHeight,
		ViewerWidth:    l.GetViewerWidth(),
		ViewerHeight:   contentHeight,
		StatusBarWidth: l.width,
		SidebarVisible: l.sidebarVisible,
	}
}

// LayoutDimensions holds the calculated dimensions for all components
type LayoutDimensions struct {
	SidebarWidth   int
	SidebarHeight  int
	ViewerWidth    int
	ViewerHeight   int
	StatusBarWidth int
	SidebarVisible bool
}

// ApplyToComponents applies the layout dimensions to the given components
func (d *LayoutDimensions) ApplyToComponents(sidebar *components.Sidebar, viewer *components.Viewer, statusBar *components.StatusBar) {
	if d.SidebarVisible {
		sidebar.SetVisible(true)
		sidebar.SetWidth(d.SidebarWidth)
		sidebar.SetHeight(d.SidebarHeight)
	} else {
		sidebar.SetVisible(false)
	}

	viewer.SetWidth(d.ViewerWidth)
	viewer.SetHeight(d.ViewerHeight)

	statusBar.SetWidth(d.StatusBarWidth)
}

// RenderLayout renders the components in a horizontal layout
func RenderLayout(sidebar *components.Sidebar, viewer *components.Viewer, statusBar *components.StatusBar, dims LayoutDimensions) string {
	var mainContent string

	if dims.SidebarVisible {
		// Render sidebar and viewer side by side
		sidebarView := sidebar.View()
		viewerView := viewer.View()
		separator := styles.RenderSeparator(dims.SidebarHeight)

		mainContent = lipgloss.JoinHorizontal(
			lipgloss.Top,
			sidebarView,
			separator,
			viewerView,
		)
	} else {
		// Render viewer only (full width)
		mainContent = viewer.View()
	}

	// Add status bar at the bottom
	statusBarView := statusBar.View()

	return lipgloss.JoinVertical(
		lipgloss.Left,
		mainContent,
		statusBarView,
	)
}

// IncreaseSidebarWidth increases the sidebar width by a delta
func (l *Layout) IncreaseSidebarWidth(delta int) {
	l.SetSidebarWidth(l.sidebarWidth + delta)
}

// DecreaseSidebarWidth decreases the sidebar width by a delta
func (l *Layout) DecreaseSidebarWidth(delta int) {
	l.SetSidebarWidth(l.sidebarWidth - delta)
}

// GetWidth returns the total width
func (l *Layout) GetWidth() int {
	return l.width
}

// GetHeight returns the total height
func (l *Layout) GetHeight() int {
	return l.height
}
