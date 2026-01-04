package json

import (
	"bytes"
	"encoding/json"
	"fmt"

	ir "github.com/finos/morphir/pkg/models/ir"
)

const encodeTypeSpecificationErrorFmt = "codec/json: encode %s: %w"

// EncodeTypeSpecification encodes a Morphir type specification using versioned Morphir-compatible JSON.
func EncodeTypeSpecification[A any](opts Options, encodeAttributes AttrEncoder[A], spec ir.TypeSpecification[A]) ([]byte, error) {
	opts = opts.withDefaults()
	raw, err := encodeTypeSpecificationRaw(opts, encodeAttributes, spec)
	if err != nil {
		return nil, err
	}
	return raw, nil
}

func encodeTypeSpecificationRaw[A any](opts Options, encodeAttributes AttrEncoder[A], spec ir.TypeSpecification[A]) (json.RawMessage, error) {
	if spec == nil {
		return nil, fmt.Errorf("codec/json: TypeSpecification must not be null")
	}
	if encodeAttributes == nil {
		return nil, fmt.Errorf("codec/json: encodeAttributes must not be nil")
	}

	switch s := spec.(type) {
	case ir.TypeAliasSpecification[A]:
		return encodeTypeAliasSpecification(opts, encodeAttributes, s)
	case ir.OpaqueTypeSpecification[A]:
		return encodeOpaqueTypeSpecification(opts, s)
	case ir.CustomTypeSpecification[A]:
		return encodeCustomTypeSpecification(opts, encodeAttributes, s)
	case ir.DerivedTypeSpecification[A]:
		return encodeDerivedTypeSpecification(opts, encodeAttributes, s)
	default:
		return nil, fmt.Errorf("codec/json: unsupported TypeSpecification variant %T", spec)
	}
}

func encodeTypeAliasSpecification[A any](opts Options, encodeAttributes AttrEncoder[A], s ir.TypeAliasSpecification[A]) (json.RawMessage, error) {
	tag := tagForTypeSpecification(opts.FormatVersion, "TypeAliasSpecification")
	paramsRaw, err := encodeNameListRaw(opts, s.TypeParams())
	if err != nil {
		return nil, err
	}
	expRaw, err := encodeTypeRaw(opts, encodeAttributes, s.Expression())
	if err != nil {
		return nil, err
	}
	encoded, err := json.Marshal([]json.RawMessage{json.RawMessage(strRaw(tag)), paramsRaw, expRaw})
	if err != nil {
		return nil, fmt.Errorf(encodeTypeSpecificationErrorFmt, tag, err)
	}
	return encoded, nil
}

func encodeOpaqueTypeSpecification[A any](opts Options, s ir.OpaqueTypeSpecification[A]) (json.RawMessage, error) {
	tag := tagForTypeSpecification(opts.FormatVersion, "OpaqueTypeSpecification")
	paramsRaw, err := encodeNameListRaw(opts, s.TypeParams())
	if err != nil {
		return nil, err
	}
	encoded, err := json.Marshal([]json.RawMessage{json.RawMessage(strRaw(tag)), paramsRaw})
	if err != nil {
		return nil, fmt.Errorf(encodeTypeSpecificationErrorFmt, tag, err)
	}
	return encoded, nil
}

func encodeCustomTypeSpecification[A any](opts Options, encodeAttributes AttrEncoder[A], s ir.CustomTypeSpecification[A]) (json.RawMessage, error) {
	tag := tagForTypeSpecification(opts.FormatVersion, "CustomTypeSpecification")
	paramsRaw, err := encodeNameListRaw(opts, s.TypeParams())
	if err != nil {
		return nil, err
	}
	ctorsRaw, err := encodeTypeConstructorsRaw(opts, encodeAttributes, s.Constructors())
	if err != nil {
		return nil, err
	}
	encoded, err := json.Marshal([]json.RawMessage{json.RawMessage(strRaw(tag)), paramsRaw, ctorsRaw})
	if err != nil {
		return nil, fmt.Errorf(encodeTypeSpecificationErrorFmt, tag, err)
	}
	return encoded, nil
}

func encodeDerivedTypeSpecification[A any](opts Options, encodeAttributes AttrEncoder[A], s ir.DerivedTypeSpecification[A]) (json.RawMessage, error) {
	tag := tagForTypeSpecification(opts.FormatVersion, "DerivedTypeSpecification")
	paramsRaw, err := encodeNameListRaw(opts, s.TypeParams())
	if err != nil {
		return nil, err
	}
	detailsRaw, err := encodeDerivedTypeSpecificationDetailsRaw(opts, encodeAttributes, s.Details())
	if err != nil {
		return nil, err
	}
	encoded, err := json.Marshal([]json.RawMessage{json.RawMessage(strRaw(tag)), paramsRaw, detailsRaw})
	if err != nil {
		return nil, fmt.Errorf(encodeTypeSpecificationErrorFmt, tag, err)
	}
	return encoded, nil
}

