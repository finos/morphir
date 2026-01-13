package cmd

import (
	"encoding/json"
	"fmt"
	"path/filepath"
	"strings"

	"github.com/charmbracelet/lipgloss/v2"
	"github.com/charmbracelet/lipgloss/v2/table"
	"github.com/finos/morphir/pkg/tooling/workspace"
	"github.com/spf13/cobra"
)

var projectCmd = &cobra.Command{
	Use:   "project",
	Short: "Manage Morphir projects",
	Long:  `Commands for managing Morphir projects within a workspace.`,
}

var (
	projectListJSON       bool
	projectListProperties string
)

var projectListCmd = &cobra.Command{
	Use:   "list",
	Short: "List projects in the workspace",
	Long: `List all projects in the current Morphir workspace.

By default, lists projects in a human-readable table format.
Use --json to output as JSON.

When using --json, you can optionally specify which properties to include:
  morphir project list --json --properties name,path,version

Available properties:
  - name: Project name
  - path: Absolute path to project directory
  - config_path: Path to the configuration file
  - config_format: Configuration format (toml or json)
  - source_directory: Source directory (relative)
  - exposed_modules: List of exposed modules
  - exposed_modules_count: Number of exposed modules
  - module_prefix: Module prefix for qualified names
  - version: Project version
  - is_root: Whether this is the root project`,
	RunE: runProjectList,
}

func runProjectList(cmd *cobra.Command, args []string) error {
	// Load workspace from current directory
	lw, err := workspace.LoadFromCwd()
	if err != nil {
		return fmt.Errorf("failed to load workspace: %w", err)
	}

	projects := lw.AllProjects()
	rootProject := lw.RootProject()

	if projectListJSON {
		return printProjectListJSON(projects, rootProject, projectListProperties)
	}

	return printProjectListTable(projects, rootProject, lw)
}

// printProjectListJSON outputs the project list as JSON.
// If properties is non-empty, only the specified properties are included.
func printProjectListJSON(projects []workspace.Project, rootProject *workspace.Project, properties string) error {
	// Parse requested properties
	var requestedProps []string
	if properties != "" {
		for _, p := range strings.Split(properties, ",") {
			requestedProps = append(requestedProps, strings.TrimSpace(p))
		}
	}

	output := make([]map[string]any, 0, len(projects))
	for _, p := range projects {
		isRoot := rootProject != nil && p.Path() == rootProject.Path()
		projectMap := buildProjectMap(p, isRoot, requestedProps)
		output = append(output, projectMap)
	}

	data, err := json.MarshalIndent(output, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal projects: %w", err)
	}
	fmt.Println(string(data))
	return nil
}

// buildProjectMap creates a map of project properties.
// If requestedProps is empty, all properties are included.
func buildProjectMap(p workspace.Project, isRoot bool, requestedProps []string) map[string]any {
	// All available properties
	allProps := map[string]any{
		"name":                  p.Name(),
		"path":                  p.Path(),
		"config_path":           p.ConfigPath(),
		"config_format":         p.ConfigFormat(),
		"source_directory":      p.SourceDirectory(),
		"exposed_modules":       p.ExposedModules(),
		"exposed_modules_count": len(p.ExposedModules()),
		"module_prefix":         p.ModulePrefix(),
		"version":               p.Version(),
		"is_root":               isRoot,
	}

	// If no specific properties requested, return all
	if len(requestedProps) == 0 {
		return allProps
	}

	// Filter to only requested properties
	result := make(map[string]any)
	for _, prop := range requestedProps {
		if val, ok := allProps[prop]; ok {
			result[prop] = val
		}
	}
	return result
}

// printProjectListTable outputs the project list in a formatted table.
func printProjectListTable(projects []workspace.Project, rootProject *workspace.Project, lw workspace.LoadedWorkspace) error {
	if len(projects) == 0 {
		fmt.Println("No projects found in workspace.")
		return nil
	}

	// Get workspace root for relative path display
	wsRoot := lw.Workspace().Root()

	// Define styles
	headerStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("12")). // Bright blue
		Padding(0, 1)

	cellStyle := lipgloss.NewStyle().
		Padding(0, 1)

	rootStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("10")). // Green
		Padding(0, 1)

	// Build table rows
	rows := make([][]string, 0, len(projects))
	for _, p := range projects {
		isRoot := rootProject != nil && p.Path() == rootProject.Path()

		// Show relative path from workspace root
		relPath, err := filepath.Rel(wsRoot, p.Path())
		if err != nil {
			relPath = p.Path()
		}

		// Format name with root indicator
		name := p.Name()
		if isRoot {
			name = name + " (root)"
		}

		// Format exposed modules count
		exposed := fmt.Sprintf("%d", len(p.ExposedModules()))

		// Format version
		version := p.Version()
		if version == "" {
			version = "-"
		}

		rows = append(rows, []string{
			name,
			relPath,
			p.ConfigFormat(),
			p.SourceDirectory(),
			exposed,
			version,
		})
	}

	// Create table
	t := table.New().
		Border(lipgloss.NormalBorder()).
		BorderStyle(lipgloss.NewStyle().Foreground(lipgloss.Color("240"))).
		Headers("NAME", "PATH", "FORMAT", "SOURCE", "MODULES", "VERSION").
		Rows(rows...).
		StyleFunc(func(row, col int) lipgloss.Style {
			if row == table.HeaderRow {
				return headerStyle
			}
			// Check if this is the root project row
			if rootProject != nil && row < len(projects) {
				p := projects[row]
				if p.Path() == rootProject.Path() {
					return rootStyle
				}
			}
			return cellStyle
		})

	fmt.Printf("Projects in workspace (%d total):\n\n", len(projects))
	fmt.Println(t)

	// Show any loading errors
	if errs := lw.Errors(); len(errs) > 0 {
		errorStyle := lipgloss.NewStyle().
			Foreground(lipgloss.Color("9")). // Red
			Bold(true)

		fmt.Println()
		fmt.Println(errorStyle.Render(fmt.Sprintf("Warning: %d project(s) failed to load:", len(errs))))
		for _, e := range errs {
			fmt.Printf("  - %s\n", e)
		}
	}

	return nil
}

func init() {
	projectCmd.AddCommand(projectListCmd)

	// Flags for project list
	projectListCmd.Flags().BoolVar(&projectListJSON, "json", false,
		"Output as JSON")
	projectListCmd.Flags().StringVar(&projectListProperties, "properties", "",
		"Comma-separated list of properties to include in JSON output")
}
