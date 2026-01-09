package toolchain

import (
	"fmt"
	"sort"
	"strings"
)

// MermaidOptions configures Mermaid diagram generation.
type MermaidOptions struct {
	// ShowInputs includes inputs in node labels
	ShowInputs bool

	// ShowOutputs includes outputs in node labels
	ShowOutputs bool

	// TaskResults maps task keys to their execution results (for styling)
	TaskResults map[TaskKey]TaskResult
}

// DefaultMermaidOptions returns the default options.
func DefaultMermaidOptions() MermaidOptions {
	return MermaidOptions{
		ShowInputs:  false,
		ShowOutputs: false,
		TaskResults: nil,
	}
}

// PlanToMermaid generates a Mermaid flowchart diagram from an execution plan.
// The diagram shows stages as subgraphs, tasks as nodes, and dependencies as edges.
func PlanToMermaid(plan Plan) string {
	return PlanToMermaidWithOptions(plan, DefaultMermaidOptions())
}

// PlanToMermaidWithOptions generates a Mermaid flowchart with custom options.
func PlanToMermaidWithOptions(plan Plan, opts MermaidOptions) string {
	var sb strings.Builder

	sb.WriteString("flowchart TD\n")

	// Collect nodes that need styling
	var failedNodes, skippedNodes, successNodes []string

	// Generate subgraphs for each stage
	for stageIdx, stage := range plan.Stages {
		stageID := fmt.Sprintf("stage_%d", stageIdx)
		stageLabel := fmt.Sprintf("Stage: %s", stage.Name)
		if stage.Parallel {
			stageLabel += " (parallel)"
		}

		fmt.Fprintf(&sb, "    subgraph %s[\"%s\"]\n", stageID, escapeMermaidLabel(stageLabel))

		// Add task nodes within the stage
		for _, task := range stage.Tasks {
			nodeID := taskKeyToNodeID(task.Key)
			nodeLabel := formatTaskNodeLabel(task)

			if opts.ShowInputs || opts.ShowOutputs {
				nodeLabel = formatDetailedTaskLabel(task, opts)
			}

			fmt.Fprintf(&sb, "        %s[\"%s\"]\n", nodeID, escapeMermaidLabel(nodeLabel))

			// Track node status for styling
			if opts.TaskResults != nil {
				if result, ok := opts.TaskResults[task.Key]; ok {
					if result.Error != nil || !result.Metadata.Success {
						failedNodes = append(failedNodes, nodeID)
					} else {
						successNodes = append(successNodes, nodeID)
					}
				}
			}
		}

		sb.WriteString("    end\n")
	}

	// Check for skipped tasks
	if opts.TaskResults != nil {
		for key, task := range plan.Tasks {
			nodeID := taskKeyToNodeID(key)
			if _, ok := opts.TaskResults[key]; !ok {
				// Task wasn't executed - it was skipped
				skippedNodes = append(skippedNodes, nodeID)
				_ = task // unused but kept for clarity
			}
		}
	}

	// Generate edges for dependencies
	edges := collectDependencyEdges(plan)
	for _, edge := range edges {
		fmt.Fprintf(&sb, "    %s --> %s\n", edge.from, edge.to)
	}

	// Add styling for task status
	if len(failedNodes) > 0 || len(skippedNodes) > 0 || len(successNodes) > 0 {
		sb.WriteString("\n")
		if len(successNodes) > 0 {
			fmt.Fprintf(&sb, "    classDef success fill:#d4edda,stroke:#28a745\n")
			fmt.Fprintf(&sb, "    class %s success\n", strings.Join(successNodes, ","))
		}
		if len(failedNodes) > 0 {
			fmt.Fprintf(&sb, "    classDef failed fill:#f8d7da,stroke:#dc3545\n")
			fmt.Fprintf(&sb, "    class %s failed\n", strings.Join(failedNodes, ","))
		}
		if len(skippedNodes) > 0 {
			fmt.Fprintf(&sb, "    classDef skipped fill:#e2e3e5,stroke:#6c757d,stroke-dasharray: 5 5\n")
			fmt.Fprintf(&sb, "    class %s skipped\n", strings.Join(skippedNodes, ","))
		}
	}

	return sb.String()
}

// edge represents a directed edge in the diagram.
type edge struct {
	from string
	to   string
}

