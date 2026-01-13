package decorations

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// DecorationType represents a registered decoration type in the registry.
type DecorationType struct {
	ID           string    `json:"id"`
	DisplayName  string    `json:"display_name"`
	Description  string    `json:"description,omitempty"`
	IRPath       string    `json:"ir_path"`
	EntryPoint   string    `json:"entry_point"`
	Source       string    `json:"source"` // "workspace", "global", "system"
	RegisteredAt time.Time `json:"registered_at"`
}

// TypeRegistry manages a collection of registered decoration types.
type TypeRegistry struct {
	types map[string]DecorationType
}

// NewTypeRegistry creates a new empty type registry.
func NewTypeRegistry() *TypeRegistry {
	return &TypeRegistry{
		types: make(map[string]DecorationType),
	}
}

// Register adds or updates a decoration type in the registry.
func (r *TypeRegistry) Register(decType DecorationType) {
	r.types[decType.ID] = decType
}

// Get retrieves a decoration type by ID.
// Returns (type, found).
func (r *TypeRegistry) Get(id string) (DecorationType, bool) {
	decType, found := r.types[id]
	return decType, found
}

// List returns all registered decoration types.
func (r *TypeRegistry) List() []DecorationType {
	result := make([]DecorationType, 0, len(r.types))
	for _, decType := range r.types {
		result = append(result, decType)
	}
	return result
}

// ListBySource returns decoration types filtered by source.
func (r *TypeRegistry) ListBySource(source string) []DecorationType {
	result := make([]DecorationType, 0)
	for _, decType := range r.types {
		if decType.Source == source {
			result = append(result, decType)
		}
	}
	return result
}

// Unregister removes a decoration type from the registry.
func (r *TypeRegistry) Unregister(id string) bool {
	if _, found := r.types[id]; found {
		delete(r.types, id)
		return true
	}
	return false
}

// Has checks if a decoration type is registered.
func (r *TypeRegistry) Has(id string) bool {
	_, found := r.types[id]
	return found
}

// Count returns the number of registered types.
func (r *TypeRegistry) Count() int {
	return len(r.types)
}

// Merge merges another registry into this one.
// Types from the other registry take precedence if IDs conflict.
func (r *TypeRegistry) Merge(other *TypeRegistry) {
	if other == nil {
		return
	}
	for id, decType := range other.types {
		r.types[id] = decType
	}
}

// typeRegistryFile represents the JSON structure of a registry file.
type typeRegistryFile struct {
	Version string                    `json:"version"`
	Types   map[string]DecorationType `json:"types"`
}

// LoadTypeRegistry loads a type registry from a file.
func LoadTypeRegistry(filePath string) (*TypeRegistry, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		if os.IsNotExist(err) {
			// Return empty registry if file doesn't exist
			return NewTypeRegistry(), nil
		}
		return nil, fmt.Errorf("read registry file: %w", err)
	}

	var file typeRegistryFile
	if err := json.Unmarshal(data, &file); err != nil {
		return nil, fmt.Errorf("parse registry file: %w", err)
	}

	registry := NewTypeRegistry()
	for id, decType := range file.Types {
		decType.ID = id // Ensure ID matches key
		registry.Register(decType)
	}

	return registry, nil
}

// Save saves the type registry to a file.
func (r *TypeRegistry) Save(filePath string) error {
	// Ensure directory exists
	dir := filepath.Dir(filePath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("create registry directory: %w", err)
	}

	file := typeRegistryFile{
		Version: "1.0",
		Types:   r.types,
	}

	data, err := json.MarshalIndent(file, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal registry: %w", err)
	}

	if err := os.WriteFile(filePath, data, 0644); err != nil {
		return fmt.Errorf("write registry file: %w", err)
	}

	return nil
}

// LoadMergedTypeRegistry loads and merges type registries from multiple sources.
// Priority: workspace > global > system
func LoadMergedTypeRegistry(workspacePath, globalPath, systemPath string) (*TypeRegistry, error) {
	registry := NewTypeRegistry()

	// Load system registry (lowest priority)
	if systemPath != "" {
		systemReg, err := LoadTypeRegistry(systemPath)
		if err != nil {
			return nil, fmt.Errorf("load system registry: %w", err)
		}
		registry.Merge(systemReg)
	}

	// Load global registry (medium priority)
	if globalPath != "" {
		globalReg, err := LoadTypeRegistry(globalPath)
		if err != nil {
			return nil, fmt.Errorf("load global registry: %w", err)
		}
		registry.Merge(globalReg)
	}

	// Load workspace registry (highest priority)
	if workspacePath != "" {
		workspaceReg, err := LoadTypeRegistry(workspacePath)
		if err != nil {
			return nil, fmt.Errorf("load workspace registry: %w", err)
		}
		registry.Merge(workspaceReg)
	}

	return registry, nil
}

// GetRegistryPaths returns the standard registry file paths.
func GetRegistryPaths(workspaceRoot string) (workspacePath, globalPath, systemPath string) {
	// Workspace registry
	if workspaceRoot != "" {
		workspacePath = filepath.Join(workspaceRoot, ".morphir", "decorations", "registry.json")
	}

	// Global registry (user home)
	if homeDir, err := os.UserHomeDir(); err == nil {
		globalPath = filepath.Join(homeDir, ".morphir", "decorations", "registry.json")
	}

	// System registry
	systemPath = filepath.Join("/etc", "morphir", "decorations", "registry.json")

	return workspacePath, globalPath, systemPath
}

// ValidateDecorationType validates that a decoration type's IR file exists and entry point is valid.
// This function uses LoadDecorationIR and ValidateEntryPoint from the same package.
func ValidateDecorationType(decType DecorationType) error {
	// Check IR file exists
	if _, err := os.Stat(decType.IRPath); os.IsNotExist(err) {
		return fmt.Errorf("IR file not found: %s", decType.IRPath)
	}

	// Load and validate entry point
	decIR, err := LoadDecorationIR(decType.IRPath)
	if err != nil {
		return fmt.Errorf("load decoration IR: %w", err)
	}

	if err := ValidateEntryPoint(decIR, decType.EntryPoint); err != nil {
		return fmt.Errorf("validate entry point: %w", err)
	}

	return nil
}
