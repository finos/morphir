package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"

	ir "github.com/finos/morphir/pkg/models/ir"
	jsoncodec "github.com/finos/morphir/pkg/models/ir/codec/json"
	decorationmodels "github.com/finos/morphir/pkg/models/ir/decorations"
	"github.com/finos/morphir/pkg/tooling/decorations"
	"github.com/finos/morphir/pkg/tooling/workspace"
	"github.com/spf13/cobra"
)

var (
	decorationListJSON    bool
	decorationListType    string
	decorationGetJSON     bool
	decorationGetType     string
	decorationSearchType  string
	decorationSearchQuery string
	decorationStatsJSON   bool
)

var decorationListCmd = &cobra.Command{
	Use:   "list",
	Short: "List all decorated nodes",
	Long: `List all IR nodes that have decorations attached.

Use --type to filter by a specific decoration type.
Use --json for machine-readable output.`,
	RunE: runDecorationList,
}

var decorationGetCmd = &cobra.Command{
	Use:   "get <node-path>",
	Short: "Get decorations for a specific node",
	Long: `Get all decorations for a specific IR node identified by its NodePath.

The node-path should be in the format:
  - Type/Value: "PackageName:ModuleName:LocalName"
  - Module: "PackageName:ModuleName"

Use --type to filter by a specific decoration type.
Use --json for machine-readable output.`,
	Args: cobra.ExactArgs(1),
	RunE: runDecorationGet,
}

var decorationSearchCmd = &cobra.Command{
	Use:   "search",
	Short: "Search for decorated nodes",
	Long: `Search for nodes with decorations matching criteria.

Currently supports filtering by decoration type.
Future versions may support content-based search.`,
	RunE: runDecorationSearch,
}

var decorationStatsCmd = &cobra.Command{
	Use:   "stats",
	Short: "Show decoration statistics",
	Long: `Display statistics about decorations in the current project.

Shows:
  - Total number of decorated nodes
  - Number of decorations per type
  - Decoration type distribution

Use --json for machine-readable output.`,
	RunE: runDecorationStats,
}

func init() {
	decorationCmd.AddCommand(decorationListCmd)
	decorationListCmd.Flags().BoolVar(&decorationListJSON, "json", false, "Output as JSON")
	decorationListCmd.Flags().StringVar(&decorationListType, "type", "", "Filter by decoration type ID")

	decorationCmd.AddCommand(decorationGetCmd)
	decorationGetCmd.Flags().BoolVar(&decorationGetJSON, "json", false, "Output as JSON")
	decorationGetCmd.Flags().StringVar(&decorationGetType, "type", "", "Filter by decoration type ID")

	decorationCmd.AddCommand(decorationSearchCmd)
	decorationSearchCmd.Flags().StringVar(&decorationSearchType, "type", "", "Filter by decoration type ID")
	decorationSearchCmd.Flags().StringVar(&decorationSearchQuery, "query", "", "Search query (future: content-based search)")

	decorationCmd.AddCommand(decorationStatsCmd)
	decorationStatsCmd.Flags().BoolVar(&decorationStatsJSON, "json", false, "Output as JSON")
}

func runDecorationList(cmd *cobra.Command, args []string) error {
	// Load workspace and distribution
	attached, err := loadAttachedDistribution()
	if err != nil {
		return err
	}

	// Get all nodes with decorations
	var nodePaths []ir.NodePath
	if decorationListType != "" {
		decID := decorationmodels.DecorationID(decorationListType)
		nodePaths = attached.GetAllNodesWithDecoration(decID)
	} else {
		nodePaths = attached.GetAllNodesWithDecorations()
	}

	// Sort by string representation for consistent output
	sort.Slice(nodePaths, func(i, j int) bool {
		return nodePaths[i].String() < nodePaths[j].String()
	})

	if decorationListJSON {
		return outputDecorationListJSON(cmd, nodePaths, attached)
	}

	return outputDecorationListText(cmd, nodePaths, attached)
}

