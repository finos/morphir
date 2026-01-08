package pipeline_test

import (
	"testing"

	"github.com/finos/morphir/pkg/bindings/wit/domain"
	"github.com/finos/morphir/pkg/bindings/wit/pipeline"
)

func TestValidateRoundTrip_IdenticalPackages(t *testing.T) {
	pkg := domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("pkg"),
		Interfaces: []domain.Interface{
			{
				Name: domain.MustIdentifier("my-interface"),
				Types: []domain.TypeDef{
					{
						Name: domain.MustIdentifier("my-type"),
						Kind: domain.EnumDef{
							Cases: []domain.Identifier{
								domain.MustIdentifier("a"),
								domain.MustIdentifier("b"),
							},
						},
					},
				},
				Functions: []domain.Function{
					{
						Name:   domain.MustIdentifier("my-func"),
						Params: []domain.Param{},
						Results: []domain.Type{
							domain.PrimitiveType{Kind: domain.Bool},
						},
					},
				},
			},
		},
	}

	if !pipeline.ValidateRoundTrip(pkg, pkg) {
		t.Error("expected identical packages to be valid")
	}
}

func TestValidateRoundTrip_DifferentInterfaceCount(t *testing.T) {
	pkg1 := domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("pkg"),
		Interfaces: []domain.Interface{
			{Name: domain.MustIdentifier("a")},
			{Name: domain.MustIdentifier("b")},
		},
	}
	pkg2 := domain.Package{
		Namespace:  domain.MustNamespace("test"),
		Name:       domain.MustPackageName("pkg"),
		Interfaces: []domain.Interface{{Name: domain.MustIdentifier("a")}},
	}

	if pipeline.ValidateRoundTrip(pkg1, pkg2) {
		t.Error("expected different interface counts to be invalid")
	}
}

func TestValidateRoundTrip_DifferentTypeCount(t *testing.T) {
	pkg1 := domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("pkg"),
		Interfaces: []domain.Interface{
			{
				Name: domain.MustIdentifier("iface"),
				Types: []domain.TypeDef{
					{Name: domain.MustIdentifier("a"), Kind: domain.EnumDef{}},
					{Name: domain.MustIdentifier("b"), Kind: domain.EnumDef{}},
				},
			},
		},
	}
	pkg2 := domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("pkg"),
		Interfaces: []domain.Interface{
			{
				Name: domain.MustIdentifier("iface"),
				Types: []domain.TypeDef{
					{Name: domain.MustIdentifier("a"), Kind: domain.EnumDef{}},
				},
			},
		},
	}

	if pipeline.ValidateRoundTrip(pkg1, pkg2) {
		t.Error("expected different type counts to be invalid")
	}
}

func TestValidateRoundTrip_DifferentFunctionCount(t *testing.T) {
	pkg1 := domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("pkg"),
		Interfaces: []domain.Interface{
			{
				Name: domain.MustIdentifier("iface"),
				Functions: []domain.Function{
					{Name: domain.MustIdentifier("a")},
					{Name: domain.MustIdentifier("b")},
				},
			},
		},
	}
	pkg2 := domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("pkg"),
		Interfaces: []domain.Interface{
			{
				Name: domain.MustIdentifier("iface"),
				Functions: []domain.Function{
					{Name: domain.MustIdentifier("a")},
				},
			},
		},
	}

	if pipeline.ValidateRoundTrip(pkg1, pkg2) {
		t.Error("expected different function counts to be invalid")
	}
}

