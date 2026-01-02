package cmd

import (
	"encoding/json"
	"fmt"

	"github.com/finos/morphir-go/pkg/config"
	"github.com/spf13/cobra"
)

var (
	configShowJSON bool
	configPathJSON bool
)

var configCmd = &cobra.Command{
	Use:   "config",
	Short: "Manage Morphir configuration",
	Long:  `Commands for viewing and managing Morphir configuration settings.`,
}

var configShowCmd = &cobra.Command{
	Use:   "show",
	Short: "Display the resolved configuration",
	Long: `Display the fully resolved configuration after merging all sources.

Configuration is loaded from multiple sources in order of priority:
1. Built-in defaults (lowest priority)
2. System configuration (/etc/morphir/morphir.toml)
3. Global user configuration (~/.config/morphir/morphir.toml)
4. Project configuration (morphir.toml in workspace root)
5. User override (.morphir/morphir.user.toml)
6. Environment variables (MORPHIR_* prefix, highest priority)`,
	RunE: runConfigShow,
}

var configPathCmd = &cobra.Command{
	Use:   "path",
	Short: "Show configuration file locations",
	Long:  `Display the paths where configuration files are searched and their status.`,
	RunE:  runConfigPath,
}

// runConfigShow displays the resolved configuration
func runConfigShow(cmd *cobra.Command, args []string) error {
	cfg, err := GetConfig()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	if configShowJSON {
		return printConfigJSON(cfg)
	}

	return printConfigText(cfg)
}

// printConfigJSON outputs configuration as JSON
func printConfigJSON(cfg config.Config) error {
	output := configToMap(cfg)
	data, err := json.MarshalIndent(output, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal config: %w", err)
	}
	fmt.Println(string(data))
	return nil
}

// configToMap converts a Config to a map for JSON serialization
func configToMap(cfg config.Config) map[string]any {
	return map[string]any{
		"morphir": map[string]any{
			"version": cfg.Morphir().Version(),
		},
		"workspace": map[string]any{
			"root":       cfg.Workspace().Root(),
			"output_dir": cfg.Workspace().OutputDir(),
		},
		"ir": map[string]any{
			"format_version": cfg.IR().FormatVersion(),
			"strict_mode":    cfg.IR().StrictMode(),
		},
		"codegen": map[string]any{
			"targets":       cfg.Codegen().Targets(),
			"template_dir":  cfg.Codegen().TemplateDir(),
			"output_format": cfg.Codegen().OutputFormat(),
		},
		"cache": map[string]any{
			"enabled":  cfg.Cache().Enabled(),
			"dir":      cfg.Cache().Dir(),
			"max_size": cfg.Cache().MaxSize(),
		},
		"logging": map[string]any{
			"level":  cfg.Logging().Level(),
			"format": cfg.Logging().Format(),
			"file":   cfg.Logging().File(),
		},
		"ui": map[string]any{
			"color":       cfg.UI().Color(),
			"interactive": cfg.UI().Interactive(),
			"theme":       cfg.UI().Theme(),
		},
	}
}

// printConfigText outputs configuration as human-readable text
func printConfigText(cfg config.Config) error {
	// Display morphir section
	fmt.Println("[morphir]")
	fmt.Printf("  version = %q\n", cfg.Morphir().Version())

	// Display workspace section
	fmt.Println("\n[workspace]")
	fmt.Printf("  root = %q\n", cfg.Workspace().Root())
	fmt.Printf("  output_dir = %q\n", cfg.Workspace().OutputDir())

	// Display ir section
	fmt.Println("\n[ir]")
	fmt.Printf("  format_version = %d\n", cfg.IR().FormatVersion())
	fmt.Printf("  strict_mode = %v\n", cfg.IR().StrictMode())

	// Display codegen section
	fmt.Println("\n[codegen]")
	fmt.Printf("  targets = %v\n", cfg.Codegen().Targets())
	fmt.Printf("  template_dir = %q\n", cfg.Codegen().TemplateDir())
	fmt.Printf("  output_format = %q\n", cfg.Codegen().OutputFormat())

	// Display cache section
	fmt.Println("\n[cache]")
	fmt.Printf("  enabled = %v\n", cfg.Cache().Enabled())
	fmt.Printf("  dir = %q\n", cfg.Cache().Dir())
	fmt.Printf("  max_size = %d\n", cfg.Cache().MaxSize())

	// Display logging section
	fmt.Println("\n[logging]")
	fmt.Printf("  level = %q\n", cfg.Logging().Level())
	fmt.Printf("  format = %q\n", cfg.Logging().Format())
	fmt.Printf("  file = %q\n", cfg.Logging().File())

	// Display ui section
	fmt.Println("\n[ui]")
	fmt.Printf("  color = %v\n", cfg.UI().Color())
	fmt.Printf("  interactive = %v\n", cfg.UI().Interactive())
	fmt.Printf("  theme = %q\n", cfg.UI().Theme())

	return nil
}

// runConfigPath displays configuration file locations
func runConfigPath(cmd *cobra.Command, args []string) error {
	result, err := GetConfigResult()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	if configPathJSON {
		return printPathJSON(result)
	}

	return printPathText(result)
}

// printPathJSON outputs configuration sources as JSON
func printPathJSON(result config.LoadResult) error {
	sources := result.Sources()
	output := make([]map[string]any, len(sources))

	for i, src := range sources {
		entry := map[string]any{
			"name":     src.Name(),
			"path":     src.Path(),
			"priority": src.Priority(),
			"loaded":   src.Loaded(),
		}
		if src.Error() != nil {
			entry["error"] = src.Error().Error()
		}
		output[i] = entry
	}

	data, err := json.MarshalIndent(output, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal sources: %w", err)
	}
	fmt.Println(string(data))
	return nil
}

// printPathText outputs configuration sources as human-readable text
func printPathText(result config.LoadResult) error {
	fmt.Println("Configuration sources (in priority order):")
	fmt.Println()

	sources := result.Sources()
	for _, src := range sources {
		status := "not found"
		if src.Loaded() {
			status = "loaded"
		} else if src.Error() != nil {
			status = fmt.Sprintf("error: %v", src.Error())
		}

		fmt.Printf("  [%s] %s\n", statusIcon(src.Loaded()), src.Name())
		fmt.Printf("      Path: %s\n", src.Path())
		fmt.Printf("      Status: %s\n", status)
		fmt.Printf("      Priority: %d\n\n", src.Priority())
	}

	return nil
}

// statusIcon returns a checkmark or X based on loaded status
func statusIcon(loaded bool) string {
	if loaded {
		return "✓"
	}
	return "✗"
}

func init() {
	configShowCmd.Flags().BoolVar(&configShowJSON, "json", false, "Output as JSON")
	configPathCmd.Flags().BoolVar(&configPathJSON, "json", false, "Output as JSON")

	configCmd.AddCommand(configShowCmd)
	configCmd.AddCommand(configPathCmd)
}
