package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"time"

	"github.com/finos/morphir/pkg/tooling/decorations"
	"github.com/finos/morphir/pkg/tooling/workspace"
	"github.com/spf13/cobra"
)

var decorationTypeCmd = &cobra.Command{
	Use:   "type",
	Short: "Manage decoration types",
	Long:  `Commands for managing registered decoration types in the registry.`,
}

var (
	decorationTypeRegisterIR          string
	decorationTypeRegisterEntryPoint  string
	decorationTypeRegisterDisplayName string
	decorationTypeRegisterDescription string
	decorationTypeRegisterGlobal      bool
	decorationTypeListJSON            bool
	decorationTypeListSource          string
)

var decorationTypeRegisterCmd = &cobra.Command{
	Use:   "register <type-id>",
	Short: "Register a decoration type in the registry",
	Long: `Register a decoration type in the registry for reuse across projects.

The type-id is a unique identifier for the decoration type (e.g., "documentation", "tags").

Use --global to register in the global registry (~/.morphir/decorations/registry.json)
instead of the workspace registry (.morphir/decorations/registry.json).`,
	Args: cobra.ExactArgs(1),
	RunE: runDecorationTypeRegister,
}

var decorationTypeListCmd = &cobra.Command{
	Use:   "list",
	Short: "List registered decoration types",
	Long: `List all registered decoration types from workspace, global, and system registries.

Use --source to filter by source (workspace, global, system, or all).
Use --json for machine-readable output.`,
	RunE: runDecorationTypeList,
}

var decorationTypeShowCmd = &cobra.Command{
	Use:   "show <type-id>",
	Short: "Show details about a decoration type",
	Long:  `Show detailed information about a registered decoration type.`,
	Args:  cobra.ExactArgs(1),
	RunE:  runDecorationTypeShow,
}

var decorationTypeUnregisterCmd = &cobra.Command{
	Use:   "unregister <type-id>",
	Short: "Unregister a decoration type",
	Long: `Remove a decoration type from the registry.

Use --global to unregister from the global registry instead of workspace.`,
	Args: cobra.ExactArgs(1),
	RunE: runDecorationTypeUnregister,
}

func init() {
	decorationCmd.AddCommand(decorationTypeCmd)

	decorationTypeCmd.AddCommand(decorationTypeRegisterCmd)
	decorationTypeRegisterCmd.Flags().StringVarP(&decorationTypeRegisterIR, "ir", "i", "", "Path to decoration IR file (required)")
	decorationTypeRegisterCmd.Flags().StringVarP(&decorationTypeRegisterEntryPoint, "entry-point", "e", "", "Entry point FQName (required)")
	decorationTypeRegisterCmd.Flags().StringVar(&decorationTypeRegisterDisplayName, "display-name", "", "Display name for the decoration (required)")
	decorationTypeRegisterCmd.Flags().StringVar(&decorationTypeRegisterDescription, "description", "", "Description of the decoration")
	decorationTypeRegisterCmd.Flags().BoolVar(&decorationTypeRegisterGlobal, "global", false, "Register in global registry instead of workspace")
	_ = decorationTypeRegisterCmd.MarkFlagRequired("ir")
	_ = decorationTypeRegisterCmd.MarkFlagRequired("entry-point")
	_ = decorationTypeRegisterCmd.MarkFlagRequired("display-name")

	decorationTypeCmd.AddCommand(decorationTypeListCmd)
	decorationTypeListCmd.Flags().BoolVar(&decorationTypeListJSON, "json", false, "Output as JSON")
	decorationTypeListCmd.Flags().StringVar(&decorationTypeListSource, "source", "all", "Filter by source (workspace, global, system, all)")

	decorationTypeCmd.AddCommand(decorationTypeShowCmd)
	decorationTypeCmd.AddCommand(decorationTypeUnregisterCmd)
	decorationTypeUnregisterCmd.Flags().BoolVar(&decorationTypeRegisterGlobal, "global", false, "Unregister from global registry instead of workspace")
}

