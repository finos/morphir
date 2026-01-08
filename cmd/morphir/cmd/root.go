package cmd

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/finos/morphir/cmd/morphir/internal/ui"
	"github.com/finos/morphir/pkg/config"
	"github.com/spf13/cobra"
)

// Version information - these are set via ldflags during build
var (
	Version   = "dev"
	GitCommit = "unknown"
	BuildDate = "unknown"
)

// Global configuration loaded at startup
var (
	cfg        config.Config
	cfgResult  config.LoadResult
	cfgLoaded  bool
	cfgLoadErr error
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
	cobra.OnInitialize(initConfig)

	rootCmd.AddCommand(workspaceCmd)
	rootCmd.AddCommand(projectCmd)
	rootCmd.AddCommand(taskCmd)
	rootCmd.AddCommand(validateCmd)
	rootCmd.AddCommand(versionCmd)
	rootCmd.AddCommand(aboutCmd)
	rootCmd.AddCommand(configCmd)
	rootCmd.AddCommand(witCmd)
	rootCmd.AddCommand(golangCmd)
	// Note: Cobra automatically provides a built-in 'help' command,
	// so we don't need to register our custom helpCmd

	// Add version flag
	rootCmd.Flags().BoolP("version", "v", false, "version for morphir")
}

// initConfig loads the configuration from all sources.
// This is called by cobra.OnInitialize before any command runs.
func initConfig() {
	// Get current working directory for project config discovery
	workDir, err := os.Getwd()
	if err != nil {
		cfgLoadErr = fmt.Errorf("failed to get working directory: %w", err)
		return
	}

	// Load configuration with working directory context
	cfgResult, cfgLoadErr = config.LoadWithDetails(config.WithWorkDir(workDir))
	if cfgLoadErr != nil {
		return
	}

	cfg = cfgResult.Config()
	cfgLoaded = true
}

// GetConfig returns the loaded configuration.
// Returns an error if configuration failed to load.
func GetConfig() (config.Config, error) {
	if cfgLoadErr != nil {
		return config.Config{}, cfgLoadErr
	}
	if !cfgLoaded {
		return config.Default(), nil
	}
	return cfg, nil
}

// GetConfigResult returns the full load result including source information.
func GetConfigResult() (config.LoadResult, error) {
	if cfgLoadErr != nil {
		return config.LoadResult{}, cfgLoadErr
	}
	return cfgResult, nil
}
