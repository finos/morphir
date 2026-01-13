package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/BurntSushi/toml"
	ir "github.com/finos/morphir/pkg/models/ir"
	"github.com/finos/morphir/pkg/tooling/decorations"
	"github.com/finos/morphir/pkg/tooling/workspace"
	"github.com/spf13/cobra"
)

var (
	decorationSetupIR              string
	decorationSetupEntryPoint      string
	decorationSetupStorageLocation string
	decorationSetupID              string
	decorationSetupDisplayName     string
	decorationSetupType            string
)

var decorationSetupCmd = &cobra.Command{
	Use:   "setup [decoration-id]",
	Short: "Set up a decoration in the project configuration",
	Long: `Set up a decoration configuration in morphir.json or morphir.toml.

This command:
  - Reads the decoration IR file to detect available types
  - Adds decoration configuration to the project config file
  - Creates an empty decoration values file if it doesn't exist

You can either:
  - Use a registered type: --type <type-id> (recommended)
  - Specify directly: -i <ir-path> -e <entry-point> (backward compatible)

The decoration-id is used as the internal identifier for the decoration.
If not provided, it will be derived from the decoration IR package name.

Examples:
  # Using a registered type
  morphir decoration setup myDecoration --type documentation

  # Using direct paths (backward compatible)
  morphir decoration setup myDecoration -i decorations/morphir-ir.json -e "My.Decoration:Module:Type"`,
	Args: cobra.MaximumNArgs(1),
	RunE: runDecorationSetup,
}

func init() {
	decorationCmd.AddCommand(decorationSetupCmd)
	decorationSetupCmd.Flags().StringVar(&decorationSetupType, "type", "", "Use a registered decoration type (alternative to -i/-e)")
	decorationSetupCmd.Flags().StringVarP(&decorationSetupIR, "ir", "i", "", "Path to decoration IR file (required if --type not used)")
	decorationSetupCmd.Flags().StringVarP(&decorationSetupEntryPoint, "entry-point", "e", "", "Entry point FQName (required if --type not used)")
	decorationSetupCmd.Flags().StringVar(&decorationSetupStorageLocation, "storage-location", "", "Path to decoration values file (default: <decoration-id>-values.json)")
	decorationSetupCmd.Flags().StringVar(&decorationSetupDisplayName, "display-name", "", "Display name for the decoration (default: derived from decoration-id or type)")
}

