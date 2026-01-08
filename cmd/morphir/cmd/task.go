package cmd

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/lipgloss/table"
	"github.com/finos/morphir/pkg/config"
	"github.com/finos/morphir/pkg/tooling/workspace"
	"github.com/spf13/cobra"
)

var taskCmd = &cobra.Command{
	Use:     "task",
	Aliases: []string{"tasks"},
	Short:   "Manage Morphir tasks",
	Long:    `Commands for managing Morphir tasks defined in morphir.toml.`,
	RunE:    runTaskList, // Default to list when no subcommand provided
}

var (
	taskListJSON       bool
	taskListProperties string
)

var taskListCmd = &cobra.Command{
	Use:   "list",
	Short: "List tasks defined in the workspace",
	Long: `List all tasks defined in morphir.toml.

By default, lists tasks in a human-readable table format.
Use --json to output as JSON.

When using --json, you can optionally specify which properties to include:
  morphir task list --json --properties name,kind,action

Available properties:
  - name: Task name
  - kind: Task kind (intrinsic or command)
  - action: Intrinsic action identifier (for intrinsic tasks)
  - cmd: Command and arguments (for command tasks)
  - depends_on: Task dependencies
  - pre: Pre-execution hooks
  - post: Post-execution hooks
  - inputs: Input globs
  - outputs: Output globs
  - params: Task parameters
  - env: Environment variables
  - mounts: Mount permissions`,
	RunE: runTaskList,
}

func runTaskList(cmd *cobra.Command, args []string) error {
	lw, err := workspace.LoadFromCwd()
	if err != nil {
		return fmt.Errorf("failed to load workspace: %w", err)
	}

	tasks := lw.Config().Tasks()

	if taskListJSON {
		return printTaskListJSON(tasks, taskListProperties)
	}

	return printTaskListTable(tasks)
}

func printTaskListJSON(tasks config.TasksSection, properties string) error {
	var requestedProps []string
	if properties != "" {
		for _, p := range strings.Split(properties, ",") {
			requestedProps = append(requestedProps, strings.TrimSpace(p))
		}
	}

	names := tasks.Names()
	sort.Strings(names)

	output := make([]map[string]any, 0, len(names))
	for _, name := range names {
		task, ok := tasks.Get(name)
		if !ok {
			continue
		}
		taskMap := buildTaskMap(name, task, requestedProps)
		output = append(output, taskMap)
	}

	data, err := json.MarshalIndent(output, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal tasks: %w", err)
	}
	fmt.Println(string(data))
	return nil
}

func buildTaskMap(name string, task config.Task, requestedProps []string) map[string]any {
	allProps := map[string]any{
		"name":       name,
		"depends_on": task.DependsOn(),
		"pre":        task.Pre(),
		"post":       task.Post(),
		"inputs":     task.Inputs(),
		"outputs":    task.Outputs(),
		"params":     task.Params(),
		"env":        task.Env(),
		"mounts":     task.Mounts(),
	}

	switch t := task.(type) {
	case config.IntrinsicTask:
		allProps["kind"] = "intrinsic"
		allProps["action"] = t.Action()
	case config.CommandTask:
		allProps["kind"] = "command"
		allProps["cmd"] = t.Cmd()
	}

	if len(requestedProps) == 0 {
		return allProps
	}

	result := make(map[string]any)
	for _, prop := range requestedProps {
		if val, ok := allProps[prop]; ok {
			result[prop] = val
		}
	}
	return result
}

func printTaskListTable(tasks config.TasksSection) error {
	names := tasks.Names()
	if len(names) == 0 {
		fmt.Println("No tasks defined in workspace.")
		return nil
	}

	sort.Strings(names)

	headerStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("12")).
		Padding(0, 1)

	cellStyle := lipgloss.NewStyle().
		Padding(0, 1)

	intrinsicStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("10")).
		Padding(0, 1)

	commandStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("14")).
		Padding(0, 1)

	rows := make([][]string, 0, len(names))
	taskKinds := make([]string, 0, len(names))

	for _, name := range names {
		task, ok := tasks.Get(name)
		if !ok {
			continue
		}

		var kind, actionOrCmd string
		switch t := task.(type) {
		case config.IntrinsicTask:
			kind = "intrinsic"
			actionOrCmd = t.Action()
		case config.CommandTask:
			kind = "command"
			cmd := t.Cmd()
			if len(cmd) > 0 {
				if len(cmd) > 3 {
					actionOrCmd = strings.Join(cmd[:3], " ") + "..."
				} else {
					actionOrCmd = strings.Join(cmd, " ")
				}
			}
		}

		deps := formatCount(len(task.DependsOn()))
		hooks := formatHooks(len(task.Pre()), len(task.Post()))

		rows = append(rows, []string{
			name,
			kind,
			actionOrCmd,
			deps,
			hooks,
		})
		taskKinds = append(taskKinds, kind)
	}

	t := table.New().
		Border(lipgloss.NormalBorder()).
		BorderStyle(lipgloss.NewStyle().Foreground(lipgloss.Color("240"))).
		Headers("NAME", "KIND", "ACTION/CMD", "DEPS", "HOOKS").
		Rows(rows...).
		StyleFunc(func(row, col int) lipgloss.Style {
			if row == table.HeaderRow {
				return headerStyle
			}
			if row < len(taskKinds) {
				if taskKinds[row] == "intrinsic" {
					return intrinsicStyle
				}
				return commandStyle
			}
			return cellStyle
		})

	fmt.Printf("Tasks in workspace (%d total):\n\n", len(names))
	fmt.Println(t)

	return nil
}

func formatCount(n int) string {
	if n == 0 {
		return "-"
	}
	return fmt.Sprintf("%d", n)
}

func formatHooks(pre, post int) string {
	if pre == 0 && post == 0 {
		return "-"
	}
	return fmt.Sprintf("%d/%d", pre, post)
}

func init() {
	taskCmd.AddCommand(taskListCmd)

	// Add flags to both taskCmd (for direct invocation) and taskListCmd
	taskCmd.Flags().BoolVar(&taskListJSON, "json", false,
		"Output as JSON")
	taskCmd.Flags().StringVar(&taskListProperties, "properties", "",
		"Comma-separated list of properties to include in JSON output")

	taskListCmd.Flags().BoolVar(&taskListJSON, "json", false,
		"Output as JSON")
	taskListCmd.Flags().StringVar(&taskListProperties, "properties", "",
		"Comma-separated list of properties to include in JSON output")
}
