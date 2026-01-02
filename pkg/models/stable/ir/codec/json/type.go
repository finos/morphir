package json

import (
	"bytes"
	"encoding/json"
	"fmt"

	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

// AttrEncoder encodes type attributes to JSON.
//
// In Morphir-Elm codecs, this corresponds to the encodeAttributes parameter.
type AttrEncoder[A any] func(A) (json.RawMessage, error)

// AttrDecoder decodes type attributes from JSON.
//
// In Morphir-Elm codecs, this corresponds to the decodeAttributes parameter.
type AttrDecoder[A any] func(json.RawMessage) (A, error)

// EncodeType encodes a Morphir IR Type using versioned Morphir-compatible JSON.
//
// Tag casing and the Field representation vary by FormatVersion:
//   - v1: tags are snake/lowercase ("variable", "record", ...); fields are [name, tpe]
//   - v2/v3: tags are PascalCase ("Variable", "Record", ...); fields are {name:..., tpe:...}
func EncodeType[A any](opts Options, encodeAttributes AttrEncoder[A], tpe ir.Type[A]) ([]byte, error) {
	opts = opts.withDefaults()
	raw, err := encodeTypeRaw(opts, encodeAttributes, tpe)
	if err != nil {
		return nil, err
	}
	return raw, nil
}

func encodeTypeRaw[A any](opts Options, encodeAttributes AttrEncoder[A], tpe ir.Type[A]) (json.RawMessage, error) {
	if tpe == nil {
		return nil, fmt.Errorf("codec/json: Type must not be null")
	}
	if encodeAttributes == nil {
		return nil, fmt.Errorf("codec/json: encodeAttributes must not be nil")
	}

	switch t := tpe.(type) {
	case ir.TypeVariable[A]:
		return encodeTypeVariable(opts, encodeAttributes, t)
	case ir.TypeReference[A]:
		return encodeTypeReference(opts, encodeAttributes, t)
	case ir.TypeTuple[A]:
		return encodeTypeTuple(opts, encodeAttributes, t)
	case ir.TypeRecord[A]:
		return encodeTypeRecord(opts, encodeAttributes, t)
	case ir.TypeExtensibleRecord[A]:
		return encodeTypeExtensibleRecord(opts, encodeAttributes, t)
	case ir.TypeFunction[A]:
		return encodeTypeFunction(opts, encodeAttributes, t)
	case ir.TypeUnit[A]:
		return encodeTypeUnit(opts, encodeAttributes, t)
	default:
		return nil, fmt.Errorf("codec/json: unsupported Type variant %T", tpe)
	}
}

func encodeTypeVariable[A any](opts Options, encodeAttributes AttrEncoder[A], t ir.TypeVariable[A]) (json.RawMessage, error) {
	tag := tagForType(opts.FormatVersion, "Variable")
	return encodeType3(opts, encodeAttributes, tag, t.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		nameRaw, err := EncodeName(opts, t.Name())
		if err != nil {
			return nil, err
		}
		return append(parts, json.RawMessage(nameRaw)), nil
	})
}

func encodeTypeReference[A any](opts Options, encodeAttributes AttrEncoder[A], t ir.TypeReference[A]) (json.RawMessage, error) {
	tag := tagForType(opts.FormatVersion, "Reference")
	return encodeType3(opts, encodeAttributes, tag, t.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		fq, err := EncodeFQName(opts, t.FullyQualifiedName())
		if err != nil {
			return nil, err
		}
		paramsBytes, err := encodeTypeListRaw(opts, encodeAttributes, t.TypeParams())
		if err != nil {
			return nil, err
		}
		return append(parts, json.RawMessage(fq), json.RawMessage(paramsBytes)), nil
	})
}

func encodeTypeTuple[A any](opts Options, encodeAttributes AttrEncoder[A], t ir.TypeTuple[A]) (json.RawMessage, error) {
	tag := tagForType(opts.FormatVersion, "Tuple")
	return encodeType3(opts, encodeAttributes, tag, t.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		elemsBytes, err := encodeTypeListRaw(opts, encodeAttributes, t.Elements())
		if err != nil {
			return nil, err
		}
		return append(parts, json.RawMessage(elemsBytes)), nil
	})
}

