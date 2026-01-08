package pipeline_test

import (
	"testing"

	"github.com/finos/morphir/pkg/bindings/wit/domain"
	"github.com/finos/morphir/pkg/bindings/wit/pipeline"
	corePipeline "github.com/finos/morphir/pkg/pipeline"
)

func TestConvertToIR_PrimitiveTypes(t *testing.T) {
	tests := []struct {
		name         string
		witType      domain.PrimitiveKind
		wantLossy    bool
		wantTypeName string
	}{
		{"bool", domain.Bool, false, "Bool"},
		{"string", domain.String, false, "String"},
		{"char", domain.Char, false, "Char"},
		{"u8", domain.U8, true, "Int"},
		{"u16", domain.U16, true, "Int"},
		{"u32", domain.U32, true, "Int"},
		{"u64", domain.U64, true, "Int"},
		{"s8", domain.S8, true, "Int"},
		{"s16", domain.S16, true, "Int"},
		{"s32", domain.S32, true, "Int"},
		{"s64", domain.S64, true, "Int"},
		{"f32", domain.F32, true, "Float"},
		{"f64", domain.F64, false, "Float"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pkg := makePackageWithFunction("test-func", domain.PrimitiveType{Kind: tt.witType})
			module, diagnostics := pipeline.ConvertToIR(pkg, pipeline.MakeOptions{})

			// Check for lossy conversion warning
			if tt.wantLossy {
				if !pipeline.HasWarnings(diagnostics) {
					t.Errorf("expected warning for lossy type %s", tt.name)
				}
			}

			// Verify module was created
			if module.Values() == nil || len(module.Values()) == 0 {
				t.Errorf("expected at least one value definition")
			}
		})
	}
}

func TestConvertToIR_RecordType(t *testing.T) {
	pkg := domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("records"),
		Interfaces: []domain.Interface{
			{
				Name: domain.MustIdentifier("my-interface"),
				Types: []domain.TypeDef{
					{
						Name: domain.MustIdentifier("point"),
						Kind: domain.RecordDef{
							Fields: []domain.Field{
								{Name: domain.MustIdentifier("x"), Type: domain.PrimitiveType{Kind: domain.S32}},
								{Name: domain.MustIdentifier("y"), Type: domain.PrimitiveType{Kind: domain.S32}},
							},
						},
					},
				},
			},
		},
	}

	module, diagnostics := pipeline.ConvertToIR(pkg, pipeline.MakeOptions{})

	// Should have 2 warnings for s32 -> Int
	if len(pipeline.FilterBySeverity(diagnostics, corePipeline.SeverityWarn)) < 2 {
		t.Errorf("expected at least 2 warnings for s32 fields, got %d", len(diagnostics))
	}

	// Should have one type definition
	if module.Types() == nil || len(module.Types()) != 1 {
		t.Errorf("expected 1 type definition, got %d", len(module.Types()))
	}
}

func TestConvertToIR_VariantType(t *testing.T) {
	stringType := domain.PrimitiveType{Kind: domain.String}
	u32Type := domain.PrimitiveType{Kind: domain.U32}

	pkg := domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("variants"),
		Interfaces: []domain.Interface{
			{
				Name: domain.MustIdentifier("my-interface"),
				Types: []domain.TypeDef{
					{
						Name: domain.MustIdentifier("result"),
						Kind: domain.VariantDef{
							Cases: []domain.VariantCase{
								{Name: domain.MustIdentifier("ok"), Payload: typePtr(stringType)},
								{Name: domain.MustIdentifier("err"), Payload: typePtr(u32Type)},
							},
						},
					},
				},
			},
		},
	}

	module, diagnostics := pipeline.ConvertToIR(pkg, pipeline.MakeOptions{})

	// Should have at least 1 warning for u32 -> Int
	if !pipeline.HasWarnings(diagnostics) {
		t.Error("expected warning for u32 payload")
	}

	// Should have one type definition
	if module.Types() == nil || len(module.Types()) != 1 {
		t.Errorf("expected 1 type definition, got %d", len(module.Types()))
	}
}

