package json

import (
	"encoding/json"
	"testing"

	ir "github.com/finos/morphir/pkg/models/ir"
)

func TestTypeSpecificationRoundTripV3(t *testing.T) {
	opts := Options{FormatVersion: FormatV3}

	foo := ir.NameFromParts([]string{"foo"})
	bar := ir.NameFromParts([]string{"bar"})
	mod := ir.PathFromParts([]ir.Name{ir.NameFromParts([]string{"my"}), ir.NameFromParts([]string{"mod"})})
	pkg := ir.PathFromParts([]ir.Name{ir.NameFromParts([]string{"my"}), ir.NameFromParts([]string{"pkg"})})
	from := ir.FQNameFromParts(pkg, mod, foo)
	to := ir.FQNameFromParts(pkg, mod, bar)

	base := ir.NewTypeUnit(unitAttr{})
	details := ir.DerivedTypeSpecificationDetailsFromParts[unitAttr](base, from, to)
	spec := ir.NewDerivedTypeSpecification[unitAttr]([]ir.Name{ir.NameFromParts([]string{"a"})}, details)

	data, err := EncodeTypeSpecification(opts, encodeUnitAttr, spec)
	if err != nil {
		t.Fatalf("EncodeTypeSpecification: %v", err)
	}

	decoded, err := DecodeTypeSpecification(opts, decodeUnitAttr, data)
	if err != nil {
		t.Fatalf("DecodeTypeSpecification: %v", err)
	}

	if !equalTypeSpecification(spec, decoded) {
		t.Fatalf("expected structural equality after roundtrip")
	}
}

func TestTypeSpecificationDerivedTagV1IsPascalCase(t *testing.T) {
	opts := Options{FormatVersion: FormatV1}

	foo := ir.NameFromParts([]string{"foo"})
	mod := ir.PathFromParts([]ir.Name{ir.NameFromParts([]string{"my"}), ir.NameFromParts([]string{"mod"})})
	pkg := ir.PathFromParts([]ir.Name{ir.NameFromParts([]string{"my"}), ir.NameFromParts([]string{"pkg"})})
	fq := ir.FQNameFromParts(pkg, mod, foo)

	base := ir.NewTypeUnit(unitAttr{})
	details := ir.DerivedTypeSpecificationDetailsFromParts[unitAttr](base, fq, fq)
	spec := ir.NewDerivedTypeSpecification[unitAttr]([]ir.Name{}, details)

	data, err := EncodeTypeSpecification(opts, encodeUnitAttr, spec)
	if err != nil {
		t.Fatalf("EncodeTypeSpecification(v1): %v", err)
	}

	var raw []json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	var tag string
	if err := json.Unmarshal(raw[0], &tag); err != nil {
		t.Fatalf("tag: %v", err)
	}
	if tag != "DerivedTypeSpecification" {
		t.Fatalf("expected v1 derived spec tag 'DerivedTypeSpecification', got %q", tag)
	}
}