func runDecorationGet(cmd *cobra.Command, args []string) error {
	nodePathStr := args[0]

	// Parse NodePath
	nodePath, err := ir.ParseNodePath(nodePathStr)
	if err != nil {
		return fmt.Errorf("invalid node path %q: %w", nodePathStr, err)
	}

	// Load workspace and distribution
	attached, err := loadAttachedDistribution()
	if err != nil {
		return err
	}

	// Get decorations for node
	var decs map[decorationmodels.DecorationID]json.RawMessage
	if decorationGetType != "" {
		decID := decorationmodels.DecorationID(decorationGetType)
		options := decorations.FilterOptions{
			DecorationIDs: []decorationmodels.DecorationID{decID},
		}
		decs = attached.FilterDecorationsForNode(nodePath, options)
	} else {
		decs = attached.GetDecorationsForNode(nodePath)
	}

	if decorationGetJSON {
		return outputDecorationGetJSON(cmd, nodePath, decs)
	}

	return outputDecorationGetText(cmd, nodePath, decs)
}

func runDecorationSearch(cmd *cobra.Command, args []string) error {
	// Load workspace and distribution
	attached, err := loadAttachedDistribution()
	if err != nil {
		return err
	}

	// For now, search is just filtering by type
	// Future: could search decoration content
	if decorationSearchType == "" {
		return fmt.Errorf("--type is required for search (content-based search coming soon)")
	}

	decID := decorationmodels.DecorationID(decorationSearchType)
	nodePaths := attached.GetAllNodesWithDecoration(decID)

	// Sort by string representation
	sort.Slice(nodePaths, func(i, j int) bool {
		return nodePaths[i].String() < nodePaths[j].String()
	})

	_, _ = fmt.Fprintf(cmd.OutOrStdout(), "Found %d node(s) with decoration type %q:\n\n", len(nodePaths), decorationSearchType)
	for _, nodePath := range nodePaths {
		_, _ = fmt.Fprintf(cmd.OutOrStdout(), "  %s\n", nodePath.String())
	}

	return nil
}

func runDecorationStats(cmd *cobra.Command, args []string) error {
	// Load workspace and distribution
	attached, err := loadAttachedDistribution()
	if err != nil {
		return err
	}

	// Collect statistics
	allNodes := attached.GetAllNodesWithDecorations()
	decIDs := attached.ListDecorationIDs()

	stats := DecorationStats{
		TotalNodes:       len(allNodes),
		TotalDecorations: attached.CountDecorations(),
		DecorationTypes:  make(map[string]int),
	}

	// Count decorations per type
	for _, decID := range decIDs {
		nodes := attached.GetAllNodesWithDecoration(decID)
		stats.DecorationTypes[string(decID)] = len(nodes)
	}

	if decorationStatsJSON {
		return outputDecorationStatsJSON(cmd, stats)
	}

	return outputDecorationStatsText(cmd, stats)
}