func TestConvertToIR_EnumType(t *testing.T) {
	pkg := domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("enums"),
		Interfaces: []domain.Interface{
			{
				Name: domain.MustIdentifier("my-interface"),
				Types: []domain.TypeDef{
					{
						Name: domain.MustIdentifier("color"),
						Kind: domain.EnumDef{
							Cases: []domain.Identifier{
								domain.MustIdentifier("red"),
								domain.MustIdentifier("green"),
								domain.MustIdentifier("blue"),
							},
						},
					},
				},
			},
		},
	}

	module, diagnostics := pipeline.ConvertToIR(pkg, pipeline.MakeOptions{})

	// Enum conversion should be lossless
	if pipeline.HasErrors(diagnostics) {
		t.Errorf("unexpected errors: %v", diagnostics)
	}

	// Should have one type definition
	if module.Types() == nil || len(module.Types()) != 1 {
		t.Errorf("expected 1 type definition, got %d", len(module.Types()))
	}
}

func TestConvertToIR_FlagsType(t *testing.T) {
	pkg := domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("flags"),
		Interfaces: []domain.Interface{
			{
				Name: domain.MustIdentifier("my-interface"),
				Types: []domain.TypeDef{
					{
						Name: domain.MustIdentifier("permissions"),
						Kind: domain.FlagsDef{
							Flags: []domain.Identifier{
								domain.MustIdentifier("read"),
								domain.MustIdentifier("write"),
								domain.MustIdentifier("execute"),
							},
						},
					},
				},
			},
		},
	}

	t.Run("non-strict mode", func(t *testing.T) {
		module, diagnostics := pipeline.ConvertToIR(pkg, pipeline.MakeOptions{StrictMode: false})

		// Should have a warning for unsupported flags
		if !pipeline.HasWarnings(diagnostics) {
			t.Error("expected warning for unsupported flags type")
		}

		// Should still have a type definition (fallback to Int)
		if module.Types() == nil || len(module.Types()) != 1 {
			t.Errorf("expected 1 type definition (fallback), got %d", len(module.Types()))
		}
	})

	t.Run("strict mode", func(t *testing.T) {
		module, diagnostics := pipeline.ConvertToIR(pkg, pipeline.MakeOptions{StrictMode: true})

		// Should have an error for unsupported flags
		if !pipeline.HasErrors(diagnostics) {
			t.Error("expected error for unsupported flags type in strict mode")
		}

		// Should NOT have a type definition
		if module.Types() != nil && len(module.Types()) != 0 {
			t.Errorf("expected no type definitions in strict mode, got %d", len(module.Types()))
		}
	})
}

func TestConvertToIR_ResourceType(t *testing.T) {
	pkg := domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("resources"),
		Interfaces: []domain.Interface{
			{
				Name: domain.MustIdentifier("my-interface"),
				Types: []domain.TypeDef{
					{
						Name: domain.MustIdentifier("file"),
						Kind: domain.ResourceDef{},
					},
				},
			},
		},
	}

	t.Run("non-strict mode", func(t *testing.T) {
		module, diagnostics := pipeline.ConvertToIR(pkg, pipeline.MakeOptions{StrictMode: false})

		// Should have a warning for unsupported resource
		if !pipeline.HasWarnings(diagnostics) {
			t.Error("expected warning for unsupported resource type")
		}

		// Should still have a type definition (fallback to Int)
		if module.Types() == nil || len(module.Types()) != 1 {
			t.Errorf("expected 1 type definition (fallback), got %d", len(module.Types()))
		}
	})

	t.Run("strict mode", func(t *testing.T) {
		module, diagnostics := pipeline.ConvertToIR(pkg, pipeline.MakeOptions{StrictMode: true})

		// Should have an error for unsupported resource
		if !pipeline.HasErrors(diagnostics) {
			t.Error("expected error for unsupported resource type in strict mode")
		}

		// Should NOT have a type definition
		if module.Types() != nil && len(module.Types()) != 0 {
			t.Errorf("expected no type definitions in strict mode, got %d", len(module.Types()))
		}
	})
}

