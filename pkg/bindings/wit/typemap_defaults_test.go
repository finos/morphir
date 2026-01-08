package wit_test

import (
	"testing"

	"github.com/finos/morphir/pkg/bindings/typemap"
	"github.com/finos/morphir/pkg/bindings/wit"
)

func TestWITDefaults(t *testing.T) {
	defaults := wit.WITDefaults{}

	t.Run("primitives count", func(t *testing.T) {
		prims := defaults.DefaultPrimitives()
		// bool, u8-u64 (4), s8-s64 (4), f32-f64 (2), string, char = 13
		if len(prims) != 13 {
			t.Errorf("expected 13 primitives, got %d", len(prims))
		}
	})

	t.Run("containers count", func(t *testing.T) {
		containers := defaults.DefaultContainers()
		// list, option, result, tuple = 4
		if len(containers) != 4 {
			t.Errorf("expected 4 containers, got %d", len(containers))
		}
	})
}

func TestNewWITRegistry(t *testing.T) {
	t.Run("default registry", func(t *testing.T) {
		r := wit.DefaultWITRegistry()

		if r.BindingName() != "wit" {
			t.Errorf("BindingName() = %q, want %q", r.BindingName(), "wit")
		}

		// Check primitive count
		if r.PrimitiveCount() != 13 {
			t.Errorf("PrimitiveCount() = %d, want 13", r.PrimitiveCount())
		}

		// Check container count
		if r.ContainerCount() != 4 {
			t.Errorf("ContainerCount() = %d, want 4", r.ContainerCount())
		}
	})

	t.Run("lookup primitives", func(t *testing.T) {
		r := wit.DefaultWITRegistry()

		tests := []struct {
			external      string
			wantPrimitive string
		}{
			{"bool", "Bool"},
			{"u8", "Int"},
			{"u32", "Int"},
			{"s64", "Int"},
			{"f32", "Float"},
			{"f64", "Float"},
			{"string", "String"},
			{"char", "Char"},
		}

		for _, tt := range tests {
			m, ok := r.Lookup(typemap.TypeID(tt.external))
			if !ok {
				t.Errorf("Lookup(%q) not found", tt.external)
				continue
			}
			if m.MorphirType.PrimitiveKind != tt.wantPrimitive {
				t.Errorf("Lookup(%q).MorphirType.PrimitiveKind = %q, want %q",
					tt.external, m.MorphirType.PrimitiveKind, tt.wantPrimitive)
			}
		}
	})

	t.Run("lookup containers", func(t *testing.T) {
		r := wit.DefaultWITRegistry()

		tests := []struct {
			pattern      string
			wantMorphir  string
			wantParamCnt int
		}{
			{"list", "Morphir.SDK:List:List", 1},
			{"option", "Morphir.SDK:Maybe:Maybe", 1},
			{"result", "Morphir.SDK:Result:Result", 2},
			{"tuple", "tuple", -1},
		}

		for _, tt := range tests {
			c, ok := r.LookupContainer(tt.pattern)
			if !ok {
				t.Errorf("LookupContainer(%q) not found", tt.pattern)
				continue
			}
			if c.MorphirPattern != tt.wantMorphir {
				t.Errorf("LookupContainer(%q).MorphirPattern = %q, want %q",
					tt.pattern, c.MorphirPattern, tt.wantMorphir)
			}
			if c.TypeParamCount != tt.wantParamCnt {
				t.Errorf("LookupContainer(%q).TypeParamCount = %d, want %d",
					tt.pattern, c.TypeParamCount, tt.wantParamCnt)
			}
		}
	})

	t.Run("reverse lookup", func(t *testing.T) {
		r := wit.DefaultWITRegistry()

		// Bool should reverse to "bool"
		m, ok := r.LookupReverse(typemap.MorphirTypeRef{PrimitiveKind: "Bool"})
		if !ok {
			t.Error("LookupReverse(Bool) not found")
		} else if m.ExternalType != "bool" {
			t.Errorf("LookupReverse(Bool).ExternalType = %q, want %q", m.ExternalType, "bool")
		}

		// String should reverse to "string"
		m, ok = r.LookupReverse(typemap.MorphirTypeRef{PrimitiveKind: "String"})
		if !ok {
			t.Error("LookupReverse(String) not found")
		} else if m.ExternalType != "string" {
			t.Errorf("LookupReverse(String).ExternalType = %q, want %q", m.ExternalType, "string")
		}
	})

	t.Run("container reverse lookup", func(t *testing.T) {
		r := wit.DefaultWITRegistry()

		// Morphir.SDK:List:List should reverse to "list"
		c, ok := r.LookupContainerReverse("Morphir.SDK:List:List")
		if !ok {
			t.Error("LookupContainerReverse(Morphir.SDK:List:List) not found")
		} else if c.ExternalPattern != "list" {
			t.Errorf("LookupContainerReverse(List).ExternalPattern = %q, want %q",
				c.ExternalPattern, "list")
		}
	})
}

func TestWITRegistryWithConfig(t *testing.T) {
	t.Run("config override", func(t *testing.T) {
		cfg := typemap.TypeMappingConfig{
			Primitives: []typemap.PrimitiveMappingConfig{
				{
					ExternalType:  "u128",
					MorphirType:   "Morphir.SDK:Int:Int128",
					Bidirectional: true,
					Priority:      100,
				},
			},
		}

		r := wit.NewWITRegistry(cfg)

		// Should have default primitives + 1 custom
		// Actually, the builder deduplicates by external type, so we have 13 defaults + 1 new = 14
		if r.PrimitiveCount() != 14 {
			t.Errorf("PrimitiveCount() = %d, want 14", r.PrimitiveCount())
		}

		// Should find the custom mapping
		m, ok := r.Lookup("u128")
		if !ok {
			t.Error("expected to find u128")
		}
		if m.MorphirType.FQName != "Morphir.SDK:Int:Int128" {
			t.Errorf("MorphirType.FQName = %q, want %q",
				m.MorphirType.FQName, "Morphir.SDK:Int:Int128")
		}
	})

	t.Run("priority override", func(t *testing.T) {
		cfg := typemap.TypeMappingConfig{
			Primitives: []typemap.PrimitiveMappingConfig{
				{
					ExternalType:  "u32",
					MorphirType:   "Morphir.SDK:Int:UInt32",
					Bidirectional: true,
					Priority:      100, // Higher than default (0)
				},
			},
		}

		r := wit.NewWITRegistry(cfg)

		m, ok := r.Lookup("u32")
		if !ok {
			t.Error("expected to find u32")
		}

		// Higher priority config should win
		if m.MorphirType.FQName != "Morphir.SDK:Int:UInt32" {
			t.Errorf("MorphirType.FQName = %q, want %q",
				m.MorphirType.FQName, "Morphir.SDK:Int:UInt32")
		}
	})
}

func TestGlobalWITRegistry(t *testing.T) {
	// The init() function should have registered the WIT registry
	if !typemap.Has("wit") {
		t.Error("expected global registry to have 'wit' binding")
	}

	r := typemap.Get("wit")
	if r == nil {
		t.Error("expected non-nil registry for 'wit'")
	}

	if r.BindingName() != "wit" {
		t.Errorf("BindingName() = %q, want %q", r.BindingName(), "wit")
	}
}