func TestValidateRoundTrip_PrimitiveTypeEquivalence(t *testing.T) {
	// Test that integer types are considered equivalent
	// (since they all map to Int in Morphir)
	tests := []struct {
		name  string
		kind1 domain.PrimitiveKind
		kind2 domain.PrimitiveKind
		want  bool
	}{
		{"same bool", domain.Bool, domain.Bool, true},
		{"same string", domain.String, domain.String, true},
		{"u8 and u32", domain.U8, domain.U32, true},   // Both integers
		{"s8 and s64", domain.S8, domain.S64, true},   // Both integers
		{"f32 and f64", domain.F32, domain.F64, true}, // Both floats
		{"bool and string", domain.Bool, domain.String, false},
		{"int and float", domain.U32, domain.F64, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pkg1 := makePackageWithPrimitive(tt.kind1)
			pkg2 := makePackageWithPrimitive(tt.kind2)

			got := pipeline.ValidateRoundTrip(pkg1, pkg2)
			if got != tt.want {
				t.Errorf("ValidateRoundTrip() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestValidateRoundTrip_RecordEquivalence(t *testing.T) {
	pkg1 := domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("pkg"),
		Interfaces: []domain.Interface{
			{
				Name: domain.MustIdentifier("iface"),
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

	// Same structure but different integer size (s64 instead of s32)
	// Should still be considered equivalent due to lossy integer mapping
	pkg2 := domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("pkg"),
		Interfaces: []domain.Interface{
			{
				Name: domain.MustIdentifier("iface"),
				Types: []domain.TypeDef{
					{
						Name: domain.MustIdentifier("point"),
						Kind: domain.RecordDef{
							Fields: []domain.Field{
								{Name: domain.MustIdentifier("x"), Type: domain.PrimitiveType{Kind: domain.S64}},
								{Name: domain.MustIdentifier("y"), Type: domain.PrimitiveType{Kind: domain.S64}},
							},
						},
					},
				},
			},
		},
	}

	if !pipeline.ValidateRoundTrip(pkg1, pkg2) {
		t.Error("expected records with equivalent integer types to be valid")
	}
}

func TestValidateRoundTrip_VariantEquivalence(t *testing.T) {
	pkg1 := domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("pkg"),
		Interfaces: []domain.Interface{
			{
				Name: domain.MustIdentifier("iface"),
				Types: []domain.TypeDef{
					{
						Name: domain.MustIdentifier("result"),
						Kind: domain.VariantDef{
							Cases: []domain.VariantCase{
								{Name: domain.MustIdentifier("ok"), Payload: witTypePtr(domain.PrimitiveType{Kind: domain.String})},
								{Name: domain.MustIdentifier("err"), Payload: witTypePtr(domain.PrimitiveType{Kind: domain.U32})},
							},
						},
					},
				},
			},
		},
	}

	if !pipeline.ValidateRoundTrip(pkg1, pkg1) {
		t.Error("expected identical variants to be valid")
	}
}

func TestValidateRoundTrip_ContainerTypes(t *testing.T) {
	stringType := domain.PrimitiveType{Kind: domain.String}

	tests := []struct {
		name  string
		type1 domain.Type
		type2 domain.Type
		want  bool
	}{
		{
			"same list",
			domain.ListType{Element: stringType},
			domain.ListType{Element: stringType},
			true,
		},
		{
			"same option",
			domain.OptionType{Inner: stringType},
			domain.OptionType{Inner: stringType},
			true,
		},
		{
			"different container",
			domain.ListType{Element: stringType},
			domain.OptionType{Inner: stringType},
			false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pkg1 := makePackageWithFunctionResult(tt.type1)
			pkg2 := makePackageWithFunctionResult(tt.type2)

			got := pipeline.ValidateRoundTrip(pkg1, pkg2)
			if got != tt.want {
				t.Errorf("ValidateRoundTrip() = %v, want %v", got, tt.want)
			}
		})
	}
}

// Helper functions

func makePackageWithPrimitive(kind domain.PrimitiveKind) domain.Package {
	return domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("pkg"),
		Interfaces: []domain.Interface{
			{
				Name: domain.MustIdentifier("iface"),
				Functions: []domain.Function{
					{
						Name:    domain.MustIdentifier("f"),
						Results: []domain.Type{domain.PrimitiveType{Kind: kind}},
					},
				},
			},
		},
	}
}

func makePackageWithFunctionResult(resultType domain.Type) domain.Package {
	return domain.Package{
		Namespace: domain.MustNamespace("test"),
		Name:      domain.MustPackageName("pkg"),
		Interfaces: []domain.Interface{
			{
				Name: domain.MustIdentifier("iface"),
				Functions: []domain.Function{
					{
						Name:    domain.MustIdentifier("f"),
						Results: []domain.Type{resultType},
					},
				},
			},
		},
	}
}

func witTypePtr(t domain.Type) *domain.Type {
	return &t
}