func TestConvertToIR_FunctionWithParams(t *testing.T) {
	pkg := domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("functions"),
		Interfaces: []domain.Interface{
			{
				Name: domain.MustIdentifier("math"),
				Functions: []domain.Function{
					{
						Name: domain.MustIdentifier("add"),
						Params: []domain.Param{
							{Name: domain.MustIdentifier("a"), Type: domain.PrimitiveType{Kind: domain.S32}},
							{Name: domain.MustIdentifier("b"), Type: domain.PrimitiveType{Kind: domain.S32}},
						},
						Results: []domain.Type{domain.PrimitiveType{Kind: domain.S32}},
					},
				},
			},
		},
	}

	module, diagnostics := pipeline.ConvertToIR(pkg, pipeline.MakeOptions{})

	// Should have warnings for s32 -> Int (3 occurrences)
	if len(pipeline.FilterBySeverity(diagnostics, corePipeline.SeverityWarn)) < 3 {
		t.Errorf("expected at least 3 warnings for s32 params/result")
	}

	// Should have one value definition
	if module.Values() == nil || len(module.Values()) != 1 {
		t.Errorf("expected 1 value definition, got %d", len(module.Values()))
	}
}

func TestConvertToIR_FunctionMultipleResults(t *testing.T) {
	pkg := domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("functions"),
		Interfaces: []domain.Interface{
			{
				Name: domain.MustIdentifier("multi"),
				Functions: []domain.Function{
					{
						Name:   domain.MustIdentifier("divmod"),
						Params: []domain.Param{},
						Results: []domain.Type{
							domain.PrimitiveType{Kind: domain.S32},
							domain.PrimitiveType{Kind: domain.S32},
						},
					},
				},
			},
		},
	}

	module, diagnostics := pipeline.ConvertToIR(pkg, pipeline.MakeOptions{})

	// Should have warnings for s32 -> Int
	if !pipeline.HasWarnings(diagnostics) {
		t.Error("expected warnings for s32 results")
	}

	// Should have one value definition
	if module.Values() == nil || len(module.Values()) != 1 {
		t.Errorf("expected 1 value definition, got %d", len(module.Values()))
	}
}

func TestConvertToIR_ContainerTypes(t *testing.T) {
	stringType := domain.PrimitiveType{Kind: domain.String}
	u32Type := domain.PrimitiveType{Kind: domain.U32}

	tests := []struct {
		name    string
		witType domain.Type
	}{
		{"list", domain.ListType{Element: stringType}},
		{"option", domain.OptionType{Inner: stringType}},
		{"result", domain.ResultType{Ok: typePtr(stringType), Err: typePtr(u32Type)}},
		{"tuple", domain.TupleType{Types: []domain.Type{stringType, u32Type}}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pkg := makePackageWithFunction("test-func", tt.witType)
			module, _ := pipeline.ConvertToIR(pkg, pipeline.MakeOptions{})

			// Should have one value definition
			if module.Values() == nil || len(module.Values()) != 1 {
				t.Errorf("expected 1 value definition, got %d", len(module.Values()))
			}
		})
	}
}

func TestConvertToIR_TypeAlias(t *testing.T) {
	pkg := domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("aliases"),
		Interfaces: []domain.Interface{
			{
				Name: domain.MustIdentifier("my-interface"),
				Types: []domain.TypeDef{
					{
						Name: domain.MustIdentifier("my-string"),
						Kind: domain.TypeAliasDef{
							Target: domain.PrimitiveType{Kind: domain.String},
						},
					},
				},
			},
		},
	}

	module, diagnostics := pipeline.ConvertToIR(pkg, pipeline.MakeOptions{})

	// Type alias to string should be lossless
	if pipeline.HasErrors(diagnostics) {
		t.Errorf("unexpected errors: %v", diagnostics)
	}

	// Should have one type definition
	if module.Types() == nil || len(module.Types()) != 1 {
		t.Errorf("expected 1 type definition, got %d", len(module.Types()))
	}
}