func TestTypeDefinitionVersionedTagsAndAccessControlledShape(t *testing.T) {
	foo := ir.NameFromParts([]string{"foo"})
	arg := ir.NameFromParts([]string{"x"})

	ctors := ir.TypeConstructors[unitAttr]{
		ir.TypeConstructorFromParts[unitAttr](foo, ir.TypeConstructorArgs[unitAttr]{
			ir.TypeConstructorArgFromParts[unitAttr](arg, ir.NewTypeUnit(unitAttr{})),
		}),
	}
	def := ir.NewCustomTypeDefinition[unitAttr](nil, ir.Public(ctors))

	// v1: tag is snake_case and access-controlled is tagged array.
	dataV1, err := EncodeTypeDefinition(Options{FormatVersion: FormatV1}, encodeUnitAttr, def)
	if err != nil {
		t.Fatalf("EncodeTypeDefinition(v1): %v", err)
	}
	var rawV1 []json.RawMessage
	if err := json.Unmarshal(dataV1, &rawV1); err != nil {
		t.Fatalf("unmarshal v1: %v", err)
	}
	var tagV1 string
	if err := json.Unmarshal(rawV1[0], &tagV1); err != nil {
		t.Fatalf("tag v1: %v", err)
	}
	if tagV1 != "custom_type_definition" {
		t.Fatalf("expected v1 tag 'custom_type_definition', got %q", tagV1)
	}
	var acV1 []json.RawMessage
	if err := json.Unmarshal(rawV1[2], &acV1); err != nil {
		t.Fatalf("expected v1 access-controlled to be array: %v", err)
	}
	var acTagV1 string
	if err := json.Unmarshal(acV1[0], &acTagV1); err != nil {
		t.Fatalf("v1 access tag: %v", err)
	}
	if acTagV1 != "public" {
		t.Fatalf("expected v1 access tag 'public', got %q", acTagV1)
	}

	// v3: tag is PascalCase and access-controlled is an object with access/value.
	dataV3, err := EncodeTypeDefinition(Options{FormatVersion: FormatV3}, encodeUnitAttr, def)
	if err != nil {
		t.Fatalf("EncodeTypeDefinition(v3): %v", err)
	}
	var rawV3 []json.RawMessage
	if err := json.Unmarshal(dataV3, &rawV3); err != nil {
		t.Fatalf("unmarshal v3: %v", err)
	}
	var tagV3 string
	if err := json.Unmarshal(rawV3[0], &tagV3); err != nil {
		t.Fatalf("tag v3: %v", err)
	}
	if tagV3 != "CustomTypeDefinition" {
		t.Fatalf("expected v3 tag 'CustomTypeDefinition', got %q", tagV3)
	}
	var acV3 map[string]json.RawMessage
	if err := json.Unmarshal(rawV3[2], &acV3); err != nil {
		t.Fatalf("expected v3 access-controlled to be object: %v", err)
	}
	if _, ok := acV3["access"]; !ok {
		t.Fatalf("expected v3 access-controlled to have key 'access'")
	}
	if _, ok := acV3["value"]; !ok {
		t.Fatalf("expected v3 access-controlled to have key 'value'")
	}
}

func TestTypeDefinitionRoundTripV3(t *testing.T) {
	opts := Options{FormatVersion: FormatV3}

	foo := ir.NameFromParts([]string{"foo"})
	arg := ir.NameFromParts([]string{"x"})

	alias := ir.NewTypeAliasDefinition[unitAttr](
		[]ir.Name{ir.NameFromParts([]string{"a"})},
		ir.NewTypeUnit(unitAttr{}),
	)

	ctors := ir.TypeConstructors[unitAttr]{
		ir.TypeConstructorFromParts[unitAttr](foo, ir.TypeConstructorArgs[unitAttr]{
			ir.TypeConstructorArgFromParts[unitAttr](arg, ir.NewTypeUnit(unitAttr{})),
		}),
	}
	custom := ir.NewCustomTypeDefinition[unitAttr](
		[]ir.Name{ir.NameFromParts([]string{"a"})},
		ir.Public(ctors),
	)

	for _, def := range []ir.TypeDefinition[unitAttr]{alias, custom} {
		data, err := EncodeTypeDefinition(opts, encodeUnitAttr, def)
		if err != nil {
			t.Fatalf("EncodeTypeDefinition: %v", err)
		}
		decoded, err := DecodeTypeDefinition(opts, decodeUnitAttr, data)
		if err != nil {
			t.Fatalf("DecodeTypeDefinition: %v", err)
		}
		if !equalTypeDefinition(def, decoded) {
			t.Fatalf("expected structural equality after roundtrip")
		}
	}
}

func TestTypeDefinitionDecodeRejectsWrongVersion(t *testing.T) {
	def := ir.NewTypeAliasDefinition[unitAttr](
		[]ir.Name{ir.NameFromParts([]string{"a"})},
		ir.NewTypeUnit(unitAttr{}),
	)

	dataV3, err := EncodeTypeDefinition(Options{FormatVersion: FormatV3}, encodeUnitAttr, def)
	if err != nil {
		t.Fatalf("EncodeTypeDefinition(v3): %v", err)
	}

	if _, err := DecodeTypeDefinition(Options{FormatVersion: FormatV1}, decodeUnitAttr, dataV3); err == nil {
		t.Fatalf("expected v1 decode to fail on v3 payload")
	}
}

