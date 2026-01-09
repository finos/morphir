package toolchain

import (
	"fmt"
	"sort"
	"strings"
)

// Plan represents a computed execution plan for a workflow.
type Plan struct {
	Workflow Workflow
	Stages   []PlanStage
	Tasks    map[TaskKey]*PlanTask
}

// PlanStage represents a stage within a plan.
type PlanStage struct {
	Name      string
	Parallel  bool
	Condition string
	Tasks     []*PlanTask
}

// PlanTask represents a resolved task in a plan.
type PlanTask struct {
	Key          TaskKey
	Toolchain    string
	Task         string
	Target       string
	Variant      string
	Inputs       InputSpec
	Outputs      map[string]OutputSpec
	DependsOn    []TaskKey
	StageIndex   int
	TargetSource string
}

// TaskKey uniquely identifies a planned task.
type TaskKey struct {
	Toolchain string
	Task      string
	Variant   string
}

// String returns the task key as a human-readable identifier.
func (k TaskKey) String() string {
	if k.Variant == "" {
		return fmt.Sprintf("%s/%s", k.Toolchain, k.Task)
	}
	return fmt.Sprintf("%s/%s:%s", k.Toolchain, k.Task, k.Variant)
}

// PlanError aggregates multiple planning issues.
type PlanError struct {
	Issues []string
}

func (e PlanError) Error() string {
	if len(e.Issues) == 0 {
		return "plan: invalid workflow"
	}
	var sb strings.Builder
	sb.WriteString("plan: invalid workflow:")
	for _, issue := range e.Issues {
		sb.WriteString("\n- ")
		sb.WriteString(issue)
	}
	return sb.String()
}

// PlanBuilder computes execution plans.
type PlanBuilder struct {
	registry  *Registry
	workflows map[string]Workflow
}

// NewPlanBuilder creates a new plan builder.
func NewPlanBuilder(registry *Registry, workflows map[string]Workflow) *PlanBuilder {
	return &PlanBuilder{
		registry:  registry,
		workflows: workflows,
	}
}

// Build resolves and validates a workflow into an execution plan.
func (b *PlanBuilder) Build(workflowName string) (Plan, error) {
	resolved, err := b.resolveWorkflow(workflowName, map[string]bool{})
	if err != nil {
		return Plan{}, err
	}

	plan := Plan{
		Workflow: resolved,
		Stages:   make([]PlanStage, 0, len(resolved.Stages)),
		Tasks:    make(map[TaskKey]*PlanTask),
	}

	var issues []string
	stageIndexForTask := make(map[TaskKey]int)

	for stageIndex, stage := range resolved.Stages {
		planStage := PlanStage{
			Name:      stage.Name,
			Parallel:  stage.Parallel,
			Condition: stage.Condition,
			Tasks:     make([]*PlanTask, 0, len(stage.Targets)),
		}

		for _, targetSpec := range stage.Targets {
			targetName, variant, err := parseTargetSpec(targetSpec)
			if err != nil {
				issues = append(issues, err.Error())
				continue
			}

			toolchainName, taskDef, resolvedVariant, err := b.resolveTask(targetName, variant)
			if err != nil {
				issues = append(issues, err.Error())
				continue
			}

			key := TaskKey{Toolchain: toolchainName, Task: taskDef.Name, Variant: resolvedVariant}
			if _, exists := plan.Tasks[key]; exists {
				issues = append(issues, fmt.Sprintf("duplicate task in workflow: %s", key.String()))
				continue
			}

			planTask := &PlanTask{
				Key:          key,
				Toolchain:    toolchainName,
				Task:         taskDef.Name,
				Target:       targetName,
				Variant:      resolvedVariant,
				Inputs:       copyInputSpec(taskDef.Inputs),
				Outputs:      copyOutputSpecs(taskDef.Outputs),
				DependsOn:    nil,
				StageIndex:   stageIndex,
				TargetSource: targetSpec,
			}

			plan.Tasks[key] = planTask
			stageIndexForTask[key] = stageIndex
			planStage.Tasks = append(planStage.Tasks, planTask)
		}

		plan.Stages = append(plan.Stages, planStage)
	}

	if len(issues) > 0 {
		return Plan{}, PlanError{Issues: issues}
	}

	dependencyIssues := b.resolveDependencies(&plan, stageIndexForTask)
	if len(dependencyIssues) > 0 {
		return Plan{}, PlanError{Issues: dependencyIssues}
	}

	return plan, nil
}