func runDecorationSetup(cmd *cobra.Command, args []string) error {
	var irPath, entryPoint, displayName string

	// Check if using registered type or direct paths
	if decorationSetupType != "" {
		// Use registered type
		if decorationSetupIR != "" || decorationSetupEntryPoint != "" {
			return fmt.Errorf("cannot use --type with -i or -e flags")
		}

		// Load workspace to get registry paths
		lw, err := workspace.LoadFromCwd()
		if err != nil {
			return fmt.Errorf("load workspace: %w", err)
		}
		workspaceRoot := lw.Config().Workspace().Root()
		workspacePath, globalPath, systemPath := decorations.GetRegistryPaths(workspaceRoot)

		// Load merged registry
		registry, err := decorations.LoadMergedTypeRegistry(workspacePath, globalPath, systemPath)
		if err != nil {
			return fmt.Errorf("load type registry: %w", err)
		}

		// Get the registered type
		decType, found := registry.Get(decorationSetupType)
		if !found {
			return fmt.Errorf("decoration type %q not found in registry. Use 'morphir decoration type list' to see available types", decorationSetupType)
		}

		irPath = decType.IRPath
		entryPoint = decType.EntryPoint
		displayName = decType.DisplayName
	} else {
		// Use direct paths (backward compatible)
		if decorationSetupIR == "" {
			return fmt.Errorf("either --type or --ir is required")
		}
		if decorationSetupEntryPoint == "" {
			return fmt.Errorf("either --type or --entry-point is required")
		}

		irPath = decorationSetupIR
		entryPoint = decorationSetupEntryPoint
	}

	// Determine decoration ID
	decorationID := decorationSetupID
	if len(args) > 0 {
		decorationID = args[0]
	}
	if decorationID == "" {
		// Try to derive from IR file
		decIR, err := decorations.LoadDecorationIR(irPath)
		if err != nil {
			return fmt.Errorf("failed to load decoration IR: %w", err)
		}
		lib := decIR.Distribution().(ir.Library)
		pkgName := lib.PackageName()
		// Use last segment of package name as decoration ID
		names := pkgName.Parts()
		if len(names) > 0 {
			decorationID = names[len(names)-1].ToCamelCase()
		} else {
			return fmt.Errorf("decoration-id is required (could not derive from IR)")
		}
	}

	// Determine display name if not set from registry
	if displayName == "" {
		if decorationSetupDisplayName != "" {
			displayName = decorationSetupDisplayName
		} else {
			// Convert decorationID to title case (capitalize first letter)
			if len(decorationID) > 0 {
				displayName = strings.ToUpper(decorationID[:1]) + decorationID[1:]
			} else {
				displayName = decorationID
			}
		}
	}

	// Determine storage location
	storageLocation := decorationSetupStorageLocation
	if storageLocation == "" {
		storageLocation = decorationID + "-values.json"
	}

	// Load decoration IR to validate entry point
	decIR, err := decorations.LoadDecorationIR(irPath)
	if err != nil {
		return fmt.Errorf("failed to load decoration IR: %w", err)
	}

	// Validate entry point
	if err := decorations.ValidateEntryPoint(decIR, entryPoint); err != nil {
		return fmt.Errorf("invalid entry point: %w", err)
	}

	// Load workspace to find project config
	lw, err := workspace.LoadFromCwd()
	if err != nil {
		return fmt.Errorf("failed to load workspace: %w", err)
	}

	rootProject := lw.RootProject()
	if rootProject == nil {
		return fmt.Errorf("no root project found in workspace")
	}

	configPath := rootProject.ConfigPath()
	configFormat := rootProject.ConfigFormat()

	// Make IR path relative to project directory if possible
	workDir, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("failed to get working directory: %w", err)
	}
	projectDir := rootProject.Path()
	var relIRPath string
	if !filepath.IsAbs(irPath) {
		absIRPath := filepath.Join(workDir, irPath)
		relIRPath, err = filepath.Rel(projectDir, absIRPath)
		if err != nil || strings.HasPrefix(relIRPath, "..") {
			relIRPath = irPath // Fallback to original if relative path fails
		}
	} else {
		relIRPath, err = filepath.Rel(projectDir, irPath)
		if err != nil || strings.HasPrefix(relIRPath, "..") {
			relIRPath = irPath // Keep absolute if can't make relative
		}
	}

	// Make storage location relative to project directory
	relStorageLocation := storageLocation
	if filepath.IsAbs(relStorageLocation) {
		relStorageLocation, err = filepath.Rel(projectDir, relStorageLocation)
		if err != nil {
			relStorageLocation = storageLocation // Fallback to absolute
		}
	}

	// Update config file
	if configFormat == "json" {
		if err := updateMorphirJSON(configPath, decorationID, displayName, relIRPath, entryPoint, relStorageLocation); err != nil {
			return fmt.Errorf("failed to update morphir.json: %w", err)
		}
	} else {
		if err := updateMorphirTOML(configPath, decorationID, displayName, relIRPath, entryPoint, relStorageLocation); err != nil {
			return fmt.Errorf("failed to update morphir.toml: %w", err)
		}
	}

	// Create empty decoration values file if it doesn't exist
	valuesPath := filepath.Join(projectDir, relStorageLocation)
	if _, err := os.Stat(valuesPath); os.IsNotExist(err) {
		emptyValues := map[string]interface{}{}
		data, err := json.MarshalIndent(emptyValues, "", "  ")
		if err != nil {
			return fmt.Errorf("failed to marshal empty values: %w", err)
		}
		if err := os.WriteFile(valuesPath, data, 0644); err != nil {
			return fmt.Errorf("failed to create decoration values file: %w", err)
		}
		fmt.Fprintf(cmd.ErrOrStderr(), "Created empty decoration values file: %s\n", relStorageLocation)
	}

	fmt.Fprintf(cmd.OutOrStdout(), "✓ Decoration %q configured successfully\n", decorationID)
	fmt.Fprintf(cmd.OutOrStdout(), "  Display Name: %s\n", displayName)
	fmt.Fprintf(cmd.OutOrStdout(), "  Entry Point: %s\n", entryPoint)
	fmt.Fprintf(cmd.OutOrStdout(), "  IR File: %s\n", relIRPath)
	fmt.Fprintf(cmd.OutOrStdout(), "  Storage: %s\n", relStorageLocation)
	if decorationSetupType != "" {
		fmt.Fprintf(cmd.OutOrStdout(), "  Type: %s (from registry)\n", decorationSetupType)
	}

	return nil
}