func TestTypeSpecificationDecodeRejectsWrongVersion(t *testing.T) {
	optsV3 := Options{FormatVersion: FormatV3}
	spec := ir.NewOpaqueTypeSpecification[unitAttr]([]ir.Name{ir.NameFromParts([]string{"a"})})

	dataV3, err := EncodeTypeSpecification(optsV3, encodeUnitAttr, spec)
	if err != nil {
		t.Fatalf("EncodeTypeSpecification(v3): %v", err)
	}

	if _, err := DecodeTypeSpecification(Options{FormatVersion: FormatV1}, decodeUnitAttr, dataV3); err == nil {
		t.Fatalf("expected v1 decode to fail on v3 payload")
	}
}

func equalTypeSpecification(left ir.TypeSpecification[unitAttr], right ir.TypeSpecification[unitAttr]) bool {
	switch l := left.(type) {
	case ir.TypeAliasSpecification[unitAttr]:
		r, ok := right.(ir.TypeAliasSpecification[unitAttr])
		return ok && equalNameList(l.TypeParams(), r.TypeParams()) && ir.EqualType(func(unitAttr, unitAttr) bool { return true }, l.Expression(), r.Expression())
	case ir.OpaqueTypeSpecification[unitAttr]:
		r, ok := right.(ir.OpaqueTypeSpecification[unitAttr])
		return ok && equalNameList(l.TypeParams(), r.TypeParams())
	case ir.CustomTypeSpecification[unitAttr]:
		r, ok := right.(ir.CustomTypeSpecification[unitAttr])
		return ok && equalNameList(l.TypeParams(), r.TypeParams()) && equalConstructors(l.Constructors(), r.Constructors())
	case ir.DerivedTypeSpecification[unitAttr]:
		r, ok := right.(ir.DerivedTypeSpecification[unitAttr])
		if !ok {
			return false
		}
		ld := l.Details()
		rd := r.Details()
		return equalNameList(l.TypeParams(), r.TypeParams()) &&
			ir.EqualType(func(unitAttr, unitAttr) bool { return true }, ld.BaseType(), rd.BaseType()) &&
			ld.FromBaseType().Equal(rd.FromBaseType()) &&
			ld.ToBaseType().Equal(rd.ToBaseType())
	default:
		return false
	}
}

func equalTypeDefinition(left ir.TypeDefinition[unitAttr], right ir.TypeDefinition[unitAttr]) bool {
	switch l := left.(type) {
	case ir.TypeAliasDefinition[unitAttr]:
		r, ok := right.(ir.TypeAliasDefinition[unitAttr])
		return ok && equalNameList(l.TypeParams(), r.TypeParams()) && ir.EqualType(func(unitAttr, unitAttr) bool { return true }, l.Expression(), r.Expression())
	case ir.CustomTypeDefinition[unitAttr]:
		r, ok := right.(ir.CustomTypeDefinition[unitAttr])
		if !ok {
			return false
		}
		lc := l.Constructors()
		rc := r.Constructors()
		if lc.Access() != rc.Access() {
			return false
		}
		return equalNameList(l.TypeParams(), r.TypeParams()) && equalConstructors(lc.Value(), rc.Value())
	default:
		return false
	}
}

func equalNameList(left []ir.Name, right []ir.Name) bool {
	if len(left) != len(right) {
		return false
	}
	for i := range left {
		if !left[i].Equal(right[i]) {
			return false
		}
	}
	return true
}

func equalConstructors(left ir.TypeConstructors[unitAttr], right ir.TypeConstructors[unitAttr]) bool {
	if len(left) != len(right) {
		return false
	}
	for i := range left {
		lc := left[i]
		rc := right[i]
		if !lc.Name().Equal(rc.Name()) {
			return false
		}
		la := lc.Args()
		ra := rc.Args()
		if len(la) != len(ra) {
			return false
		}
		for j := range la {
			if !la[j].Name().Equal(ra[j].Name()) {
				return false
			}
			if !ir.EqualType(func(unitAttr, unitAttr) bool { return true }, la[j].Type(), ra[j].Type()) {
				return false
			}
		}
	}
	return true
}
