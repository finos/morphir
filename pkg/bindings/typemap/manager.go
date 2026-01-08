package typemap

import "sync"

// Manager manages registries for multiple bindings.
// Thread-safe for concurrent access.
type Manager struct {
	mu         sync.RWMutex
	registries map[string]*Registry
}

// NewManager creates a new registry manager.
func NewManager() *Manager {
	return &Manager{
		registries: make(map[string]*Registry),
	}
}

// Register adds or replaces a registry for a binding.
func (m *Manager) Register(registry *Registry) {
	if registry == nil {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.registries[registry.BindingName()] = registry
}

// Get retrieves a registry by binding name.
// Returns nil if not found.
func (m *Manager) Get(bindingName string) *Registry {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.registries[bindingName]
}

// MustGet retrieves a registry, panicking if not found.
// Use only when the registry is known to exist.
func (m *Manager) MustGet(bindingName string) *Registry {
	r := m.Get(bindingName)
	if r == nil {
		panic("typemap: registry not found: " + bindingName)
	}
	return r
}

// Has returns true if a registry exists for the binding.
func (m *Manager) Has(bindingName string) bool {
	m.mu.RLock()
	defer m.mu.RUnlock()
	_, ok := m.registries[bindingName]
	return ok
}

// Names returns the names of all registered bindings.
func (m *Manager) Names() []string {
	m.mu.RLock()
	defer m.mu.RUnlock()
	names := make([]string, 0, len(m.registries))
	for name := range m.registries {
		names = append(names, name)
	}
	return names
}

// DefaultManager is the global default manager.
var DefaultManager = NewManager()

// Register adds a registry to the default manager.
func Register(registry *Registry) {
	DefaultManager.Register(registry)
}

// Get retrieves a registry from the default manager.
func Get(bindingName string) *Registry {
	return DefaultManager.Get(bindingName)
}

// MustGet retrieves a registry from the default manager, panicking if not found.
func MustGet(bindingName string) *Registry {
	return DefaultManager.MustGet(bindingName)
}

// Has returns true if the default manager has a registry for the binding.
func Has(bindingName string) bool {
	return DefaultManager.Has(bindingName)
}