func encodeDerivedTypeSpecificationDetailsRaw[A any](opts Options, encodeAttributes AttrEncoder[A], d ir.DerivedTypeSpecificationDetails[A]) (json.RawMessage, error) {
	baseTypeRaw, err := encodeTypeRaw(opts, encodeAttributes, d.BaseType())
	if err != nil {
		return nil, err
	}
	fromRaw, err := EncodeFQName(opts, d.FromBaseType())
	if err != nil {
		return nil, err
	}
	toRaw, err := EncodeFQName(opts, d.ToBaseType())
	if err != nil {
		return nil, err
	}
	obj := map[string]json.RawMessage{
		"baseType":     baseTypeRaw,
		"fromBaseType": json.RawMessage(fromRaw),
		"toBaseType":   json.RawMessage(toRaw),
	}
	encoded, err := json.Marshal(obj)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode derived type details: %w", err)
	}
	return encoded, nil
}

// DecodeTypeSpecification decodes a Morphir type specification using versioned Morphir-compatible JSON.
func DecodeTypeSpecification[A any](opts Options, decodeAttributes AttrDecoder[A], data []byte) (ir.TypeSpecification[A], error) {
	opts = opts.withDefaults()
	trimmed := bytes.TrimSpace(data)
	if bytes.Equal(trimmed, []byte("null")) {
		return nil, fmt.Errorf("codec/json: expected TypeSpecification array, got null")
	}
	if decodeAttributes == nil {
		return nil, fmt.Errorf("codec/json: decodeAttributes must not be nil")
	}

	var parts []json.RawMessage
	if err := json.Unmarshal(trimmed, &parts); err != nil {
		return nil, fmt.Errorf("codec/json: decode TypeSpecification: %w", err)
	}
	if len(parts) == 0 {
		return nil, fmt.Errorf("codec/json: decode TypeSpecification: expected non-empty array")
	}
	var tag string
	if err := json.Unmarshal(parts[0], &tag); err != nil {
		return nil, fmt.Errorf("codec/json: decode TypeSpecification tag: %w", err)
	}

	return decodeTypeSpecificationByTag(opts, decodeAttributes, tag, parts)
}

func decodeTypeSpecificationByTag[A any](opts Options, decodeAttributes AttrDecoder[A], tag string, parts []json.RawMessage) (ir.TypeSpecification[A], error) {
	if opts.FormatVersion == FormatV1 {
		switch tag {
		case "type_alias_specification":
			return decodeTypeAliasSpecification(opts, decodeAttributes, parts)
		case "opaque_type_specification":
			return decodeOpaqueTypeSpecification[A](opts, parts)
		case "custom_type_specification":
			return decodeCustomTypeSpecification(opts, decodeAttributes, parts)
		case "derived_type_specification", "DerivedTypeSpecification":
			// v1 has an upstream inconsistency: encoder uses "DerivedTypeSpecification" while decoder expects
			// "derived_type_specification". We accept both to maximize compatibility.
			return decodeDerivedTypeSpecification(opts, decodeAttributes, parts)
		default:
			return nil, fmt.Errorf("codec/json: unknown TypeSpecification kind: %q", tag)
		}
	}

	switch tag {
	case "TypeAliasSpecification":
		return decodeTypeAliasSpecification(opts, decodeAttributes, parts)
	case "OpaqueTypeSpecification":
		return decodeOpaqueTypeSpecification[A](opts, parts)
	case "CustomTypeSpecification":
		return decodeCustomTypeSpecification(opts, decodeAttributes, parts)
	case "DerivedTypeSpecification":
		return decodeDerivedTypeSpecification(opts, decodeAttributes, parts)
	default:
		return nil, fmt.Errorf("codec/json: unknown TypeSpecification kind: %q", tag)
	}
}

func decodeTypeAliasSpecification[A any](opts Options, decodeAttributes AttrDecoder[A], parts []json.RawMessage) (ir.TypeSpecification[A], error) {
	if len(parts) != 3 {
		return nil, fmt.Errorf("codec/json: decode TypeAliasSpecification: expected array length 3, got %d", len(parts))
	}
	params, err := decodeNameList(opts, parts[1])
	if err != nil {
		return nil, err
	}
	exp, err := DecodeType(opts, decodeAttributes, parts[2])
	if err != nil {
		return nil, err
	}
	return ir.NewTypeAliasSpecification[A](params, exp), nil
}