func encodeTypeRecord[A any](opts Options, encodeAttributes AttrEncoder[A], t ir.TypeRecord[A]) (json.RawMessage, error) {
	tag := tagForType(opts.FormatVersion, "Record")
	return encodeType3(opts, encodeAttributes, tag, t.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		fieldsBytes, err := encodeFieldListRaw(opts, encodeAttributes, t.Fields())
		if err != nil {
			return nil, err
		}
		return append(parts, json.RawMessage(fieldsBytes)), nil
	})
}

func encodeTypeExtensibleRecord[A any](opts Options, encodeAttributes AttrEncoder[A], t ir.TypeExtensibleRecord[A]) (json.RawMessage, error) {
	tag := tagForType(opts.FormatVersion, "ExtensibleRecord")
	return encodeType3(opts, encodeAttributes, tag, t.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		varNameRaw, err := EncodeName(opts, t.VariableName())
		if err != nil {
			return nil, err
		}
		fieldsBytes, err := encodeFieldListRaw(opts, encodeAttributes, t.Fields())
		if err != nil {
			return nil, err
		}
		return append(parts, json.RawMessage(varNameRaw), json.RawMessage(fieldsBytes)), nil
	})
}

func encodeTypeFunction[A any](opts Options, encodeAttributes AttrEncoder[A], t ir.TypeFunction[A]) (json.RawMessage, error) {
	tag := tagForType(opts.FormatVersion, "Function")
	return encodeType3(opts, encodeAttributes, tag, t.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		argRaw, err := encodeTypeRaw(opts, encodeAttributes, t.Argument())
		if err != nil {
			return nil, err
		}
		resRaw, err := encodeTypeRaw(opts, encodeAttributes, t.Result())
		if err != nil {
			return nil, err
		}
		return append(parts, argRaw, resRaw), nil
	})
}

func encodeTypeUnit[A any](opts Options, encodeAttributes AttrEncoder[A], t ir.TypeUnit[A]) (json.RawMessage, error) {
	tag := tagForType(opts.FormatVersion, "Unit")
	parts, err := encodeHeader(opts, encodeAttributes, tag, t.Attributes())
	if err != nil {
		return nil, err
	}
	encoded, err := json.Marshal(parts)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode unit: %w", err)
	}
	return encoded, nil
}

func encodeTypeListRaw[A any](opts Options, encodeAttributes AttrEncoder[A], items []ir.Type[A]) ([]byte, error) {
	itemsRaw := make([]json.RawMessage, len(items))
	for i := range items {
		itemRaw, err := encodeTypeRaw(opts, encodeAttributes, items[i])
		if err != nil {
			return nil, err
		}
		itemsRaw[i] = itemRaw
	}
	encoded, err := json.Marshal(itemsRaw)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode list: %w", err)
	}
	return encoded, nil
}

func encodeFieldListRaw[A any](opts Options, encodeAttributes AttrEncoder[A], fields []ir.Field[A]) ([]byte, error) {
	fieldsRaw := make([]json.RawMessage, len(fields))
	for i := range fields {
		fRaw, err := encodeFieldRaw(opts, encodeAttributes, fields[i])
		if err != nil {
			return nil, err
		}
		fieldsRaw[i] = fRaw
	}
	encoded, err := json.Marshal(fieldsRaw)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode fields list: %w", err)
	}
	return encoded, nil
}

func encodeType3[A any](opts Options, encodeAttributes AttrEncoder[A], tag string, attrs A, add func([]json.RawMessage) ([]json.RawMessage, error)) (json.RawMessage, error) {
	parts, err := encodeHeader(opts, encodeAttributes, tag, attrs)
	if err != nil {
		return nil, err
	}
	parts, err = add(parts)
	if err != nil {
		return nil, err
	}
	encoded, err := json.Marshal(parts)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode %s: %w", tag, err)
	}
	return encoded, nil
}

