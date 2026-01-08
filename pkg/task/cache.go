package task

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/finos/morphir/pkg/pipeline"
)

// CacheEntry represents a cached task execution result.
type CacheEntry struct {
	TaskName    string    `json:"task_name"`
	InputHash   string    `json:"input_hash"`
	Output      any       `json:"output"`
	Diagnostics []pipeline.Diagnostic `json:"diagnostics"`
	Timestamp   time.Time `json:"timestamp"`
}

// CacheManager handles storage and retrieval of task results.
type CacheManager struct {
	cacheDir string
	metaFile string
	entries  map[string]CacheEntry // map[InputHash]CacheEntry
	mu       sync.RWMutex
}

// NewCacheManager creates a new cache manager.
func NewCacheManager(projectRoot string) (*CacheManager, error) {
	cacheDir := filepath.Join(projectRoot, ".morphir", "cache")
	if err := os.MkdirAll(cacheDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create cache dir: %w", err)
	}

	cm := &CacheManager{
		cacheDir: cacheDir,
		metaFile: filepath.Join(cacheDir, "meta.json"),
		entries:  make(map[string]CacheEntry),
	}

	if err := cm.load(); err != nil {
		// If load fails, just start with empty cache (unless it's a permission error?)
		// For now, log and ignore or just ignore if file doesn't exist
		if !os.IsNotExist(err) {
			// fmt.Printf("Warning: failed to load cache: %v\n", err)
		}
	}

	return cm, nil
}

// load reads the cache metadata from disk.
func (cm *CacheManager) load() error {
	cm.mu.Lock()
	defer cm.mu.Unlock()

	data, err := os.ReadFile(cm.metaFile)
	if err != nil {
		return err
	}

	if len(data) == 0 {
		return nil
	}

	return json.Unmarshal(data, &cm.entries)
}

// save writes the cache metadata to disk.
func (cm *CacheManager) save() error {
	cm.mu.RLock()
	defer cm.mu.RUnlock()

	data, err := json.MarshalIndent(cm.entries, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(cm.metaFile, data, 0644)
}

// Get retrieves a cached result if it exists.
func (cm *CacheManager) Get(inputHash string) (TaskResult, bool) {
	cm.mu.RLock()
	entry, ok := cm.entries[inputHash]
	cm.mu.RUnlock()

	if !ok {
		return TaskResult{}, false
	}

	// Reconstruct TaskResult
	// Note: We don't verify artifacts existence yet, assuming they persist if cache persists

	return TaskResult{
		Name:        entry.TaskName,
		Output:      entry.Output,
		Diagnostics: entry.Diagnostics,
		// Artifacts: ... // We assume artifacts are still on disk if they were file outputs.
                         // But TaskResult.Artifacts is []pipeline.Artifact which has Content []byte?
                         // If artifacts are large, we probably didn't cache content in meta.json.
                         // For now, let's assume valid cache hit implies side-effects are done.
	}, true
}

// Put stores a result in the cache.
func (cm *CacheManager) Put(inputHash string, result TaskResult) error {
	cm.mu.Lock()
	defer cm.mu.Unlock()

	entry := CacheEntry{
		TaskName:    result.Name,
		InputHash:   inputHash,
		Output:      result.Output,
		Diagnostics: result.Diagnostics,
		Timestamp:   time.Now(),
	}
	cm.entries[inputHash] = entry
    
    // Write immediately? Or batch? For now, write immediately for safety.
    // We need to release lock to call save? No, save takes lock.
    // For now I did it to refactor save to not take lock or call internalSave
    
    data, err := json.MarshalIndent(cm.entries, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(cm.metaFile, data, 0644)
}