func decodeOpaqueTypeSpecification[A any](opts Options, parts []json.RawMessage) (ir.TypeSpecification[A], error) {
	if len(parts) != 2 {
		return nil, fmt.Errorf("codec/json: decode OpaqueTypeSpecification: expected array length 2, got %d", len(parts))
	}
	params, err := decodeNameList(opts, parts[1])
	if err != nil {
		return nil, err
	}
	return ir.NewOpaqueTypeSpecification[A](params), nil
}

func decodeCustomTypeSpecification[A any](opts Options, decodeAttributes AttrDecoder[A], parts []json.RawMessage) (ir.TypeSpecification[A], error) {
	if len(parts) != 3 {
		return nil, fmt.Errorf("codec/json: decode CustomTypeSpecification: expected array length 3, got %d", len(parts))
	}
	params, err := decodeNameList(opts, parts[1])
	if err != nil {
		return nil, err
	}
	ctors, err := DecodeTypeConstructors(opts, decodeAttributes, parts[2])
	if err != nil {
		return nil, err
	}
	return ir.NewCustomTypeSpecification[A](params, ctors), nil
}

func decodeDerivedTypeSpecification[A any](opts Options, decodeAttributes AttrDecoder[A], parts []json.RawMessage) (ir.TypeSpecification[A], error) {
	if len(parts) != 3 {
		return nil, fmt.Errorf("codec/json: decode DerivedTypeSpecification: expected array length 3, got %d", len(parts))
	}
	params, err := decodeNameList(opts, parts[1])
	if err != nil {
		return nil, err
	}
	details, err := decodeDerivedTypeSpecificationDetails(opts, decodeAttributes, parts[2])
	if err != nil {
		return nil, err
	}
	return ir.NewDerivedTypeSpecification[A](params, details), nil
}

func decodeDerivedTypeSpecificationDetails[A any](opts Options, decodeAttributes AttrDecoder[A], data json.RawMessage) (ir.DerivedTypeSpecificationDetails[A], error) {
	var obj map[string]json.RawMessage
	if err := json.Unmarshal(bytes.TrimSpace(data), &obj); err != nil {
		return ir.DerivedTypeSpecificationDetails[A]{}, fmt.Errorf("codec/json: decode derived type details: %w", err)
	}
	baseRaw, ok := obj["baseType"]
	if !ok {
		return ir.DerivedTypeSpecificationDetails[A]{}, fmt.Errorf("codec/json: decode derived type details: missing field 'baseType'")
	}
	fromRaw, ok := obj["fromBaseType"]
	if !ok {
		return ir.DerivedTypeSpecificationDetails[A]{}, fmt.Errorf("codec/json: decode derived type details: missing field 'fromBaseType'")
	}
	toRaw, ok := obj["toBaseType"]
	if !ok {
		return ir.DerivedTypeSpecificationDetails[A]{}, fmt.Errorf("codec/json: decode derived type details: missing field 'toBaseType'")
	}
	base, err := DecodeType(opts, decodeAttributes, baseRaw)
	if err != nil {
		return ir.DerivedTypeSpecificationDetails[A]{}, err
	}
	from, err := DecodeFQName(opts, fromRaw)
	if err != nil {
		return ir.DerivedTypeSpecificationDetails[A]{}, err
	}
	to, err := DecodeFQName(opts, toRaw)
	if err != nil {
		return ir.DerivedTypeSpecificationDetails[A]{}, err
	}
	return ir.DerivedTypeSpecificationDetailsFromParts[A](base, from, to), nil
}

func tagForTypeSpecification(v FormatVersion, pascal string) string {
	if v == FormatV1 {
		switch pascal {
		case "TypeAliasSpecification":
			return "type_alias_specification"
		case "OpaqueTypeSpecification":
			return "opaque_type_specification"
		case "CustomTypeSpecification":
			return "custom_type_specification"
		case "DerivedTypeSpecification":
			// Matches Morphir.IR.Type.CodecV1 (upstream) even though the decoder expects snake_case.
			return "DerivedTypeSpecification"
		default:
			return pascal
		}
	}
	return pascal
}

func encodeNameListRaw(opts Options, names []ir.Name) (json.RawMessage, error) {
	items := make([]json.RawMessage, len(names))
	for i := range names {
		raw, err := EncodeName(opts, names[i])
		if err != nil {
			return nil, err
		}
		items[i] = json.RawMessage(raw)
	}
	encoded, err := json.Marshal(items)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode name list: %w", err)
	}
	return encoded, nil
}

func decodeNameList(opts Options, data json.RawMessage) ([]ir.Name, error) {
	var items []json.RawMessage
	if err := json.Unmarshal(bytes.TrimSpace(data), &items); err != nil {
		return nil, fmt.Errorf("codec/json: decode name list: %w", err)
	}
	names := make([]ir.Name, len(items))
	for i := range items {
		name, err := DecodeName(opts, items[i])
		if err != nil {
			return nil, err
		}
		names[i] = name
	}
	return names, nil
}
