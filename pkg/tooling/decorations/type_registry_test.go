package decorations

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestTypeRegistry_Register(t *testing.T) {
	registry := NewTypeRegistry()

	decType := DecorationType{
		ID:           "test",
		DisplayName:  "Test Decoration",
		IRPath:       "test.json",
		EntryPoint:   "Test:Module:Type",
		Source:       "workspace",
		RegisteredAt: time.Now(),
	}

	registry.Register(decType)

	if !registry.Has("test") {
		t.Error("expected decoration type to be registered")
	}

	got, found := registry.Get("test")
	if !found {
		t.Fatal("expected decoration type to be found")
	}

	if got.ID != "test" {
		t.Errorf("ID: got %q, want %q", got.ID, "test")
	}
}

func TestTypeRegistry_Unregister(t *testing.T) {
	registry := NewTypeRegistry()

	decType := DecorationType{
		ID:           "test",
		DisplayName:  "Test",
		IRPath:       "test.json",
		EntryPoint:   "Test:Module:Type",
		Source:       "workspace",
		RegisteredAt: time.Now(),
	}

	registry.Register(decType)
	if !registry.Unregister("test") {
		t.Error("expected unregister to return true")
	}

	if registry.Has("test") {
		t.Error("expected decoration type to be unregistered")
	}

	if registry.Unregister("nonexistent") {
		t.Error("expected unregister to return false for nonexistent type")
	}
}

func TestTypeRegistry_Merge(t *testing.T) {
	registry1 := NewTypeRegistry()
	registry2 := NewTypeRegistry()

	decType1 := DecorationType{
		ID:           "type1",
		DisplayName:  "Type 1",
		IRPath:       "type1.json",
		EntryPoint:   "Type1:Module:Type",
		Source:       "workspace",
		RegisteredAt: time.Now(),
	}

	decType2 := DecorationType{
		ID:           "type2",
		DisplayName:  "Type 2",
		IRPath:       "type2.json",
		EntryPoint:   "Type2:Module:Type",
		Source:       "global",
		RegisteredAt: time.Now(),
	}

	registry1.Register(decType1)
	registry2.Register(decType2)

	registry1.Merge(registry2)

	if registry1.Count() != 2 {
		t.Errorf("Count: got %d, want 2", registry1.Count())
	}

	if !registry1.Has("type1") {
		t.Error("expected type1 to be present")
	}

	if !registry1.Has("type2") {
		t.Error("expected type2 to be present")
	}
}

func TestLoadTypeRegistry_FileNotExists(t *testing.T) {
	tmpDir := t.TempDir()
	registryPath := filepath.Join(tmpDir, "nonexistent.json")

	registry, err := LoadTypeRegistry(registryPath)
	if err != nil {
		t.Fatalf("LoadTypeRegistry: unexpected error: %v", err)
	}

	if registry.Count() != 0 {
		t.Errorf("expected empty registry, got %d types", registry.Count())
	}
}

func TestLoadTypeRegistry_FileExists(t *testing.T) {
	tmpDir := t.TempDir()
	registryPath := filepath.Join(tmpDir, "registry.json")

	// Create a registry file
	registry := NewTypeRegistry()
	decType := DecorationType{
		ID:           "test",
		DisplayName:  "Test",
		IRPath:       "test.json",
		EntryPoint:   "Test:Module:Type",
		Source:       "workspace",
		RegisteredAt: time.Now(),
	}
	registry.Register(decType)

	if err := registry.Save(registryPath); err != nil {
		t.Fatalf("Save: %v", err)
	}

	// Load it back
	loaded, err := LoadTypeRegistry(registryPath)
	if err != nil {
		t.Fatalf("LoadTypeRegistry: %v", err)
	}

	if loaded.Count() != 1 {
		t.Errorf("Count: got %d, want 1", loaded.Count())
	}

	got, found := loaded.Get("test")
	if !found {
		t.Fatal("expected decoration type to be found")
	}

	if got.DisplayName != "Test" {
		t.Errorf("DisplayName: got %q, want %q", got.DisplayName, "Test")
	}
}

func TestTypeRegistry_Save(t *testing.T) {
	tmpDir := t.TempDir()
	registryPath := filepath.Join(tmpDir, "registry.json")

	registry := NewTypeRegistry()
	decType := DecorationType{
		ID:           "test",
		DisplayName:  "Test Decoration",
		Description:  "A test decoration",
		IRPath:       "test.json",
		EntryPoint:   "Test:Module:Type",
		Source:       "workspace",
		RegisteredAt: time.Now(),
	}
	registry.Register(decType)

	if err := registry.Save(registryPath); err != nil {
		t.Fatalf("Save: %v", err)
	}

	// Verify file exists
	if _, err := os.Stat(registryPath); os.IsNotExist(err) {
		t.Fatal("expected registry file to be created")
	}

	// Load and verify
	loaded, err := LoadTypeRegistry(registryPath)
	if err != nil {
		t.Fatalf("LoadTypeRegistry: %v", err)
	}

	if loaded.Count() != 1 {
		t.Errorf("Count: got %d, want 1", loaded.Count())
	}
}

func TestTypeRegistry_ListBySource(t *testing.T) {
	registry := NewTypeRegistry()

	decType1 := DecorationType{
		ID:           "workspace-type",
		DisplayName:  "Workspace Type",
		IRPath:       "workspace.json",
		EntryPoint:   "Workspace:Module:Type",
		Source:       "workspace",
		RegisteredAt: time.Now(),
	}

	decType2 := DecorationType{
		ID:           "global-type",
		DisplayName:  "Global Type",
		IRPath:       "global.json",
		EntryPoint:   "Global:Module:Type",
		Source:       "global",
		RegisteredAt: time.Now(),
	}

	registry.Register(decType1)
	registry.Register(decType2)

	workspaceTypes := registry.ListBySource("workspace")
	if len(workspaceTypes) != 1 {
		t.Errorf("ListBySource(workspace): got %d, want 1", len(workspaceTypes))
	}

	globalTypes := registry.ListBySource("global")
	if len(globalTypes) != 1 {
		t.Errorf("ListBySource(global): got %d, want 1", len(globalTypes))
	}

	systemTypes := registry.ListBySource("system")
	if len(systemTypes) != 0 {
		t.Errorf("ListBySource(system): got %d, want 0", len(systemTypes))
	}
}