func runDecorationTypeRegister(cmd *cobra.Command, args []string) error {
	typeID := args[0]

	// Validate inputs
	if decorationTypeRegisterIR == "" {
		return fmt.Errorf("--ir is required")
	}
	if decorationTypeRegisterEntryPoint == "" {
		return fmt.Errorf("--entry-point is required")
	}
	if decorationTypeRegisterDisplayName == "" {
		return fmt.Errorf("--display-name is required")
	}

	// Make IR path absolute
	irPath, err := filepath.Abs(decorationTypeRegisterIR)
	if err != nil {
		return fmt.Errorf("resolve IR path: %w", err)
	}

	// Validate the decoration type
	decType := decorations.DecorationType{
		ID:           typeID,
		DisplayName:  decorationTypeRegisterDisplayName,
		Description:  decorationTypeRegisterDescription,
		IRPath:       irPath,
		EntryPoint:   decorationTypeRegisterEntryPoint,
		RegisteredAt: time.Now(),
	}

	if decorationTypeRegisterGlobal {
		decType.Source = "global"
	} else {
		decType.Source = "workspace"
	}

	// Validate IR file and entry point
	if err := decorations.ValidateDecorationType(decType); err != nil {
		return fmt.Errorf("validation failed: %w", err)
	}

	// Determine registry path
	var registryPath string
	if decorationTypeRegisterGlobal {
		homeDir, err := os.UserHomeDir()
		if err != nil {
			return fmt.Errorf("get home directory: %w", err)
		}
		registryPath = filepath.Join(homeDir, ".morphir", "decorations", "registry.json")
	} else {
		// Use workspace root
		lw, err := workspace.LoadFromCwd()
		if err != nil {
			return fmt.Errorf("load workspace: %w", err)
		}
		workspaceRoot := lw.Config().Workspace().Root()
		registryPath = filepath.Join(workspaceRoot, ".morphir", "decorations", "registry.json")
	}

	// Load existing registry
	registry, err := decorations.LoadTypeRegistry(registryPath)
	if err != nil {
		return fmt.Errorf("load registry: %w", err)
	}

	// Register the type
	registry.Register(decType)

	// Save registry
	if err := registry.Save(registryPath); err != nil {
		return fmt.Errorf("save registry: %w", err)
	}

	fmt.Fprintf(cmd.OutOrStdout(), "✓ Registered decoration type %q\n", typeID)
	fmt.Fprintf(cmd.OutOrStdout(), "  Display Name: %s\n", decorationTypeRegisterDisplayName)
	fmt.Fprintf(cmd.OutOrStdout(), "  Entry Point: %s\n", decorationTypeRegisterEntryPoint)
	fmt.Fprintf(cmd.OutOrStdout(), "  IR File: %s\n", irPath)
	fmt.Fprintf(cmd.OutOrStdout(), "  Registry: %s\n", registryPath)

	return nil
}

func runDecorationTypeList(cmd *cobra.Command, args []string) error {
	// Get workspace root
	lw, err := workspace.LoadFromCwd()
	if err != nil {
		return fmt.Errorf("load workspace: %w", err)
	}
	workspaceRoot := lw.Config().Workspace().Root()

	// Get registry paths
	workspacePath, globalPath, systemPath := decorations.GetRegistryPaths(workspaceRoot)

	// Load merged registry
	registry, err := decorations.LoadMergedTypeRegistry(workspacePath, globalPath, systemPath)
	if err != nil {
		return fmt.Errorf("load registry: %w", err)
	}

	// Filter by source if requested
	var types []decorations.DecorationType
	if decorationTypeListSource == "all" || decorationTypeListSource == "" {
		types = registry.List()
	} else {
		types = registry.ListBySource(decorationTypeListSource)
	}

	// Sort by ID
	sort.Slice(types, func(i, j int) bool {
		return types[i].ID < types[j].ID
	})

	if decorationTypeListJSON {
		return outputDecorationTypeListJSON(cmd, types)
	}

	return outputDecorationTypeListText(cmd, types)
}

func outputDecorationTypeListJSON(cmd *cobra.Command, types []decorations.DecorationType) error {
	encoder := json.NewEncoder(cmd.OutOrStdout())
	encoder.SetIndent("", "  ")
	return encoder.Encode(types)
}

