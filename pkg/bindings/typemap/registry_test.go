package typemap_test

import (
	"testing"

	"github.com/finos/morphir/pkg/bindings/typemap"
)

func TestParseMorphirTypeRef(t *testing.T) {
	tests := []struct {
		name        string
		input       string
		wantFQName  string
		wantPrimitive string
		wantErr     bool
	}{
		{
			name:          "primitive kind",
			input:         "Int",
			wantPrimitive: "Int",
		},
		{
			name:          "primitive kind with spaces",
			input:         "  Float  ",
			wantPrimitive: "Float",
		},
		{
			name:       "FQName",
			input:      "Morphir.SDK:Basics:Int",
			wantFQName: "Morphir.SDK:Basics:Int",
		},
		{
			name:       "FQName with complex path",
			input:      "MyPackage.Foo:MyModule.Bar:myType",
			wantFQName: "MyPackage.Foo:MyModule.Bar:myType",
		},
		{
			name:    "empty string",
			input:   "",
			wantErr: true,
		},
		{
			name:    "invalid FQName - too few parts",
			input:   "Foo:Bar",
			wantErr: true,
		},
		{
			name:    "invalid FQName - too many parts",
			input:   "A:B:C:D",
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ref, err := typemap.ParseMorphirTypeRef(tt.input)
			if tt.wantErr {
				if err == nil {
					t.Errorf("expected error, got nil")
				}
				return
			}
			if err != nil {
				t.Errorf("unexpected error: %v", err)
				return
			}
			if ref.FQName != tt.wantFQName {
				t.Errorf("FQName = %q, want %q", ref.FQName, tt.wantFQName)
			}
			if ref.PrimitiveKind != tt.wantPrimitive {
				t.Errorf("PrimitiveKind = %q, want %q", ref.PrimitiveKind, tt.wantPrimitive)
			}
		})
	}
}

func TestMorphirTypeRef(t *testing.T) {
	t.Run("String", func(t *testing.T) {
		tests := []struct {
			ref  typemap.MorphirTypeRef
			want string
		}{
			{typemap.MorphirTypeRef{PrimitiveKind: "Int"}, "Int"},
			{typemap.MorphirTypeRef{FQName: "A:B:c"}, "A:B:c"},
			{typemap.MorphirTypeRef{}, ""},
		}
		for _, tt := range tests {
			if got := tt.ref.String(); got != tt.want {
				t.Errorf("String() = %q, want %q", got, tt.want)
			}
		}
	})

	t.Run("IsEmpty", func(t *testing.T) {
		emptyRef := typemap.MorphirTypeRef{}
		if !emptyRef.IsEmpty() {
			t.Error("empty ref should be empty")
		}
		primitiveRef := typemap.MorphirTypeRef{PrimitiveKind: "Int"}
		if primitiveRef.IsEmpty() {
			t.Error("primitive ref should not be empty")
		}
	})

	t.Run("IsPrimitive", func(t *testing.T) {
		primitiveRef := typemap.MorphirTypeRef{PrimitiveKind: "Int"}
		if !primitiveRef.IsPrimitive() {
			t.Error("expected IsPrimitive true")
		}
		fqnRef := typemap.MorphirTypeRef{FQName: "A:B:c"}
		if fqnRef.IsPrimitive() {
			t.Error("expected IsPrimitive false for FQName")
		}
	})

	t.Run("IsFQName", func(t *testing.T) {
		fqnRef := typemap.MorphirTypeRef{FQName: "A:B:c"}
		if !fqnRef.IsFQName() {
			t.Error("expected IsFQName true")
		}
		primitiveRef := typemap.MorphirTypeRef{PrimitiveKind: "Int"}
		if primitiveRef.IsFQName() {
			t.Error("expected IsFQName false for primitive")
		}
	})
}