func encodeHeader[A any](opts Options, encodeAttributes AttrEncoder[A], tag string, attrs A) ([]json.RawMessage, error) {
	tagRaw, err := json.Marshal(tag)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode tag: %w", err)
	}
	attrsRaw, err := encodeAttributes(attrs)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode attributes: %w", err)
	}
	if len(attrsRaw) == 0 {
		return nil, fmt.Errorf("codec/json: encode attributes returned empty JSON")
	}
	return []json.RawMessage{json.RawMessage(tagRaw), attrsRaw}, nil
}

func encodeFieldRaw[A any](opts Options, encodeAttributes AttrEncoder[A], field ir.Field[A]) (json.RawMessage, error) {
	nameRaw, err := EncodeName(opts, field.Name())
	if err != nil {
		return nil, err
	}
	tpeRaw, err := encodeTypeRaw(opts, encodeAttributes, field.Type())
	if err != nil {
		return nil, err
	}

	if opts.FormatVersion == FormatV1 {
		encoded, err := json.Marshal([]json.RawMessage{json.RawMessage(nameRaw), tpeRaw})
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode field (v1): %w", err)
		}
		return encoded, nil
	}

	// v2/v3 field is an object with keys name and tpe.
	obj := map[string]json.RawMessage{
		"name": json.RawMessage(nameRaw),
		"tpe":  tpeRaw,
	}
	encoded, err := json.Marshal(obj)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode field: %w", err)
	}
	return encoded, nil
}

// DecodeType decodes a Morphir IR Type using versioned Morphir-compatible JSON.
func DecodeType[A any](opts Options, decodeAttributes AttrDecoder[A], data []byte) (ir.Type[A], error) {
	opts = opts.withDefaults()
	trimmed := bytes.TrimSpace(data)
	if bytes.Equal(trimmed, []byte("null")) {
		return nil, fmt.Errorf("codec/json: expected Type array, got null")
	}
	if decodeAttributes == nil {
		return nil, fmt.Errorf("codec/json: decodeAttributes must not be nil")
	}

	raw, err := decodeTypeHeader(trimmed)
	if err != nil {
		return nil, err
	}

	kind, attrs, err := decodeKindAndAttributes(opts, decodeAttributes, raw)
	if err != nil {
		return nil, err
	}

	switch kind {
	case "Variable":
		return decodeTypeVariable(opts, attrs, raw)
	case "Reference":
		return decodeTypeReference(opts, decodeAttributes, attrs, raw)
	case "Tuple":
		return decodeTypeTuple(opts, decodeAttributes, attrs, raw)
	case "Record":
		return decodeTypeRecord(opts, decodeAttributes, attrs, raw)
	case "ExtensibleRecord":
		return decodeTypeExtensibleRecord(opts, decodeAttributes, attrs, raw)
	case "Function":
		return decodeTypeFunction(opts, decodeAttributes, attrs, raw)
	case "Unit":
		return decodeTypeUnit(attrs, raw)
	default:
		return nil, fmt.Errorf("codec/json: unsupported Type kind %q", kind)
	}
}

func decodeTypeHeader(trimmed []byte) ([]json.RawMessage, error) {
	var raw []json.RawMessage
	if err := json.Unmarshal(trimmed, &raw); err != nil {
		return nil, fmt.Errorf("codec/json: expected Type array: %w", err)
	}
	if len(raw) < 2 {
		return nil, fmt.Errorf("codec/json: expected Type array with at least 2 elements, got %d", len(raw))
	}
	return raw, nil
}

func decodeKindAndAttributes[A any](opts Options, decodeAttributes AttrDecoder[A], raw []json.RawMessage) (string, A, error) {
	var tag string
	if err := json.Unmarshal(raw[0], &tag); err != nil {
		var zero A
		return "", zero, fmt.Errorf("codec/json: invalid Type tag: %w", err)
	}
	kind, err := kindFromTag(opts.FormatVersion, tag)
	if err != nil {
		var zero A
		return "", zero, err
	}
	attrs, err := decodeAttributes(raw[1])
	if err != nil {
		var zero A
		return "", zero, fmt.Errorf("codec/json: decode attributes: %w", err)
	}
	return kind, attrs, nil
}