func outputDecorationTypeListText(cmd *cobra.Command, types []decorations.DecorationType) error {
	if len(types) == 0 {
		fmt.Fprintf(cmd.OutOrStdout(), "No decoration types registered.\n")
		return nil
	}

	fmt.Fprintf(cmd.OutOrStdout(), "Registered Decoration Types (%d):\n\n", len(types))
	for _, decType := range types {
		fmt.Fprintf(cmd.OutOrStdout(), "  %s\n", decType.ID)
		fmt.Fprintf(cmd.OutOrStdout(), "    Display Name: %s\n", decType.DisplayName)
		if decType.Description != "" {
			fmt.Fprintf(cmd.OutOrStdout(), "    Description: %s\n", decType.Description)
		}
		fmt.Fprintf(cmd.OutOrStdout(), "    Entry Point: %s\n", decType.EntryPoint)
		fmt.Fprintf(cmd.OutOrStdout(), "    IR File: %s\n", decType.IRPath)
		fmt.Fprintf(cmd.OutOrStdout(), "    Source: %s\n", decType.Source)
		fmt.Fprintf(cmd.OutOrStdout(), "\n")
	}

	return nil
}

func runDecorationTypeShow(cmd *cobra.Command, args []string) error {
	typeID := args[0]

	// Get workspace root
	lw, err := workspace.LoadFromCwd()
	if err != nil {
		return fmt.Errorf("load workspace: %w", err)
	}
	workspaceRoot := lw.Config().Workspace().Root()

	// Get registry paths
	workspacePath, globalPath, systemPath := decorations.GetRegistryPaths(workspaceRoot)

	// Load merged registry
	registry, err := decorations.LoadMergedTypeRegistry(workspacePath, globalPath, systemPath)
	if err != nil {
		return fmt.Errorf("load registry: %w", err)
	}

	decType, found := registry.Get(typeID)
	if !found {
		return fmt.Errorf("decoration type %q not found", typeID)
	}

	if decorationTypeListJSON {
		encoder := json.NewEncoder(cmd.OutOrStdout())
		encoder.SetIndent("", "  ")
		return encoder.Encode(decType)
	}

	fmt.Fprintf(cmd.OutOrStdout(), "Decoration Type: %s\n\n", decType.ID)
	fmt.Fprintf(cmd.OutOrStdout(), "  Display Name: %s\n", decType.DisplayName)
	if decType.Description != "" {
		fmt.Fprintf(cmd.OutOrStdout(), "  Description: %s\n", decType.Description)
	}
	fmt.Fprintf(cmd.OutOrStdout(), "  Entry Point: %s\n", decType.EntryPoint)
	fmt.Fprintf(cmd.OutOrStdout(), "  IR File: %s\n", decType.IRPath)
	fmt.Fprintf(cmd.OutOrStdout(), "  Source: %s\n", decType.Source)
	fmt.Fprintf(cmd.OutOrStdout(), "  Registered At: %s\n", decType.RegisteredAt.Format(time.RFC3339))

	return nil
}

func runDecorationTypeUnregister(cmd *cobra.Command, args []string) error {
	typeID := args[0]

	// Determine registry path
	var registryPath string
	if decorationTypeRegisterGlobal {
		homeDir, err := os.UserHomeDir()
		if err != nil {
			return fmt.Errorf("get home directory: %w", err)
		}
		registryPath = filepath.Join(homeDir, ".morphir", "decorations", "registry.json")
	} else {
		// Use workspace root
		lw, err := workspace.LoadFromCwd()
		if err != nil {
			return fmt.Errorf("load workspace: %w", err)
		}
		workspaceRoot := lw.Config().Workspace().Root()
		registryPath = filepath.Join(workspaceRoot, ".morphir", "decorations", "registry.json")
	}

	// Load existing registry
	registry, err := decorations.LoadTypeRegistry(registryPath)
	if err != nil {
		return fmt.Errorf("load registry: %w", err)
	}

	// Check if type exists
	if !registry.Has(typeID) {
		return fmt.Errorf("decoration type %q not found in registry", typeID)
	}

	// Unregister
	registry.Unregister(typeID)

	// Save registry
	if err := registry.Save(registryPath); err != nil {
		return fmt.Errorf("save registry: %w", err)
	}

	fmt.Fprintf(cmd.OutOrStdout(), "✓ Unregistered decoration type %q\n", typeID)

	return nil
}