func TestBuilder(t *testing.T) {
	t.Run("empty builder", func(t *testing.T) {
		r := typemap.NewBuilder("test").Build()
		if r.BindingName() != "test" {
			t.Errorf("BindingName() = %q, want %q", r.BindingName(), "test")
		}
		if r.PrimitiveCount() != 0 {
			t.Errorf("PrimitiveCount() = %d, want 0", r.PrimitiveCount())
		}
		if r.ContainerCount() != 0 {
			t.Errorf("ContainerCount() = %d, want 0", r.ContainerCount())
		}
	})

	t.Run("add primitives", func(t *testing.T) {
		r := typemap.NewBuilder("test").
			AddPrimitive("u32", "Int").
			AddPrimitive("bool", "Bool").
			Build()

		if r.PrimitiveCount() != 2 {
			t.Errorf("PrimitiveCount() = %d, want 2", r.PrimitiveCount())
		}

		m, ok := r.Lookup("u32")
		if !ok {
			t.Error("expected to find u32")
		}
		if m.MorphirType.PrimitiveKind != "Int" {
			t.Errorf("MorphirType.PrimitiveKind = %q, want %q", m.MorphirType.PrimitiveKind, "Int")
		}
	})

	t.Run("add containers", func(t *testing.T) {
		r := typemap.NewBuilder("test").
			AddContainer("list", "Morphir.SDK:List:List", 1).
			AddContainer("option", "Morphir.SDK:Maybe:Maybe", 1).
			Build()

		if r.ContainerCount() != 2 {
			t.Errorf("ContainerCount() = %d, want 2", r.ContainerCount())
		}

		c, ok := r.LookupContainer("list")
		if !ok {
			t.Error("expected to find list")
		}
		if c.TypeParamCount != 1 {
			t.Errorf("TypeParamCount = %d, want 1", c.TypeParamCount)
		}
	})

	t.Run("priority override", func(t *testing.T) {
		r := typemap.NewBuilder("test").
			AddPrimitive("u32", "Int", typemap.WithPriority(0)).
			AddPrimitive("u32", "Int64", typemap.WithPriority(100)).
			Build()

		m, ok := r.Lookup("u32")
		if !ok {
			t.Error("expected to find u32")
		}
		// Higher priority should win
		if m.MorphirType.PrimitiveKind != "Int64" {
			t.Errorf("MorphirType.PrimitiveKind = %q, want %q", m.MorphirType.PrimitiveKind, "Int64")
		}
	})
}

func TestRegistry(t *testing.T) {
	t.Run("nil registry", func(t *testing.T) {
		var r *typemap.Registry
		if _, ok := r.Lookup("foo"); ok {
			t.Error("expected not found for nil registry")
		}
		if _, ok := r.LookupReverse(typemap.MorphirTypeRef{PrimitiveKind: "Int"}); ok {
			t.Error("expected not found for nil registry")
		}
		if _, ok := r.LookupContainer("list"); ok {
			t.Error("expected not found for nil registry")
		}
		if r.PrimitiveCount() != 0 {
			t.Error("expected 0 count for nil registry")
		}
	})

	t.Run("reverse lookup", func(t *testing.T) {
		r := typemap.NewBuilder("test").
			AddPrimitive("u32", "Int").
			Build()

		m, ok := r.LookupReverse(typemap.MorphirTypeRef{PrimitiveKind: "Int"})
		if !ok {
			t.Error("expected to find reverse mapping")
		}
		if m.ExternalType != "u32" {
			t.Errorf("ExternalType = %q, want %q", m.ExternalType, "u32")
		}
	})

	t.Run("container reverse lookup", func(t *testing.T) {
		r := typemap.NewBuilder("test").
			AddContainer("list", "Morphir.SDK:List:List", 1).
			Build()

		c, ok := r.LookupContainerReverse("Morphir.SDK:List:List")
		if !ok {
			t.Error("expected to find reverse container mapping")
		}
		if c.ExternalPattern != "list" {
			t.Errorf("ExternalPattern = %q, want %q", c.ExternalPattern, "list")
		}
	})

	t.Run("all primitives returns copy", func(t *testing.T) {
		r := typemap.NewBuilder("test").
			AddPrimitive("u32", "Int").
			Build()

		all := r.AllPrimitives()
		if len(all) != 1 {
			t.Errorf("len(AllPrimitives()) = %d, want 1", len(all))
		}
	})
}

func TestManager(t *testing.T) {
	t.Run("register and get", func(t *testing.T) {
		m := typemap.NewManager()
		r := typemap.NewBuilder("wit").
			AddPrimitive("u32", "Int").
			Build()

		m.Register(r)

		got := m.Get("wit")
		if got != r {
			t.Error("expected to get same registry")
		}

		if m.Get("unknown") != nil {
			t.Error("expected nil for unknown binding")
		}
	})

	t.Run("has", func(t *testing.T) {
		m := typemap.NewManager()
		r := typemap.NewBuilder("wit").Build()
		m.Register(r)

		if !m.Has("wit") {
			t.Error("expected Has(wit) = true")
		}
		if m.Has("unknown") {
			t.Error("expected Has(unknown) = false")
		}
	})

	t.Run("names", func(t *testing.T) {
		m := typemap.NewManager()
		m.Register(typemap.NewBuilder("wit").Build())
		m.Register(typemap.NewBuilder("protobuf").Build())

		names := m.Names()
		if len(names) != 2 {
			t.Errorf("len(Names()) = %d, want 2", len(names))
		}
	})

	t.Run("must get panics", func(t *testing.T) {
		m := typemap.NewManager()
		defer func() {
			if r := recover(); r == nil {
				t.Error("expected panic")
			}
		}()
		m.MustGet("unknown")
	})

	t.Run("register nil is no-op", func(t *testing.T) {
		m := typemap.NewManager()
		m.Register(nil) // Should not panic
		if len(m.Names()) != 0 {
			t.Error("expected no registries after registering nil")
		}
	})
}

