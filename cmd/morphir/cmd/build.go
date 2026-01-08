package cmd

import (
	"fmt"
	"runtime"

	"github.com/finos/morphir/pkg/config"
	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/task"
	"github.com/finos/morphir/pkg/tooling/workspace"
	"github.com/finos/morphir/pkg/vfs"
	"github.com/spf13/cobra"
)

var (
	buildNoCache    bool
	buildWorkers    int
	buildProjectDir string
)

var buildCmd = &cobra.Command{
	Use:   "build [task-names...]",
	Short: "Execute tasks in the workspace",
	Long: `Execute tasks defined in morphir.toml.

By default, runs the 'build' task if defined, or lists available tasks.
If specific task names are provided, only those tasks and their dependencies are executed.

Caching is enabled by default. Use --no-cache to force full re-execution.
Parallel execution is enabled by default using all available CPU cores.`,
	RunE: runBuild,
}

func init() {
	buildCmd.Flags().BoolVar(&buildNoCache, "no-cache", false, "Disable result caching")
	buildCmd.Flags().IntVarP(&buildWorkers, "jobs", "j", 0, "Number of parallel workers (default: all CPUs)")
	buildCmd.Flags().StringVar(&buildProjectDir, "project", "", "Path to project root (default: current directory)")
}

func runBuild(cmd *cobra.Command, args []string) error {
	// 1. Load Workspace
	lw, err := workspace.LoadFromCwd()
	if err != nil {
		return fmt.Errorf("failed to load workspace: %w", err)
	}

	cfg := lw.Config()
	tasks := cfg.Tasks()
	
	taskMap := make(map[string]task.Task)
	names := tasks.Names()
	for _, name := range names {
		tCfg, ok := tasks.Get(name)
		if !ok {
			continue
		}
		
		switch t := tCfg.(type) {
		case config.IntrinsicTask:
			opts := []task.TaskOption{
				task.WithDependsOn(t.DependsOn()),
				task.WithPre(t.Pre()),
				task.WithPost(t.Post()),
				task.WithInputs(toGlobs(t.Inputs())),
				task.WithOutputs(toGlobs(t.Outputs())),
				task.WithParams(t.Params()),
				task.WithEnv(t.Env()),
				task.WithMounts(t.Mounts()),
			}
			
			newTask := task.NewIntrinsicTask(name, t.Action(), opts...)
			taskMap[name] = newTask
			
		case config.CommandTask:
			opts := []task.TaskOption{
				task.WithDependsOn(t.DependsOn()),
				task.WithPre(t.Pre()),
				task.WithPost(t.Post()),
				task.WithInputs(toGlobs(t.Inputs())),
				task.WithOutputs(toGlobs(t.Outputs())),
				task.WithParams(t.Params()),
				task.WithEnv(t.Env()),
				task.WithMounts(t.Mounts()),
			}
			
			newTask := task.NewCommandTask(name, t.Cmd(), opts...)
			taskMap[name] = newTask
		}
	}

	// 2. Constants & Context
	projectRoot := lw.Workspace().Root()
	
	// Create VFS
	// Construct an OS mount at root
	rootPath, err := vfs.ParseVPath("/")
	if err != nil {
		return fmt.Errorf("failed to parse root vpath: %w", err)
	}
	
	osMount := vfs.NewOSMount("project_root", vfs.MountRW, projectRoot, rootPath)
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{osMount})
	
	if buildWorkers <= 0 {
		buildWorkers = runtime.NumCPU()
	}

	// 3. Initialize Executor Components
	registry := task.NewTaskRegistry()
	
	cm, err := task.NewCacheManager(projectRoot)
	if err != nil {
		fmt.Printf("Warning: failed to initialize cache: %v\n", err)
	}

	executor := task.NewExecutor(
		registry,
		taskMap,
		task.WithCacheManager(cm),
		task.WithVFS(vfsInstance), // OverlayVFS implements VFS interface
		task.WithMaxParallelism(buildWorkers),
		task.WithNoCache(buildNoCache),
		task.WithProjectRoot(projectRoot),
	)

	// 4. Create Pipeline Context
	pCtx := pipeline.NewContext(
		projectRoot,
		1, // Format Version
		pipeline.ModeDefault,
		vfsInstance,
	)

	// 5. Determine Tasks to Run
	var targetTasks []string
	if len(args) > 0 {
		targetTasks = args
	} else {
		if _, ok := taskMap["build"]; ok {
			targetTasks = []string{"build"}
		} else {
			fmt.Println("No 'build' task found and no tasks specified.")
			fmt.Println("Available tasks:")
			for name := range taskMap {
				fmt.Printf("  - %s\n", name)
			}
			return nil
		}
	}

	// 6. Execute
	failed := false
	for _, name := range targetTasks {
		fmt.Printf("Running task: %s\n", name)
		result, err := executor.Execute(pCtx, name)
		if err != nil {
			fmt.Printf("Task %s failed: %v\n", name, err)
			failed = true
			continue 
		}
		
		status := "Executed"
		if result.Err != nil {
			status = "Failed" 
		}
		fmt.Printf("Task %s: %s\n", name, status)
	}

	if failed {
		return fmt.Errorf("build failed")
	}
	
	return nil
}

func toGlobs(strs []string) []vfs.Glob {
	globs := make([]vfs.Glob, 0, len(strs))
	for _, s := range strs {
		if g, err := vfs.ParseGlob(s); err == nil {
			globs = append(globs, g)
		} else {
			// Warn? For now ignore invalid globs or panic?
			// Let's rely on ParseGlob strictness but maybe we should log.
			// Making it safe by ignoring invalid ones for this context.
		}
	}
	return globs
}