// collectDependencyEdges extracts all dependency edges from the plan.
func collectDependencyEdges(plan Plan) []edge {
	var edges []edge
	seen := make(map[string]struct{})

	for _, task := range plan.Tasks {
		toID := taskKeyToNodeID(task.Key)
		for _, dep := range task.DependsOn {
			fromID := taskKeyToNodeID(dep)
			edgeKey := fromID + "->" + toID
			if _, ok := seen[edgeKey]; ok {
				continue
			}
			seen[edgeKey] = struct{}{}
			edges = append(edges, edge{from: fromID, to: toID})
		}
	}

	return edges
}

// taskKeyToNodeID converts a TaskKey to a valid Mermaid node ID.
// Node IDs must be alphanumeric with underscores.
func taskKeyToNodeID(key TaskKey) string {
	id := key.Toolchain + "_" + key.Task
	if key.Variant != "" {
		id += "_" + key.Variant
	}
	// Replace any characters that aren't valid in Mermaid node IDs
	return sanitizeNodeID(id)
}

// sanitizeNodeID replaces invalid characters with underscores.
func sanitizeNodeID(id string) string {
	var sb strings.Builder
	for _, r := range id {
		if isValidNodeIDChar(r) {
			sb.WriteRune(r)
		} else {
			sb.WriteRune('_')
		}
	}
	return sb.String()
}

// isValidNodeIDChar returns true if the rune is valid in a Mermaid node ID.
func isValidNodeIDChar(r rune) bool {
	return (r >= 'a' && r <= 'z') ||
		(r >= 'A' && r <= 'Z') ||
		(r >= '0' && r <= '9') ||
		r == '_'
}

// formatTaskNodeLabel creates a human-readable label for a task node.
func formatTaskNodeLabel(task *PlanTask) string {
	label := fmt.Sprintf("%s/%s", task.Toolchain, task.Task)
	if task.Variant != "" {
		label += fmt.Sprintf(" (%s)", task.Variant)
	}
	return label
}

// formatDetailedTaskLabel creates a detailed label including inputs and/or outputs.
func formatDetailedTaskLabel(task *PlanTask, opts MermaidOptions) string {
	var parts []string

	// Task name with variant
	name := fmt.Sprintf("%s/%s", task.Toolchain, task.Task)
	if task.Variant != "" {
		name += fmt.Sprintf(" (%s)", task.Variant)
	}
	parts = append(parts, name)

	// Add inputs if present and requested
	if opts.ShowInputs && (len(task.Inputs.Files) > 0 || len(task.Inputs.Artifacts) > 0) {
		inputs := formatInputsCompact(task.Inputs)
		if inputs != "" {
			parts = append(parts, "in: "+inputs)
		}
	}

	// Add outputs if present and requested
	if opts.ShowOutputs && len(task.Outputs) > 0 {
		outputs := formatOutputsCompact(task.Outputs)
		if outputs != "" {
			parts = append(parts, "out: "+outputs)
		}
	}

	return strings.Join(parts, "\\n")
}

// formatInputsCompact creates a compact representation of inputs.
func formatInputsCompact(inputs InputSpec) string {
	var items []string

	// Add file patterns (abbreviated)
	for _, f := range inputs.Files {
		items = append(items, abbreviatePath(f))
	}

	// Add artifact references
	for name := range inputs.Artifacts {
		items = append(items, "@"+name)
	}

	if len(items) > 3 {
		return fmt.Sprintf("%s... (+%d)", strings.Join(items[:2], ", "), len(items)-2)
	}
	return strings.Join(items, ", ")
}

// formatOutputsCompact creates a compact representation of outputs.
func formatOutputsCompact(outputs map[string]OutputSpec) string {
	names := make([]string, 0, len(outputs))
	for name := range outputs {
		names = append(names, name)
	}
	sort.Strings(names)

	if len(names) > 3 {
		return fmt.Sprintf("%s... (+%d)", strings.Join(names[:2], ", "), len(names)-2)
	}
	return strings.Join(names, ", ")
}

// abbreviatePath shortens a file path for display.
func abbreviatePath(path string) string {
	if len(path) > 20 {
		// Show just the filename or last part
		parts := strings.Split(path, "/")
		if len(parts) > 1 {
			return ".../" + parts[len(parts)-1]
		}
		return path[:17] + "..."
	}
	return path
}

// escapeMermaidLabel escapes special characters in Mermaid labels.
func escapeMermaidLabel(label string) string {
	// Escape quotes and other special characters
	label = strings.ReplaceAll(label, "\"", "#quot;")
	label = strings.ReplaceAll(label, "<", "#lt;")
	label = strings.ReplaceAll(label, ">", "#gt;")
	return label
}
