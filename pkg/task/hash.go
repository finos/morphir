package task

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"sort"

	"github.com/finos/morphir/pkg/vfs"
)

// ComputeTaskHash computes a deterministic hash for a task.
// The hash is based on:
// 1. Task Name and Action/Command
// 2. Task Configuration (Params, Env, Mounts)
// 3. Content of input files (resolved from globs)
// 4. Hashes of output references (dependencies) - TODO: passed in via map
// 5. Tool Version (optional)
func ComputeTaskHash(task Task, vfsInstance vfs.VFS, dependencyHashes map[string]string, toolVersion string) (string, error) {
	hasher := sha256.New()

	// 1. Task Identity
	fmt.Fprintf(hasher, "task_name:%s\n", task.Name)
	switch cfg := task.Config.(type) {
	case IntrinsicTaskConfig:
		fmt.Fprintf(hasher, "kind:intrinsic\naction:%s\n", cfg.Action())
	case CommandTaskConfig:
		fmt.Fprintf(hasher, "kind:command\ncmd:%v\n", cfg.Cmd())
	}

	// 2. Configuration
	if err := hashConfig(hasher, task.Config); err != nil {
		return "", fmt.Errorf("failed to hash config: %w", err)
	}

	// 3. Inputs
	// Resolve globs to find all input files
	inputFiles, err := resolveInputs(task.Config.Inputs(), vfsInstance)
	if err != nil {
		return "", fmt.Errorf("failed to resolve inputs: %w", err)
	}

	// Sort files for determinism
	sort.Slice(inputFiles, func(i, j int) bool {
		return inputFiles[i].Path().String() < inputFiles[j].Path().String()
	})

	// Hash each file's path and content
	for _, file := range inputFiles {
		fmt.Fprintf(hasher, "input_path:%s\n", file.Path().String())
		
		content, err := file.Bytes() // TODO: Use Stream() for large files
		if err != nil {
			return "", fmt.Errorf("failed to read file %s: %w", file.Path(), err)
		}
		
		// Hash content
		contentHash := sha256.Sum256(content)
		fmt.Fprintf(hasher, "input_content:%x\n", contentHash)
	}

	// 4. Dependency Hashes
	// Sort dependencies for determinism
	deps := task.Config.DependsOn()
	sort.Strings(deps)
	for _, dep := range deps {
		if hash, ok := dependencyHashes[dep]; ok {
			fmt.Fprintf(hasher, "dep:%s:%s\n", dep, hash)
		} else {
			// If a dependency hash is missing, we can't safely cache this task
			// (or we treat it as a cache miss/re-run always, but strictly we should probably fail or warn)
			// For now, let's include a specific marker so it changes if the dep is unknown (which shouldn't happen in valid exec)
			fmt.Fprintf(hasher, "dep:%s:UNKNOWN\n", dep)
		}
	}

	// 5. Tool Version
	fmt.Fprintf(hasher, "tool_version:%s\n", toolVersion)

	return hex.EncodeToString(hasher.Sum(nil)), nil
}

func hashConfig(w io.Writer, cfg TaskConfig) error {
	// Params
	params := cfg.Params()
	if len(params) > 0 {
		// JSON marshal params for consistent hashing
		// Note: map keys in JSON are sorted
		data, err := json.Marshal(params)
		if err != nil {
			return err
		}
		fmt.Fprintf(w, "params:%s\n", string(data))
	}

	// Env
	env := cfg.Env()
	keys := make([]string, 0, len(env))
	for k := range env {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		fmt.Fprintf(w, "env:%s=%s\n", k, env[k])
	}

	// Mounts
	mounts := cfg.Mounts()
	keys = make([]string, 0, len(mounts))
	for k := range mounts {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		fmt.Fprintf(w, "mount:%s=%s\n", k, mounts[k])
	}

	return nil
}

func resolveInputs(globs []vfs.Glob, vfsInstance vfs.VFS) ([]vfs.File, error) {
	var files []vfs.File
	seen := make(map[string]bool)

	for _, g := range globs {
		entries, err := vfsInstance.Find(g, vfs.FindOptions{IncludeShadowed: false})
		if err != nil {
			return nil, err
		}

		for _, entry := range entries {
			if entry.Kind() == vfs.KindFile {
				// Dedup
				path := entry.Path().String()
				if !seen[path] {
					seen[path] = true
					if f, ok := entry.(vfs.File); ok {
						files = append(files, f)
					}
				}
			}
		}
	}
	return files, nil
}