// updateMorphirJSON updates morphir.json with a new decoration configuration.
func updateMorphirJSON(configPath string, decorationID string, displayName string, irPath string, entryPoint string, storageLocation string) error {
	// Read raw JSON to preserve other fields
	data, err := os.ReadFile(configPath)
	if err != nil {
		return fmt.Errorf("read config file: %w", err)
	}

	var raw map[string]interface{}
	if err := json.Unmarshal(data, &raw); err != nil {
		return fmt.Errorf("parse JSON: %w", err)
	}

	// Ensure decorations map exists
	if raw["decorations"] == nil {
		raw["decorations"] = make(map[string]interface{})
	}
	decorations, ok := raw["decorations"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("decorations field is not a map")
	}

	// Add or update decoration
	decorations[decorationID] = map[string]interface{}{
		"displayName":     displayName,
		"ir":              irPath,
		"entryPoint":      entryPoint,
		"storageLocation": storageLocation,
	}

	// Write back
	output, err := json.MarshalIndent(raw, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal JSON: %w", err)
	}

	if err := os.WriteFile(configPath, output, 0644); err != nil {
		return fmt.Errorf("write config file: %w", err)
	}

	return nil
}

// updateMorphirTOML updates morphir.toml with a new decoration configuration.
func updateMorphirTOML(configPath string, decorationID string, displayName string, irPath string, entryPoint string, storageLocation string) error {
	// Read existing TOML
	data, err := os.ReadFile(configPath)
	if err != nil {
		return fmt.Errorf("read config file: %w", err)
	}

	var raw map[string]interface{}
	if err := toml.Unmarshal(data, &raw); err != nil {
		return fmt.Errorf("parse TOML: %w", err)
	}

	// Ensure project section exists
	if raw["project"] == nil {
		raw["project"] = make(map[string]interface{})
	}
	project, ok := raw["project"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("project section is not a map")
	}

	// Ensure decorations map exists
	if project["decorations"] == nil {
		project["decorations"] = make(map[string]interface{})
	}
	decorations, ok := project["decorations"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("decorations field is not a map")
	}

	// Add or update decoration
	decorations[decorationID] = map[string]interface{}{
		"display_name":     displayName,
		"ir":               irPath,
		"entry_point":      entryPoint,
		"storage_location": storageLocation,
	}

	// Write back
	var buf strings.Builder
	encoder := toml.NewEncoder(&buf)
	encoder.Indent = "  "
	if err := encoder.Encode(raw); err != nil {
		return fmt.Errorf("encode TOML: %w", err)
	}

	if err := os.WriteFile(configPath, []byte(buf.String()), 0644); err != nil {
		return fmt.Errorf("write config file: %w", err)
	}

	return nil
}
