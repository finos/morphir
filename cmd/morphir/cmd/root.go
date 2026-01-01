package cmd

import (
	"fmt"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/finos/morphir-go/cmd/morphir/internal/ui"
	"github.com/spf13/cobra"
)

// Version information - these are set via ldflags during build
var (
	Version   = "dev"
	GitCommit = "unknown"
	BuildDate = "unknown"
)

var rootCmd = &cobra.Command{
	Use:     "morphir",
	Version: Version,
	Short:   "Morphir CLI - A tool for working with Morphir IR",
	Long: `Morphir is a CLI tool for working with Morphir IR (Intermediate Representation).
It provides commands for workspace management, model processing, and more.`,
	RunE: runRoot,
}

// Execute runs the root command
func Execute() error {
	return rootCmd.Execute()
}

// runRoot executes the root command, launching the Bubbletea TUI
// This is only called when no subcommand is provided (Cobra handles subcommands automatically)
func runRoot(cmd *cobra.Command, args []string) error {
	// Check if version flag was passed
	versionFlag, _ := cmd.Flags().GetBool("version")
	if versionFlag {
		fmt.Printf("morphir version %s\n", Version)
		fmt.Printf("  commit: %s\n", GitCommit)
		fmt.Printf("  built:  %s\n", BuildDate)
		return nil
	}

	return launchTUI()
}

// launchTUI starts the Bubbletea TUI application
func launchTUI() error {
	model := ui.NewModel()
	program := tea.NewProgram(model, tea.WithAltScreen())

	if _, err := program.Run(); err != nil {
		return fmt.Errorf("failed to run TUI: %w", err)
	}

	return nil
}

func init() {
	rootCmd.AddCommand(workspaceCmd)
	rootCmd.AddCommand(validateCmd)
	rootCmd.AddCommand(versionCmd)
	// Note: Cobra automatically provides a built-in 'help' command,
	// so we don't need to register our custom helpCmd

	// Add version flag
	rootCmd.Flags().BoolP("version", "v", false, "version for morphir")
}
