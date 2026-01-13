package cmd

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/finos/morphir/cmd/morphir/internal/ui"
	"github.com/finos/morphir/pkg/config"
	"github.com/finos/morphir/pkg/logging"
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

// Logging flags and state
var (
	logLevel   string // Log level from --log-level flag
	verbose    bool   // Verbose mode (-v/--verbose)
	quiet      bool   // Quiet mode (-q/--quiet)
	logFile    string // Log file from --log-file flag
	logger     logging.Logger
	loggerInit bool
)

var rootCmd = &cobra.Command{
	Use:   "morphir",
	Short: "Morphir CLI - A tool for working with Morphir IR",
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
	cobra.OnInitialize(initConfig, initLogging)

	rootCmd.AddCommand(workspaceCmd)
	rootCmd.AddCommand(projectCmd)
	rootCmd.AddCommand(taskCmd)
	rootCmd.AddCommand(validateCmd)
	rootCmd.AddCommand(versionCmd)
	rootCmd.AddCommand(aboutCmd)
	rootCmd.AddCommand(configCmd)
	rootCmd.AddCommand(planCmd)
	rootCmd.AddCommand(witCmd)
	rootCmd.AddCommand(golangCmd)
	// Note: Cobra automatically provides a built-in 'help' command,
	// so we don't need to register our custom helpCmd

	// Add version flag (no short flag - -v reserved for verbose)
	rootCmd.Flags().Bool("version", false, "version for morphir")

	// Add global logging flags
	rootCmd.PersistentFlags().StringVar(&logLevel, "log-level", "",
		"Log level (trace, debug, info, warn, error)")
	rootCmd.PersistentFlags().BoolVarP(&verbose, "verbose", "v", false,
		"Enable verbose output (debug level)")
	rootCmd.PersistentFlags().BoolVarP(&quiet, "quiet", "q", false,
		"Suppress non-error output (error level only)")
	rootCmd.PersistentFlags().StringVar(&logFile, "log-file", "",
		"Write logs to file (in .morphir/logs/ if relative)")
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

// initLogging initializes the logger from flags, environment, and configuration.
// Priority: CLI flags > Environment variables > Config file > Defaults
func initLogging() {
	// Resolve log level: flags > env > config > default
	level := resolveLogLevel()

	// Resolve log file: flags > env > config > default (empty = no file)
	file := resolveLogFile()

	// Determine workspace root for relative log file paths
	workspaceRoot, _ := os.Getwd()

	// Determine format from config (flags don't override format for simplicity)
	format := "text"
	if cfgLoaded {
		format = cfg.Logging().Format()
	}
	if envFormat := os.Getenv("MORPHIR_LOGGING_FORMAT"); envFormat != "" {
		format = envFormat
	}

	// Check for NO_COLOR environment variable
	noColor := os.Getenv("NO_COLOR") != ""

	// Build logger options
	opts := []logging.Option{
		logging.WithLevel(level),
		logging.WithFormat(format),
	}
	if file != "" {
		opts = append(opts, logging.WithFile(file, workspaceRoot))
	}
	if noColor {
		opts = append(opts, logging.WithNoColor())
	}

	// Create the logger
	var err error
	logger, err = logging.New(opts...)
	if err != nil {
		// Fall back to noop logger if configuration is invalid
		logger = logging.Noop()
		fmt.Fprintf(os.Stderr, "Warning: failed to initialize logger: %v\n", err)
	}

	// Set as global logger for any log.* calls
	logger.SetAsStdLogger()
	loggerInit = true
}

// resolveLogLevel determines the log level from flags, env, config.
func resolveLogLevel() string {
	// CLI flags take precedence
	if quiet {
		return "error"
	}
	if verbose {
		return "debug"
	}
	if logLevel != "" {
		return logLevel
	}

	// Check environment variable
	if envLevel := os.Getenv("MORPHIR_LOGGING_LEVEL"); envLevel != "" {
		return envLevel
	}

	// Fall back to config
	if cfgLoaded {
		return cfg.Logging().Level()
	}

	// Default
	return "info"
}

// resolveLogFile determines the log file from flags, env, config.
func resolveLogFile() string {
	// CLI flags take precedence
	if logFile != "" {
		return logFile
	}

	// Check environment variable
	if envFile := os.Getenv("MORPHIR_LOGGING_FILE"); envFile != "" {
		return envFile
	}

	// Fall back to config
	if cfgLoaded {
		return cfg.Logging().File()
	}

	// Default: no file logging
	return ""
}

// GetLogger returns the initialized logger.
// If logging is not yet initialized, returns a noop logger.
func GetLogger() logging.Logger {
	if !loggerInit {
		return logging.Noop()
	}
	return logger
}