func (b *PlanBuilder) resolveDependencies(plan *Plan, stageIndexForTask map[TaskKey]int) []string {
	var issues []string
	outputTypes := make(map[string][]TaskKey)

	for _, task := range plan.Tasks {
		for _, output := range task.Outputs {
			if output.Type == "" {
				continue
			}
			outputTypes[output.Type] = append(outputTypes[output.Type], task.Key)
		}
	}

	for _, task := range plan.Tasks {
		deps := make(map[TaskKey]struct{})

		for _, ref := range task.Inputs.Artifacts {
			toolchainName, taskName, _, err := parseArtifactRef(ref)
			if err != nil {
				issues = append(issues, fmt.Sprintf("invalid artifact reference for %s: %v", task.Key.String(), err))
				continue
			}
			refKey := TaskKey{Toolchain: toolchainName, Task: taskName, Variant: ""}
			if _, ok := plan.Tasks[refKey]; !ok {
				refKey, ok = matchTaskWithVariant(plan.Tasks, refKey)
				if !ok {
					issues = append(issues, fmt.Sprintf("missing dependency %s for %s", refKey.String(), task.Key.String()))
					continue
				}
			}
			if refKey == task.Key {
				continue
			}
			deps[refKey] = struct{}{}
		}

		if targetDef, ok := b.registry.GetTarget(task.Target); ok {
			for _, requiredType := range targetDef.Requires {
				producers := outputTypes[requiredType]
				if len(producers) == 0 {
					issues = append(issues, fmt.Sprintf("no task produces required type %q for target %s", requiredType, task.Target))
					continue
				}
				if len(producers) > 1 {
					choices := make([]string, 0, len(producers))
					for _, key := range producers {
						choices = append(choices, key.String())
					}
					sort.Strings(choices)
					issues = append(issues, fmt.Sprintf("multiple tasks produce type %q for target %s: %s", requiredType, task.Target, strings.Join(choices, ", ")))
					continue
				}
				if producers[0] == task.Key {
					continue
				}
				deps[producers[0]] = struct{}{}
			}
		}

		task.DependsOn = sortedKeys(deps)
		for _, dep := range task.DependsOn {
			if stageIndexForTask[dep] > task.StageIndex {
				issues = append(issues, fmt.Sprintf("dependency %s scheduled after %s", dep.String(), task.Key.String()))
			}
		}
	}

	return issues
}

func matchTaskWithVariant(tasks map[TaskKey]*PlanTask, key TaskKey) (TaskKey, bool) {
	var matches []TaskKey
	for candidate := range tasks {
		if candidate.Toolchain == key.Toolchain && candidate.Task == key.Task {
			matches = append(matches, candidate)
		}
	}
	if len(matches) != 1 {
		return key, false
	}
	return matches[0], true
}

func sortedKeys(set map[TaskKey]struct{}) []TaskKey {
	if len(set) == 0 {
		return nil
	}
	keys := make([]TaskKey, 0, len(set))
	for key := range set {
		keys = append(keys, key)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].Toolchain != keys[j].Toolchain {
			return keys[i].Toolchain < keys[j].Toolchain
		}
		if keys[i].Task != keys[j].Task {
			return keys[i].Task < keys[j].Task
		}
		return keys[i].Variant < keys[j].Variant
	})
	return keys
}

func copyInputSpec(spec InputSpec) InputSpec {
	result := InputSpec{}
	if len(spec.Files) > 0 {
		result.Files = make([]string, len(spec.Files))
		copy(result.Files, spec.Files)
	}
	if len(spec.Artifacts) > 0 {
		result.Artifacts = make(map[string]string, len(spec.Artifacts))
		for k, v := range spec.Artifacts {
			result.Artifacts[k] = v
		}
	}
	return result
}

func copyOutputSpecs(outputs map[string]OutputSpec) map[string]OutputSpec {
	if len(outputs) == 0 {
		return nil
	}
	result := make(map[string]OutputSpec, len(outputs))
	for k, v := range outputs {
		result[k] = v
	}
	return result
}

func (b *PlanBuilder) resolveWorkflow(name string, visiting map[string]bool) (Workflow, error) {
	if visiting[name] {
		return Workflow{}, fmt.Errorf("workflow inheritance cycle detected at %q", name)
	}

	workflow, ok := b.workflows[name]
	if !ok {
		return Workflow{}, fmt.Errorf("workflow not found: %s", name)
	}

	if workflow.Extends == "" {
		return workflow, nil
	}

	visiting[name] = true
	base, err := b.resolveWorkflow(workflow.Extends, visiting)
	delete(visiting, name)
	if err != nil {
		return Workflow{}, err
	}

	merged := Workflow{
		Name:        workflow.Name,
		Description: workflow.Description,
		Extends:     workflow.Extends,
		Stages:      make([]WorkflowStage, 0, len(base.Stages)+len(workflow.Stages)),
	}
	merged.Stages = append(merged.Stages, base.Stages...)
	merged.Stages = append(merged.Stages, workflow.Stages...)
	return merged, nil
}