// loadAttachedDistribution loads the workspace, IR, and attaches decorations.
func loadAttachedDistribution() (decorations.AttachedDistribution, error) {
	// Load workspace
	lw, err := workspace.LoadFromCwd()
	if err != nil {
		return decorations.AttachedDistribution{}, fmt.Errorf("load workspace: %w", err)
	}

	rootProject := lw.RootProject()
	if rootProject == nil {
		return decorations.AttachedDistribution{}, fmt.Errorf("no root project found")
	}

	projectConfig := rootProject.Config()

	// Find IR file
	workspaceRoot := lw.Config().Workspace().Root()
	irPath := filepath.Join(workspaceRoot, "morphir-ir.json")
	if _, err := os.Stat(irPath); os.IsNotExist(err) {
		// If IR file doesn't exist, we can still work with decorations
		// Create a minimal distribution for decoration queries
		lib := ir.NewLibrary(
			ir.PathFromString(projectConfig.Name()),
			nil,
			ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]](),
		)

		// Load and attach decorations (without IR, we can still query decoration values)
		attached, err := decorations.LoadAndAttachDecorations(lib, projectConfig, false)
		if err != nil {
			return decorations.AttachedDistribution{}, fmt.Errorf("load decorations: %w", err)
		}

		return attached, nil
	}

	// Load actual IR distribution
	irData, err := os.ReadFile(irPath)
	if err != nil {
		return decorations.AttachedDistribution{}, fmt.Errorf("read IR file: %w", err)
	}

	// Decode IR distribution
	opts := jsoncodec.Options{
		FormatVersion: jsoncodec.FormatV3,
	}

	// Check if wrapped format
	var wrapper struct {
		FormatVersion *int            `json:"formatVersion"`
		Distribution  json.RawMessage `json:"distribution"`
	}
	if err := json.Unmarshal(irData, &wrapper); err == nil && wrapper.FormatVersion != nil && wrapper.Distribution != nil {
		dist, err := jsoncodec.DecodeDistribution(opts, wrapper.Distribution)
		if err != nil {
			return decorations.AttachedDistribution{}, fmt.Errorf("decode distribution: %w", err)
		}
		lib := dist.(ir.Library)

		// Load and attach decorations
		attached, err := decorations.LoadAndAttachDecorations(lib, projectConfig, false)
		if err != nil {
			return decorations.AttachedDistribution{}, fmt.Errorf("load decorations: %w", err)
		}

		return attached, nil
	}

	// Try direct distribution format
	dist, err := jsoncodec.DecodeDistribution(opts, json.RawMessage(irData))
	if err != nil {
		return decorations.AttachedDistribution{}, fmt.Errorf("decode distribution: %w", err)
	}
	lib := dist.(ir.Library)

	// Load and attach decorations
	attached, err := decorations.LoadAndAttachDecorations(lib, projectConfig, false)
	if err != nil {
		return decorations.AttachedDistribution{}, fmt.Errorf("load decorations: %w", err)
	}

	return attached, nil
}

// DecorationStats represents decoration statistics.
type DecorationStats struct {
	TotalNodes       int            `json:"total_nodes"`
	TotalDecorations int            `json:"total_decorations"`
	DecorationTypes  map[string]int `json:"decoration_types"`
}

func outputDecorationListJSON(cmd *cobra.Command, nodePaths []ir.NodePath, attached decorations.AttachedDistribution) error {
	type NodeInfo struct {
		NodePath    string   `json:"node_path"`
		Decorations []string `json:"decoration_types"`
		Count       int      `json:"decoration_count"`
	}

	nodes := make([]NodeInfo, 0, len(nodePaths))
	for _, nodePath := range nodePaths {
		decs := attached.GetDecorationsForNode(nodePath)
		decTypes := make([]string, 0, len(decs))
		for decID := range decs {
			decTypes = append(decTypes, string(decID))
		}
		sort.Strings(decTypes)

		nodes = append(nodes, NodeInfo{
			NodePath:    nodePath.String(),
			Decorations: decTypes,
			Count:       len(decs),
		})
	}

	encoder := json.NewEncoder(cmd.OutOrStdout())
	encoder.SetIndent("", "  ")
	return encoder.Encode(nodes)
}

func outputDecorationListText(cmd *cobra.Command, nodePaths []ir.NodePath, attached decorations.AttachedDistribution) error {
	if len(nodePaths) == 0 {
		_, _ = fmt.Fprintf(cmd.OutOrStdout(), "No decorated nodes found.\n")
		return nil
	}

	_, _ = fmt.Fprintf(cmd.OutOrStdout(), "Decorated Nodes (%d):\n\n", len(nodePaths))
	for _, nodePath := range nodePaths {
		decs := attached.GetDecorationsForNode(nodePath)
		decTypes := make([]string, 0, len(decs))
		for decID := range decs {
			decTypes = append(decTypes, string(decID))
		}
		sort.Strings(decTypes)

		_, _ = fmt.Fprintf(cmd.OutOrStdout(), "  %s\n", nodePath.String())
		_, _ = fmt.Fprintf(cmd.OutOrStdout(), "    Decorations: %s\n", fmt.Sprintf("%v", decTypes))
		_, _ = fmt.Fprintf(cmd.OutOrStdout(), "    Count: %d\n\n", len(decs))
	}

	return nil
}