func TestDefaultManager(t *testing.T) {
	// Save and restore default manager state
	oldManager := typemap.DefaultManager

	// Create a fresh manager for testing
	typemap.DefaultManager = typemap.NewManager()
	defer func() {
		typemap.DefaultManager = oldManager
	}()

	r := typemap.NewBuilder("test-binding").
		AddPrimitive("test", "Test").
		Build()

	typemap.Register(r)

	if !typemap.Has("test-binding") {
		t.Error("expected Has = true")
	}

	got := typemap.Get("test-binding")
	if got != r {
		t.Error("expected to get same registry")
	}
}

// mockDefaults implements DefaultsProvider for testing
type mockDefaults struct {
	primitives []typemap.TypeMapping
	containers []typemap.ContainerMapping
}

func (m mockDefaults) DefaultPrimitives() []typemap.TypeMapping {
	return m.primitives
}

func (m mockDefaults) DefaultContainers() []typemap.ContainerMapping {
	return m.containers
}

func TestWithDefaults(t *testing.T) {
	defaults := mockDefaults{
		primitives: []typemap.TypeMapping{
			{ExternalType: "bool", MorphirType: typemap.MorphirTypeRef{PrimitiveKind: "Bool"}, Bidirectional: true},
			{ExternalType: "string", MorphirType: typemap.MorphirTypeRef{PrimitiveKind: "String"}, Bidirectional: true},
		},
		containers: []typemap.ContainerMapping{
			{ExternalPattern: "list", MorphirPattern: "Morphir.SDK:List:List", TypeParamCount: 1, Bidirectional: true},
		},
	}

	r := typemap.NewBuilder("test").
		WithDefaults(defaults).
		Build()

	if r.PrimitiveCount() != 2 {
		t.Errorf("PrimitiveCount() = %d, want 2", r.PrimitiveCount())
	}
	if r.ContainerCount() != 1 {
		t.Errorf("ContainerCount() = %d, want 1", r.ContainerCount())
	}

	m, ok := r.Lookup("bool")
	if !ok {
		t.Error("expected to find bool")
	}
	if m.MorphirType.PrimitiveKind != "Bool" {
		t.Errorf("MorphirType.PrimitiveKind = %q, want %q", m.MorphirType.PrimitiveKind, "Bool")
	}
}

func TestWithConfig(t *testing.T) {
	cfg := typemap.TypeMappingConfig{
		Primitives: []typemap.PrimitiveMappingConfig{
			{ExternalType: "u128", MorphirType: "Morphir.SDK:Int:Int128", Bidirectional: true, Priority: 100},
		},
		Containers: []typemap.ContainerMappingConfig{
			{ExternalPattern: "hashmap", MorphirPattern: "Morphir.SDK:Dict:Dict", TypeParamCount: 2, Bidirectional: true, Priority: 100},
		},
	}

	r := typemap.NewBuilder("test").
		WithConfig(cfg).
		Build()

	if r.PrimitiveCount() != 1 {
		t.Errorf("PrimitiveCount() = %d, want 1", r.PrimitiveCount())
	}

	m, ok := r.Lookup("u128")
	if !ok {
		t.Error("expected to find u128")
	}
	if m.MorphirType.FQName != "Morphir.SDK:Int:Int128" {
		t.Errorf("MorphirType.FQName = %q, want %q", m.MorphirType.FQName, "Morphir.SDK:Int:Int128")
	}

	c, ok := r.LookupContainer("hashmap")
	if !ok {
		t.Error("expected to find hashmap")
	}
	if c.TypeParamCount != 2 {
		t.Errorf("TypeParamCount = %d, want 2", c.TypeParamCount)
	}
}

func TestConfigOverridesDefaults(t *testing.T) {
	defaults := mockDefaults{
		primitives: []typemap.TypeMapping{
			{ExternalType: "u32", MorphirType: typemap.MorphirTypeRef{PrimitiveKind: "Int"}, Bidirectional: true, Priority: 0},
		},
	}

	cfg := typemap.TypeMappingConfig{
		Primitives: []typemap.PrimitiveMappingConfig{
			{ExternalType: "u32", MorphirType: "Int64", Bidirectional: true, Priority: 100},
		},
	}

	r := typemap.NewBuilder("test").
		WithDefaults(defaults).
		WithConfig(cfg).
		Build()

	m, ok := r.Lookup("u32")
	if !ok {
		t.Error("expected to find u32")
	}
	// Config should override defaults due to higher priority
	if m.MorphirType.PrimitiveKind != "Int64" {
		t.Errorf("MorphirType.PrimitiveKind = %q, want %q", m.MorphirType.PrimitiveKind, "Int64")
	}
}