func (b *PlanBuilder) resolveTask(targetName, variant string) (string, TaskDef, string, error) {
	toolchainNames := b.registry.ListToolchains()
	sort.Strings(toolchainNames)

	type candidate struct {
		toolchain string
		task      TaskDef
	}
	var candidates []candidate

	for _, name := range toolchainNames {
		tc, ok := b.registry.GetToolchain(name)
		if !ok {
			continue
		}
		for _, task := range tc.Tasks {
			if fulfillsTarget(task.Fulfills, targetName) {
				candidates = append(candidates, candidate{toolchain: name, task: task})
			}
		}
	}

	if len(candidates) == 0 {
		return "", TaskDef{}, "", fmt.Errorf("no task fulfills target %q", targetName)
	}

	filtered := make([]candidate, 0, len(candidates))
	variantMatch := variant
	variantCandidates := make([]string, 0)

	for _, cand := range candidates {
		if len(cand.task.Variants) == 0 {
			if variant != "" {
				continue
			}
			filtered = append(filtered, cand)
			continue
		}

		if variant == "" {
			variantCandidates = append(variantCandidates, strings.Join(cand.task.Variants, ", "))
			continue
		}

		if match, ok := matchVariant(cand.task.Variants, variant); ok {
			variantMatch = match
			filtered = append(filtered, cand)
		}
	}

	if variant == "" && len(filtered) == 0 && len(variantCandidates) > 0 {
		sort.Strings(variantCandidates)
		return "", TaskDef{}, "", fmt.Errorf("target %q requires a variant (%s)", targetName, strings.Join(variantCandidates, "; "))
	}

	if len(filtered) == 0 {
		return "", TaskDef{}, "", fmt.Errorf("no task variant %q available for target %q", variant, targetName)
	}
	if len(filtered) > 1 {
		choices := make([]string, 0, len(filtered))
		for _, cand := range filtered {
			choices = append(choices, fmt.Sprintf("%s/%s", cand.toolchain, cand.task.Name))
		}
		sort.Strings(choices)
		return "", TaskDef{}, "", fmt.Errorf("multiple tasks fulfill target %q: %s", targetName, strings.Join(choices, ", "))
	}

	return filtered[0].toolchain, filtered[0].task, variantMatch, nil
}

func fulfillsTarget(fulfills []string, target string) bool {
	for _, name := range fulfills {
		if name == target {
			return true
		}
	}
	return false
}

func matchVariant(variants []string, wanted string) (string, bool) {
	for _, v := range variants {
		if strings.EqualFold(v, wanted) {
			return v, true
		}
	}
	return "", false
}

func parseTargetSpec(spec string) (string, string, error) {
	if strings.TrimSpace(spec) == "" {
		return "", "", fmt.Errorf("empty target specification")
	}

	parts := strings.SplitN(spec, ":", 2)
	if len(parts) == 1 {
		return parts[0], "", nil
	}
	if parts[0] == "" {
		return "", "", fmt.Errorf("invalid target specification %q: missing target name", spec)
	}
	if parts[1] == "" {
		return "", "", fmt.Errorf("invalid target specification %q: missing variant", spec)
	}
	return parts[0], parts[1], nil
}

func parseArtifactRef(ref string) (string, string, string, error) {
	if !strings.HasPrefix(ref, "@") {
		return "", "", "", fmt.Errorf("artifact ref must start with '@': %s", ref)
	}
	ref = strings.TrimPrefix(ref, "@")
	parts := strings.SplitN(ref, ":", 2)
	if len(parts) != 2 {
		return "", "", "", fmt.Errorf("artifact ref must include ':' separator: %s", ref)
	}
	taskPart := parts[0]
	artifactName := parts[1]
	taskParts := strings.SplitN(taskPart, "/", 2)
	if len(taskParts) != 2 {
		return "", "", "", fmt.Errorf("artifact ref must include toolchain/task: %s", ref)
	}
	if taskParts[0] == "" || taskParts[1] == "" {
		return "", "", "", fmt.Errorf("artifact ref must include toolchain and task: %s", ref)
	}
	return taskParts[0], taskParts[1], artifactName, nil
}