func decodeTypeVariable[A any](opts Options, attrs A, raw []json.RawMessage) (ir.Type[A], error) {
	if len(raw) != 3 {
		return nil, fmt.Errorf("codec/json: Variable expects 3 elements, got %d", len(raw))
	}
	name, err := DecodeName(opts, raw[2])
	if err != nil {
		return nil, err
	}
	return ir.NewTypeVariable(attrs, name), nil
}

func decodeTypeReference[A any](opts Options, decodeAttributes AttrDecoder[A], attrs A, raw []json.RawMessage) (ir.Type[A], error) {
	if len(raw) != 4 {
		return nil, fmt.Errorf("codec/json: Reference expects 4 elements, got %d", len(raw))
	}
	fq, err := DecodeFQName(opts, raw[2])
	if err != nil {
		return nil, err
	}
	params, err := decodeTypeList(opts, decodeAttributes, raw[3])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode reference params: %w", err)
	}
	return ir.NewTypeReference(attrs, fq, params), nil
}

func decodeTypeTuple[A any](opts Options, decodeAttributes AttrDecoder[A], attrs A, raw []json.RawMessage) (ir.Type[A], error) {
	if len(raw) != 3 {
		return nil, fmt.Errorf("codec/json: Tuple expects 3 elements, got %d", len(raw))
	}
	elems, err := decodeTypeList(opts, decodeAttributes, raw[2])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode tuple elements: %w", err)
	}
	return ir.NewTypeTuple(attrs, elems), nil
}

func decodeTypeRecord[A any](opts Options, decodeAttributes AttrDecoder[A], attrs A, raw []json.RawMessage) (ir.Type[A], error) {
	if len(raw) != 3 {
		return nil, fmt.Errorf("codec/json: Record expects 3 elements, got %d", len(raw))
	}
	fields, err := decodeFieldList(opts, decodeAttributes, raw[2])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode record fields: %w", err)
	}
	return ir.NewTypeRecord(attrs, fields), nil
}

func decodeTypeExtensibleRecord[A any](opts Options, decodeAttributes AttrDecoder[A], attrs A, raw []json.RawMessage) (ir.Type[A], error) {
	if len(raw) != 4 {
		return nil, fmt.Errorf("codec/json: ExtensibleRecord expects 4 elements, got %d", len(raw))
	}
	varName, err := DecodeName(opts, raw[2])
	if err != nil {
		return nil, err
	}
	fields, err := decodeFieldList(opts, decodeAttributes, raw[3])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode extensible record fields: %w", err)
	}
	return ir.NewTypeExtensibleRecord(attrs, varName, fields), nil
}

func decodeTypeFunction[A any](opts Options, decodeAttributes AttrDecoder[A], attrs A, raw []json.RawMessage) (ir.Type[A], error) {
	if len(raw) != 4 {
		return nil, fmt.Errorf("codec/json: Function expects 4 elements, got %d", len(raw))
	}
	arg, err := DecodeType(opts, decodeAttributes, raw[2])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode function argument: %w", err)
	}
	res, err := DecodeType(opts, decodeAttributes, raw[3])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode function result: %w", err)
	}
	return ir.NewTypeFunction(attrs, arg, res), nil
}

func decodeTypeUnit[A any](attrs A, raw []json.RawMessage) (ir.Type[A], error) {
	if len(raw) != 2 {
		return nil, fmt.Errorf("codec/json: Unit expects 2 elements, got %d", len(raw))
	}
	return ir.NewTypeUnit(attrs), nil
}

