package json

import (
	"bytes"
	"encoding/json"
	"fmt"

	ir "github.com/finos/morphir/pkg/models/ir"
)

// EncodeTypeDefinition encodes a Morphir type definition using versioned Morphir-compatible JSON.
func EncodeTypeDefinition[A any](opts Options, encodeAttributes AttrEncoder[A], def ir.TypeDefinition[A]) ([]byte, error) {
	opts = opts.withDefaults()
	raw, err := encodeTypeDefinitionRaw(opts, encodeAttributes, def)
	if err != nil {
		return nil, err
	}
	return raw, nil
}

func encodeTypeDefinitionRaw[A any](opts Options, encodeAttributes AttrEncoder[A], def ir.TypeDefinition[A]) (json.RawMessage, error) {
	if def == nil {
		return nil, fmt.Errorf("codec/json: TypeDefinition must not be null")
	}
	if encodeAttributes == nil {
		return nil, fmt.Errorf("codec/json: encodeAttributes must not be nil")
	}

	switch d := def.(type) {
	case ir.TypeAliasDefinition[A]:
		return encodeTypeAliasDefinition(opts, encodeAttributes, d)
	case ir.CustomTypeDefinition[A]:
		return encodeCustomTypeDefinition(opts, encodeAttributes, d)
	default:
		return nil, fmt.Errorf("codec/json: unsupported TypeDefinition variant %T", def)
	}
}

func encodeTypeAliasDefinition[A any](opts Options, encodeAttributes AttrEncoder[A], d ir.TypeAliasDefinition[A]) (json.RawMessage, error) {
	tag := tagForTypeDefinition(opts.FormatVersion, "TypeAliasDefinition")
	paramsRaw, err := encodeNameListRaw(opts, d.TypeParams())
	if err != nil {
		return nil, err
	}
	expRaw, err := encodeTypeRaw(opts, encodeAttributes, d.Expression())
	if err != nil {
		return nil, err
	}
	encoded, err := json.Marshal([]json.RawMessage{json.RawMessage(strRaw(tag)), paramsRaw, expRaw})
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode %s: %w", tag, err)
	}
	return encoded, nil
}

func encodeCustomTypeDefinition[A any](opts Options, encodeAttributes AttrEncoder[A], d ir.CustomTypeDefinition[A]) (json.RawMessage, error) {
	tag := tagForTypeDefinition(opts.FormatVersion, "CustomTypeDefinition")
	paramsRaw, err := encodeNameListRaw(opts, d.TypeParams())
	if err != nil {
		return nil, err
	}
	ctorsRaw, err := EncodeAccessControlled(opts, func(v ir.TypeConstructors[A]) (json.RawMessage, error) {
		return encodeTypeConstructorsRaw(opts, encodeAttributes, v)
	}, d.Constructors())
	if err != nil {
		return nil, err
	}
	encoded, err := json.Marshal([]json.RawMessage{json.RawMessage(strRaw(tag)), paramsRaw, json.RawMessage(ctorsRaw)})
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode %s: %w", tag, err)
	}
	return encoded, nil
}

// DecodeTypeDefinition decodes a Morphir type definition using versioned Morphir-compatible JSON.
func DecodeTypeDefinition[A any](opts Options, decodeAttributes AttrDecoder[A], data []byte) (ir.TypeDefinition[A], error) {
	opts = opts.withDefaults()
	trimmed := bytes.TrimSpace(data)
	if bytes.Equal(trimmed, []byte("null")) {
		return nil, fmt.Errorf("codec/json: expected TypeDefinition array, got null")
	}
	if decodeAttributes == nil {
		return nil, fmt.Errorf("codec/json: decodeAttributes must not be nil")
	}

	var parts []json.RawMessage
	if err := json.Unmarshal(trimmed, &parts); err != nil {
		return nil, fmt.Errorf("codec/json: decode TypeDefinition: %w", err)
	}
	if len(parts) == 0 {
		return nil, fmt.Errorf("codec/json: decode TypeDefinition: expected non-empty array")
	}
	var tag string
	if err := json.Unmarshal(parts[0], &tag); err != nil {
		return nil, fmt.Errorf("codec/json: decode TypeDefinition tag: %w", err)
	}

	if opts.FormatVersion == FormatV1 {
		switch tag {
		case "type_alias_definition":
			return decodeTypeAliasDefinition(opts, decodeAttributes, parts)
		case "custom_type_definition":
			return decodeCustomTypeDefinition(opts, decodeAttributes, parts)
		default:
			return nil, fmt.Errorf("codec/json: unknown TypeDefinition kind: %q", tag)
		}
	}

	switch tag {
	case "TypeAliasDefinition":
		return decodeTypeAliasDefinition(opts, decodeAttributes, parts)
	case "CustomTypeDefinition":
		return decodeCustomTypeDefinition(opts, decodeAttributes, parts)
	default:
		return nil, fmt.Errorf("codec/json: unknown TypeDefinition kind: %q", tag)
	}
}

func decodeTypeAliasDefinition[A any](opts Options, decodeAttributes AttrDecoder[A], parts []json.RawMessage) (ir.TypeDefinition[A], error) {
	if len(parts) != 3 {
		return nil, fmt.Errorf("codec/json: decode TypeAliasDefinition: expected array length 3, got %d", len(parts))
	}
	params, err := decodeNameList(opts, parts[1])
	if err != nil {
		return nil, err
	}
	exp, err := DecodeType(opts, decodeAttributes, parts[2])
	if err != nil {
		return nil, err
	}
	return ir.NewTypeAliasDefinition[A](params, exp), nil
}

func decodeCustomTypeDefinition[A any](opts Options, decodeAttributes AttrDecoder[A], parts []json.RawMessage) (ir.TypeDefinition[A], error) {
	if len(parts) != 3 {
		return nil, fmt.Errorf("codec/json: decode CustomTypeDefinition: expected array length 3, got %d", len(parts))
	}
	params, err := decodeNameList(opts, parts[1])
	if err != nil {
		return nil, err
	}
	ctors, err := DecodeAccessControlled(opts, func(raw json.RawMessage) (ir.TypeConstructors[A], error) {
		return DecodeTypeConstructors(opts, decodeAttributes, raw)
	}, parts[2])
	if err != nil {
		return nil, err
	}
	return ir.NewCustomTypeDefinition[A](params, ctors), nil
}

func tagForTypeDefinition(v FormatVersion, pascal string) string {
	if v == FormatV1 {
		switch pascal {
		case "TypeAliasDefinition":
			return "type_alias_definition"
		case "CustomTypeDefinition":
			return "custom_type_definition"
		default:
			return pascal
		}
	}
	return pascal
}