func outputDecorationGetJSON(cmd *cobra.Command, nodePath ir.NodePath, decs map[decorationmodels.DecorationID]json.RawMessage) error {
	type DecorationInfo struct {
		Type  string          `json:"type"`
		Value json.RawMessage `json:"value"`
	}

	result := struct {
		NodePath    string           `json:"node_path"`
		Decorations []DecorationInfo `json:"decorations"`
		Count       int              `json:"count"`
	}{
		NodePath: nodePath.String(),
		Count:    len(decs),
	}

	for decID, value := range decs {
		result.Decorations = append(result.Decorations, DecorationInfo{
			Type:  string(decID),
			Value: value,
		})
	}

	encoder := json.NewEncoder(cmd.OutOrStdout())
	encoder.SetIndent("", "  ")
	return encoder.Encode(result)
}

func outputDecorationGetText(cmd *cobra.Command, nodePath ir.NodePath, decs map[decorationmodels.DecorationID]json.RawMessage) error {
	if len(decs) == 0 {
		fmt.Fprintf(cmd.OutOrStdout(), "No decorations found for node %q.\n", nodePath.String())
		return nil
	}

	fmt.Fprintf(cmd.OutOrStdout(), "Decorations for %q:\n\n", nodePath.String())

	// Sort decoration IDs for consistent output
	decIDs := make([]string, 0, len(decs))
	for decID := range decs {
		decIDs = append(decIDs, string(decID))
	}
	sort.Strings(decIDs)

	for _, decID := range decIDs {
		value := decs[decorationmodels.DecorationID(decID)]
		fmt.Fprintf(cmd.OutOrStdout(), "  [%s]\n", decID)
		fmt.Fprintf(cmd.OutOrStdout(), "    %s\n\n", string(value))
	}

	return nil
}

func outputDecorationStatsJSON(cmd *cobra.Command, stats DecorationStats) error {
	encoder := json.NewEncoder(cmd.OutOrStdout())
	encoder.SetIndent("", "  ")
	return encoder.Encode(stats)
}

func outputDecorationStatsText(cmd *cobra.Command, stats DecorationStats) error {
	fmt.Fprintf(cmd.OutOrStdout(), "Decoration Statistics:\n\n")
	fmt.Fprintf(cmd.OutOrStdout(), "  Total Decorated Nodes: %d\n", stats.TotalNodes)
	fmt.Fprintf(cmd.OutOrStdout(), "  Total Decorations: %d\n", stats.TotalDecorations)
	fmt.Fprintf(cmd.OutOrStdout(), "\n  Decoration Types:\n")

	if len(stats.DecorationTypes) == 0 {
		fmt.Fprintf(cmd.OutOrStdout(), "    (none)\n")
		return nil
	}

	// Sort by count (descending) then by name
	type typeCount struct {
		name  string
		count int
	}
	counts := make([]typeCount, 0, len(stats.DecorationTypes))
	for name, count := range stats.DecorationTypes {
		counts = append(counts, typeCount{name: name, count: count})
	}
	sort.Slice(counts, func(i, j int) bool {
		if counts[i].count != counts[j].count {
			return counts[i].count > counts[j].count
		}
		return counts[i].name < counts[j].name
	})

	for _, tc := range counts {
		fmt.Fprintf(cmd.OutOrStdout(), "    %s: %d node(s)\n", tc.name, tc.count)
	}

	return nil
}