func decodeTypeList[A any](opts Options, decodeAttributes AttrDecoder[A], raw json.RawMessage) ([]ir.Type[A], error) {
	var items []json.RawMessage
	if err := json.Unmarshal(raw, &items); err != nil {
		return nil, fmt.Errorf("codec/json: expected list: %w", err)
	}
	out := make([]ir.Type[A], len(items))
	for i := range items {
		t, err := DecodeType(opts, decodeAttributes, items[i])
		if err != nil {
			return nil, err
		}
		out[i] = t
	}
	return out, nil
}

func decodeFieldList[A any](opts Options, decodeAttributes AttrDecoder[A], raw json.RawMessage) ([]ir.Field[A], error) {
	var items []json.RawMessage
	if err := json.Unmarshal(raw, &items); err != nil {
		return nil, fmt.Errorf("codec/json: expected fields list: %w", err)
	}
	out := make([]ir.Field[A], len(items))
	for i := range items {
		f, err := decodeField(opts, decodeAttributes, items[i])
		if err != nil {
			return nil, err
		}
		out[i] = f
	}
	return out, nil
}

func decodeField[A any](opts Options, decodeAttributes AttrDecoder[A], raw json.RawMessage) (ir.Field[A], error) {
	if opts.FormatVersion == FormatV1 {
		var parts []json.RawMessage
		if err := json.Unmarshal(raw, &parts); err != nil {
			return ir.Field[A]{}, fmt.Errorf("codec/json: expected field array [name,tpe]: %w", err)
		}
		if len(parts) != 2 {
			return ir.Field[A]{}, fmt.Errorf("codec/json: expected field array length 2, got %d", len(parts))
		}
		name, err := DecodeName(opts, parts[0])
		if err != nil {
			return ir.Field[A]{}, err
		}
		tpe, err := DecodeType(opts, decodeAttributes, parts[1])
		if err != nil {
			return ir.Field[A]{}, err
		}
		return ir.FieldFromParts[A](name, tpe), nil
	}

	var obj struct {
		Name json.RawMessage `json:"name"`
		Tpe  json.RawMessage `json:"tpe"`
	}
	if err := json.Unmarshal(raw, &obj); err != nil {
		return ir.Field[A]{}, fmt.Errorf("codec/json: expected field object {name,tpe}: %w", err)
	}
	if len(bytes.TrimSpace(obj.Name)) == 0 {
		return ir.Field[A]{}, fmt.Errorf("codec/json: missing field.name")
	}
	if len(bytes.TrimSpace(obj.Tpe)) == 0 {
		return ir.Field[A]{}, fmt.Errorf("codec/json: missing field.tpe")
	}
	name, err := DecodeName(opts, obj.Name)
	if err != nil {
		return ir.Field[A]{}, err
	}
	tpe, err := DecodeType(opts, decodeAttributes, obj.Tpe)
	if err != nil {
		return ir.Field[A]{}, err
	}
	return ir.FieldFromParts[A](name, tpe), nil
}

func tagForType(version FormatVersion, kind string) string {
	if version == FormatV1 {
		switch kind {
		case "Variable":
			return "variable"
		case "Reference":
			return "reference"
		case "Tuple":
			return "tuple"
		case "Record":
			return "record"
		case "ExtensibleRecord":
			return "extensible_record"
		case "Function":
			return "function"
		case "Unit":
			return "unit"
		default:
			return kind
		}
	}
	return kind
}

func kindFromTag(version FormatVersion, tag string) (string, error) {
	if version == FormatV1 {
		switch tag {
		case "variable":
			return "Variable", nil
		case "reference":
			return "Reference", nil
		case "tuple":
			return "Tuple", nil
		case "record":
			return "Record", nil
		case "extensible_record":
			return "ExtensibleRecord", nil
		case "function":
			return "Function", nil
		case "unit":
			return "Unit", nil
		default:
			return "", fmt.Errorf("codec/json: unknown v1 Type tag %q", tag)
		}
	}

	// v2/v3
	switch tag {
	case "Variable", "Reference", "Tuple", "Record", "ExtensibleRecord", "Function", "Unit":
		return tag, nil
	default:
		return "", fmt.Errorf("codec/json: unknown Type tag %q", tag)
	}
}