func TestConvertToIR_Documentation(t *testing.T) {
	pkg := domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("docs"),
		Interfaces: []domain.Interface{
			{
				Name: domain.MustIdentifier("my-interface"),
				Types: []domain.TypeDef{
					{
						Name: domain.MustIdentifier("documented-type"),
						Kind: domain.EnumDef{
							Cases: []domain.Identifier{domain.MustIdentifier("a")},
						},
						Docs: domain.NewDocumentation("A documented type"),
					},
				},
				Functions: []domain.Function{
					{
						Name:    domain.MustIdentifier("documented-func"),
						Params:  []domain.Param{},
						Results: []domain.Type{},
						Docs:    domain.NewDocumentation("A documented function"),
					},
				},
			},
		},
		Docs: domain.NewDocumentation("Package documentation"),
	}

	module, diagnostics := pipeline.ConvertToIR(pkg, pipeline.MakeOptions{})

	// Should not have errors
	if pipeline.HasErrors(diagnostics) {
		t.Errorf("unexpected errors: %v", diagnostics)
	}

	// Should have both types and values
	if module.Types() == nil || len(module.Types()) != 1 {
		t.Errorf("expected 1 type definition, got %d", len(module.Types()))
	}
	if module.Values() == nil || len(module.Values()) != 1 {
		t.Errorf("expected 1 value definition, got %d", len(module.Values()))
	}

	// Check package documentation is preserved
	if module.Doc() == nil {
		t.Error("expected module documentation to be preserved")
	}
}

func TestConvertToIR_EmptyPackage(t *testing.T) {
	pkg := domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("empty"),
	}

	module, diagnostics := pipeline.ConvertToIR(pkg, pipeline.MakeOptions{})

	// Should not have errors
	if pipeline.HasErrors(diagnostics) {
		t.Errorf("unexpected errors: %v", diagnostics)
	}

	// Should have no types or values
	if module.Types() != nil && len(module.Types()) != 0 {
		t.Errorf("expected 0 type definitions, got %d", len(module.Types()))
	}
	if module.Values() != nil && len(module.Values()) != 0 {
		t.Errorf("expected 0 value definitions, got %d", len(module.Values()))
	}
}

func TestConvertToIR_WarningsAsErrors(t *testing.T) {
	// Create a package with a lossy type
	pkg := makePackageWithFunction("test-func", domain.PrimitiveType{Kind: domain.U8})

	t.Run("warnings allowed", func(t *testing.T) {
		_, diagnostics := pipeline.ConvertToIR(pkg, pipeline.MakeOptions{
			WarningsAsErrors: false,
		})

		// Should have warnings, but not errors
		if !pipeline.HasWarnings(diagnostics) {
			t.Error("expected warnings for u8 -> Int")
		}
		if pipeline.HasErrors(diagnostics) {
			t.Error("did not expect errors when warnings are allowed")
		}
	})

	t.Run("warnings as errors check", func(t *testing.T) {
		_, diagnostics := pipeline.ConvertToIR(pkg, pipeline.MakeOptions{
			WarningsAsErrors: true,
		})

		// The conversion itself doesn't change diagnostics based on WarningsAsErrors
		// That's handled in the make step. The conversion should still produce warnings.
		if !pipeline.HasWarnings(diagnostics) {
			t.Error("expected warnings for u8 -> Int")
		}
	})
}

// Helper functions

func makePackageWithFunction(funcName string, resultType domain.Type) domain.Package {
	return domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("test"),
		Interfaces: []domain.Interface{
			{
				Name: domain.MustIdentifier("test-interface"),
				Functions: []domain.Function{
					{
						Name:    domain.MustIdentifier(funcName),
						Params:  []domain.Param{},
						Results: []domain.Type{resultType},
					},
				},
			},
		},
	}
}

func typePtr(t domain.Type) *domain.Type {
	return &t
}
