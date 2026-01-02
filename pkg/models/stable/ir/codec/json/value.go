package json

import (
	"bytes"
	"encoding/json"
	"fmt"

	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

// ValueAttrEncoder encodes value attributes to JSON.
type ValueAttrEncoder[VA any] func(VA) (json.RawMessage, error)

// ValueAttrDecoder decodes value attributes from JSON.
type ValueAttrDecoder[VA any] func(json.RawMessage) (VA, error)

// EncodeValue encodes a Morphir IR Value using versioned Morphir-compatible JSON.
//
// Tag casing differs by format version:
//   - v1: lowercase/snake_case (e.g. "literal", "if_then_else")
//   - v2/v3: PascalCase (e.g. "Literal", "IfThenElse")
func EncodeValue[TA any, VA any](
	opts Options,
	encodeTypeAttributes AttrEncoder[TA],
	encodeValueAttributes ValueAttrEncoder[VA],
	value ir.Value[TA, VA],
) ([]byte, error) {
	opts = opts.withDefaults()
	raw, err := encodeValueRaw(opts, encodeTypeAttributes, encodeValueAttributes, value)
	if err != nil {
		return nil, err
	}
	return raw, nil
}

func encodeValueRaw[TA any, VA any](
	opts Options,
	encodeTA AttrEncoder[TA],
	encodeVA ValueAttrEncoder[VA],
	value ir.Value[TA, VA],
) (json.RawMessage, error) {
	if value == nil {
		return nil, fmt.Errorf("codec/json: Value must not be null")
	}
	if encodeVA == nil {
		return nil, fmt.Errorf("codec/json: encodeValueAttributes must not be nil")
	}

	switch v := value.(type) {
	case ir.LiteralValue[TA, VA]:
		return encodeLiteralValue(opts, encodeVA, v)
	case ir.ConstructorValue[TA, VA]:
		return encodeConstructorValue(opts, encodeVA, v)
	case ir.TupleValue[TA, VA]:
		return encodeTupleValue(opts, encodeTA, encodeVA, v)
	case ir.ListValue[TA, VA]:
		return encodeListValue(opts, encodeTA, encodeVA, v)
	case ir.RecordValue[TA, VA]:
		return encodeRecordValueNode(opts, encodeTA, encodeVA, v)
	case ir.VariableValue[TA, VA]:
		return encodeVariableValue(opts, encodeVA, v)
	case ir.ReferenceValue[TA, VA]:
		return encodeReferenceValue(opts, encodeVA, v)
	case ir.FieldValue[TA, VA]:
		return encodeFieldValueNode(opts, encodeTA, encodeVA, v)
	case ir.FieldFunctionValue[TA, VA]:
		return encodeFieldFunctionValue(opts, encodeVA, v)
	case ir.ApplyValue[TA, VA]:
		return encodeApplyValue(opts, encodeTA, encodeVA, v)
	case ir.LambdaValue[TA, VA]:
		return encodeLambdaValue(opts, encodeTA, encodeVA, v)
	case ir.LetDefinitionValue[TA, VA]:
		return encodeLetDefinitionValue(opts, encodeTA, encodeVA, v)
	case ir.LetRecursionValue[TA, VA]:
		return encodeLetRecursionValue(opts, encodeTA, encodeVA, v)
	case ir.DestructureValue[TA, VA]:
		return encodeDestructureValue(opts, encodeTA, encodeVA, v)
	case ir.IfThenElseValue[TA, VA]:
		return encodeIfThenElseValue(opts, encodeTA, encodeVA, v)
	case ir.PatternMatchValue[TA, VA]:
		return encodePatternMatchValue(opts, encodeTA, encodeVA, v)
	case ir.UpdateRecordValue[TA, VA]:
		return encodeUpdateRecordValue(opts, encodeTA, encodeVA, v)
	case ir.UnitValue[TA, VA]:
		return encodeUnitValue(opts, encodeVA, v)
	default:
		return nil, fmt.Errorf("codec/json: unsupported Value variant %T", value)
	}
}

func encodeLiteralValue[TA any, VA any](opts Options, encodeVA ValueAttrEncoder[VA], v ir.LiteralValue[TA, VA]) (json.RawMessage, error) {
	tag := tagForValue(opts.FormatVersion, "Literal")
	return encodeValue3Plus(opts, encodeVA, tag, v.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		litRaw, err := EncodeLiteral(opts, v.Literal())
		if err != nil {
			return nil, err
		}
		return append(parts, json.RawMessage(litRaw)), nil
	})
}

func encodeConstructorValue[TA any, VA any](opts Options, encodeVA ValueAttrEncoder[VA], v ir.ConstructorValue[TA, VA]) (json.RawMessage, error) {
	tag := tagForValue(opts.FormatVersion, "Constructor")
	return encodeValue3Plus(opts, encodeVA, tag, v.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		fqRaw, err := EncodeFQName(opts, v.ConstructorName())
		if err != nil {
			return nil, err
		}
		return append(parts, json.RawMessage(fqRaw)), nil
	})
}

func encodeTupleValue[TA any, VA any](opts Options, encodeTA AttrEncoder[TA], encodeVA ValueAttrEncoder[VA], v ir.TupleValue[TA, VA]) (json.RawMessage, error) {
	tag := tagForValue(opts.FormatVersion, "Tuple")
	return encodeValue3Plus(opts, encodeVA, tag, v.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		elemsRaw, err := encodeValueListRaw(opts, encodeTA, encodeVA, v.Elements())
		if err != nil {
			return nil, err
		}
		return append(parts, json.RawMessage(elemsRaw)), nil
	})
}

func encodeListValue[TA any, VA any](opts Options, encodeTA AttrEncoder[TA], encodeVA ValueAttrEncoder[VA], v ir.ListValue[TA, VA]) (json.RawMessage, error) {
	tag := tagForValue(opts.FormatVersion, "List")
	return encodeValue3Plus(opts, encodeVA, tag, v.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		itemsRaw, err := encodeValueListRaw(opts, encodeTA, encodeVA, v.Items())
		if err != nil {
			return nil, err
		}
		return append(parts, json.RawMessage(itemsRaw)), nil
	})
}

func encodeRecordValueNode[TA any, VA any](opts Options, encodeTA AttrEncoder[TA], encodeVA ValueAttrEncoder[VA], v ir.RecordValue[TA, VA]) (json.RawMessage, error) {
	tag := tagForValue(opts.FormatVersion, "Record")
	return encodeValue3Plus(opts, encodeVA, tag, v.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		fieldsRaw, err := encodeRecordFieldListRaw(opts, encodeTA, encodeVA, v.Fields())
		if err != nil {
			return nil, err
		}
		return append(parts, json.RawMessage(fieldsRaw)), nil
	})
}

func encodeVariableValue[TA any, VA any](opts Options, encodeVA ValueAttrEncoder[VA], v ir.VariableValue[TA, VA]) (json.RawMessage, error) {
	tag := tagForValue(opts.FormatVersion, "Variable")
	return encodeValue3Plus(opts, encodeVA, tag, v.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		nameRaw, err := EncodeName(opts, v.VariableName())
		if err != nil {
			return nil, err
		}
		return append(parts, json.RawMessage(nameRaw)), nil
	})
}

func encodeReferenceValue[TA any, VA any](opts Options, encodeVA ValueAttrEncoder[VA], v ir.ReferenceValue[TA, VA]) (json.RawMessage, error) {
	tag := tagForValue(opts.FormatVersion, "Reference")
	return encodeValue3Plus(opts, encodeVA, tag, v.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		fqRaw, err := EncodeFQName(opts, v.ReferenceName())
		if err != nil {
			return nil, err
		}
		return append(parts, json.RawMessage(fqRaw)), nil
	})
}

func encodeFieldValueNode[TA any, VA any](opts Options, encodeTA AttrEncoder[TA], encodeVA ValueAttrEncoder[VA], v ir.FieldValue[TA, VA]) (json.RawMessage, error) {
	tag := tagForValue(opts.FormatVersion, "Field")
	return encodeValue3Plus(opts, encodeVA, tag, v.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		subjectRaw, err := encodeValueRaw(opts, encodeTA, encodeVA, v.Subject())
		if err != nil {
			return nil, err
		}
		nameRaw, err := EncodeName(opts, v.FieldName())
		if err != nil {
			return nil, err
		}
		return append(parts, subjectRaw, json.RawMessage(nameRaw)), nil
	})
}

func encodeFieldFunctionValue[TA any, VA any](opts Options, encodeVA ValueAttrEncoder[VA], v ir.FieldFunctionValue[TA, VA]) (json.RawMessage, error) {
	tag := tagForValue(opts.FormatVersion, "FieldFunction")
	return encodeValue3Plus(opts, encodeVA, tag, v.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		nameRaw, err := EncodeName(opts, v.FieldName())
		if err != nil {
			return nil, err
		}
		return append(parts, json.RawMessage(nameRaw)), nil
	})
}

func encodeApplyValue[TA any, VA any](opts Options, encodeTA AttrEncoder[TA], encodeVA ValueAttrEncoder[VA], v ir.ApplyValue[TA, VA]) (json.RawMessage, error) {
	tag := tagForValue(opts.FormatVersion, "Apply")
	return encodeValue3Plus(opts, encodeVA, tag, v.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		fnRaw, err := encodeValueRaw(opts, encodeTA, encodeVA, v.Function())
		if err != nil {
			return nil, err
		}
		argRaw, err := encodeValueRaw(opts, encodeTA, encodeVA, v.Argument())
		if err != nil {
			return nil, err
		}
		return append(parts, fnRaw, argRaw), nil
	})
}

func encodeLambdaValue[TA any, VA any](opts Options, encodeTA AttrEncoder[TA], encodeVA ValueAttrEncoder[VA], v ir.LambdaValue[TA, VA]) (json.RawMessage, error) {
	tag := tagForValue(opts.FormatVersion, "Lambda")
	// Pattern uses VA as its attribute type
	encodePatternVA := AttrEncoder[VA](encodeVA)
	return encodeValue3Plus(opts, encodeVA, tag, v.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		patternRaw, err := encodePatternRaw(opts, encodePatternVA, v.ArgumentPattern())
		if err != nil {
			return nil, err
		}
		bodyRaw, err := encodeValueRaw(opts, encodeTA, encodeVA, v.Body())
		if err != nil {
			return nil, err
		}
		return append(parts, patternRaw, bodyRaw), nil
	})
}

func encodeLetDefinitionValue[TA any, VA any](opts Options, encodeTA AttrEncoder[TA], encodeVA ValueAttrEncoder[VA], v ir.LetDefinitionValue[TA, VA]) (json.RawMessage, error) {
	tag := tagForValue(opts.FormatVersion, "LetDefinition")
	return encodeValue3Plus(opts, encodeVA, tag, v.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		nameRaw, err := EncodeName(opts, v.ValueName())
		if err != nil {
			return nil, err
		}
		defRaw, err := encodeValueDefinitionRaw(opts, encodeTA, encodeVA, v.Definition())
		if err != nil {
			return nil, err
		}
		inValueRaw, err := encodeValueRaw(opts, encodeTA, encodeVA, v.InValue())
		if err != nil {
			return nil, err
		}
		return append(parts, json.RawMessage(nameRaw), defRaw, inValueRaw), nil
	})
}

func encodeLetRecursionValue[TA any, VA any](opts Options, encodeTA AttrEncoder[TA], encodeVA ValueAttrEncoder[VA], v ir.LetRecursionValue[TA, VA]) (json.RawMessage, error) {
	tag := tagForValue(opts.FormatVersion, "LetRecursion")
	return encodeValue3Plus(opts, encodeVA, tag, v.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		defsRaw, err := encodeNamedDefinitionsRaw(opts, encodeTA, encodeVA, v.Definitions())
		if err != nil {
			return nil, err
		}
		inValueRaw, err := encodeValueRaw(opts, encodeTA, encodeVA, v.InValue())
		if err != nil {
			return nil, err
		}
		return append(parts, json.RawMessage(defsRaw), inValueRaw), nil
	})
}

func encodeDestructureValue[TA any, VA any](opts Options, encodeTA AttrEncoder[TA], encodeVA ValueAttrEncoder[VA], v ir.DestructureValue[TA, VA]) (json.RawMessage, error) {
	tag := tagForValue(opts.FormatVersion, "Destructure")
	encodePatternVA := AttrEncoder[VA](encodeVA)
	return encodeValue3Plus(opts, encodeVA, tag, v.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		patternRaw, err := encodePatternRaw(opts, encodePatternVA, v.Pattern())
		if err != nil {
			return nil, err
		}
		valueToDestructRaw, err := encodeValueRaw(opts, encodeTA, encodeVA, v.ValueToDestruct())
		if err != nil {
			return nil, err
		}
		inValueRaw, err := encodeValueRaw(opts, encodeTA, encodeVA, v.InValue())
		if err != nil {
			return nil, err
		}
		return append(parts, patternRaw, valueToDestructRaw, inValueRaw), nil
	})
}

func encodeIfThenElseValue[TA any, VA any](opts Options, encodeTA AttrEncoder[TA], encodeVA ValueAttrEncoder[VA], v ir.IfThenElseValue[TA, VA]) (json.RawMessage, error) {
	tag := tagForValue(opts.FormatVersion, "IfThenElse")
	return encodeValue3Plus(opts, encodeVA, tag, v.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		condRaw, err := encodeValueRaw(opts, encodeTA, encodeVA, v.Condition())
		if err != nil {
			return nil, err
		}
		thenRaw, err := encodeValueRaw(opts, encodeTA, encodeVA, v.ThenBranch())
		if err != nil {
			return nil, err
		}
		elseRaw, err := encodeValueRaw(opts, encodeTA, encodeVA, v.ElseBranch())
		if err != nil {
			return nil, err
		}
		return append(parts, condRaw, thenRaw, elseRaw), nil
	})
}

func encodePatternMatchValue[TA any, VA any](opts Options, encodeTA AttrEncoder[TA], encodeVA ValueAttrEncoder[VA], v ir.PatternMatchValue[TA, VA]) (json.RawMessage, error) {
	tag := tagForValue(opts.FormatVersion, "PatternMatch")
	encodePatternVA := AttrEncoder[VA](encodeVA)
	return encodeValue3Plus(opts, encodeVA, tag, v.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		subjectRaw, err := encodeValueRaw(opts, encodeTA, encodeVA, v.Subject())
		if err != nil {
			return nil, err
		}
		casesRaw, err := encodePatternMatchCasesRaw(opts, encodeTA, encodeVA, encodePatternVA, v.Cases())
		if err != nil {
			return nil, err
		}
		return append(parts, subjectRaw, json.RawMessage(casesRaw)), nil
	})
}

func encodeUpdateRecordValue[TA any, VA any](opts Options, encodeTA AttrEncoder[TA], encodeVA ValueAttrEncoder[VA], v ir.UpdateRecordValue[TA, VA]) (json.RawMessage, error) {
	tag := tagForValue(opts.FormatVersion, "UpdateRecord")
	return encodeValue3Plus(opts, encodeVA, tag, v.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		valueToUpdateRaw, err := encodeValueRaw(opts, encodeTA, encodeVA, v.ValueToUpdate())
		if err != nil {
			return nil, err
		}
		fieldsRaw, err := encodeRecordFieldListRaw(opts, encodeTA, encodeVA, v.FieldsToUpdate())
		if err != nil {
			return nil, err
		}
		return append(parts, valueToUpdateRaw, json.RawMessage(fieldsRaw)), nil
	})
}

func encodeUnitValue[TA any, VA any](opts Options, encodeVA ValueAttrEncoder[VA], v ir.UnitValue[TA, VA]) (json.RawMessage, error) {
	tag := tagForValue(opts.FormatVersion, "Unit")
	return encodeValue2(opts, encodeVA, tag, v.Attributes())
}

// Helper functions for encoding

func encodeValue2[VA any](opts Options, encodeVA ValueAttrEncoder[VA], tag string, attrs VA) (json.RawMessage, error) {
	parts, err := encodeValueHeader(opts, encodeVA, tag, attrs)
	if err != nil {
		return nil, err
	}
	encoded, err := json.Marshal(parts)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode %s: %w", tag, err)
	}
	return encoded, nil
}

func encodeValue3Plus[VA any](opts Options, encodeVA ValueAttrEncoder[VA], tag string, attrs VA, add func([]json.RawMessage) ([]json.RawMessage, error)) (json.RawMessage, error) {
	parts, err := encodeValueHeader(opts, encodeVA, tag, attrs)
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

func encodeValueHeader[VA any](opts Options, encodeVA ValueAttrEncoder[VA], tag string, attrs VA) ([]json.RawMessage, error) {
	tagRaw, err := json.Marshal(tag)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode tag: %w", err)
	}
	attrsRaw, err := encodeVA(attrs)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode value attributes: %w", err)
	}
	if len(attrsRaw) == 0 {
		return nil, fmt.Errorf("codec/json: encode value attributes returned empty JSON")
	}
	return []json.RawMessage{json.RawMessage(tagRaw), attrsRaw}, nil
}

func encodeValueListRaw[TA any, VA any](opts Options, encodeTA AttrEncoder[TA], encodeVA ValueAttrEncoder[VA], items []ir.Value[TA, VA]) ([]byte, error) {
	itemsRaw := make([]json.RawMessage, len(items))
	for i := range items {
		itemRaw, err := encodeValueRaw(opts, encodeTA, encodeVA, items[i])
		if err != nil {
			return nil, err
		}
		itemsRaw[i] = itemRaw
	}
	encoded, err := json.Marshal(itemsRaw)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode value list: %w", err)
	}
	return encoded, nil
}

func encodeRecordFieldListRaw[TA any, VA any](opts Options, encodeTA AttrEncoder[TA], encodeVA ValueAttrEncoder[VA], fields []ir.RecordField[TA, VA]) ([]byte, error) {
	fieldsRaw := make([]json.RawMessage, len(fields))
	for i, f := range fields {
		nameRaw, err := EncodeName(opts, f.Name())
		if err != nil {
			return nil, err
		}
		valueRaw, err := encodeValueRaw(opts, encodeTA, encodeVA, f.Value())
		if err != nil {
			return nil, err
		}
		pair := []json.RawMessage{json.RawMessage(nameRaw), valueRaw}
		encoded, err := json.Marshal(pair)
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode record field: %w", err)
		}
		fieldsRaw[i] = encoded
	}
	encoded, err := json.Marshal(fieldsRaw)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode record fields: %w", err)
	}
	return encoded, nil
}

func encodeValueDefinitionRaw[TA any, VA any](opts Options, encodeTA AttrEncoder[TA], encodeVA ValueAttrEncoder[VA], def ir.ValueDefinition[TA, VA]) (json.RawMessage, error) {
	// Definition is encoded as an object: { inputTypes, outputType, body }
	inputTypesRaw, err := encodeDefinitionInputTypesRaw(opts, encodeTA, encodeVA, def.InputTypes())
	if err != nil {
		return nil, err
	}

	outputTypeRaw, err := encodeTypeRaw(opts, encodeTA, def.OutputType())
	if err != nil {
		return nil, err
	}

	bodyRaw, err := encodeValueRaw(opts, encodeTA, encodeVA, def.Body())
	if err != nil {
		return nil, err
	}

	obj := map[string]json.RawMessage{
		"inputTypes": json.RawMessage(inputTypesRaw),
		"outputType": outputTypeRaw,
		"body":       bodyRaw,
	}
	encoded, err := json.Marshal(obj)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode value definition: %w", err)
	}
	return encoded, nil
}

func encodeDefinitionInputTypesRaw[TA any, VA any](opts Options, encodeTA AttrEncoder[TA], encodeVA ValueAttrEncoder[VA], inputs []ir.ValueDefinitionInput[TA, VA]) ([]byte, error) {
	inputsRaw := make([]json.RawMessage, len(inputs))
	for i, inp := range inputs {
		nameRaw, err := EncodeName(opts, inp.Name())
		if err != nil {
			return nil, err
		}
		attrRaw, err := encodeVA(inp.Attributes())
		if err != nil {
			return nil, err
		}
		tpeRaw, err := encodeTypeRaw(opts, encodeTA, inp.Type())
		if err != nil {
			return nil, err
		}
		triple := []json.RawMessage{json.RawMessage(nameRaw), attrRaw, tpeRaw}
		encoded, err := json.Marshal(triple)
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode input type: %w", err)
		}
		inputsRaw[i] = encoded
	}
	encoded, err := json.Marshal(inputsRaw)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode input types: %w", err)
	}
	return encoded, nil
}

func encodeNamedDefinitionsRaw[TA any, VA any](opts Options, encodeTA AttrEncoder[TA], encodeVA ValueAttrEncoder[VA], defs []ir.NamedValueDefinition[TA, VA]) ([]byte, error) {
	defsRaw := make([]json.RawMessage, len(defs))
	for i, nd := range defs {
		nameRaw, err := EncodeName(opts, nd.Name())
		if err != nil {
			return nil, err
		}
		defRaw, err := encodeValueDefinitionRaw(opts, encodeTA, encodeVA, nd.Definition())
		if err != nil {
			return nil, err
		}
		pair := []json.RawMessage{json.RawMessage(nameRaw), defRaw}
		encoded, err := json.Marshal(pair)
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode named definition: %w", err)
		}
		defsRaw[i] = encoded
	}
	encoded, err := json.Marshal(defsRaw)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode named definitions: %w", err)
	}
	return encoded, nil
}

func encodePatternMatchCasesRaw[TA any, VA any](opts Options, encodeTA AttrEncoder[TA], encodeVA ValueAttrEncoder[VA], encodePatternVA AttrEncoder[VA], cases []ir.PatternMatchCase[TA, VA]) ([]byte, error) {
	casesRaw := make([]json.RawMessage, len(cases))
	for i, c := range cases {
		patternRaw, err := encodePatternRaw(opts, encodePatternVA, c.Pattern())
		if err != nil {
			return nil, err
		}
		bodyRaw, err := encodeValueRaw(opts, encodeTA, encodeVA, c.Body())
		if err != nil {
			return nil, err
		}
		pair := []json.RawMessage{patternRaw, bodyRaw}
		encoded, err := json.Marshal(pair)
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode pattern match case: %w", err)
		}
		casesRaw[i] = encoded
	}
	encoded, err := json.Marshal(casesRaw)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode pattern match cases: %w", err)
	}
	return encoded, nil
}

// DecodeValue decodes a Morphir IR Value using versioned Morphir-compatible JSON.
func DecodeValue[TA any, VA any](
	opts Options,
	decodeTypeAttributes AttrDecoder[TA],
	decodeValueAttributes ValueAttrDecoder[VA],
	data []byte,
) (ir.Value[TA, VA], error) {
	opts = opts.withDefaults()
	trimmed := bytes.TrimSpace(data)
	if bytes.Equal(trimmed, []byte("null")) {
		return nil, fmt.Errorf("codec/json: expected Value array, got null")
	}
	if decodeValueAttributes == nil {
		return nil, fmt.Errorf("codec/json: decodeValueAttributes must not be nil")
	}

	raw, err := decodeValueHeader(trimmed)
	if err != nil {
		return nil, err
	}

	kind, attrs, err := decodeValueKindAndAttributes(opts, decodeValueAttributes, raw)
	if err != nil {
		return nil, err
	}

	return decodeValueByKind(opts, decodeTypeAttributes, decodeValueAttributes, kind, attrs, raw)
}

func decodeValueHeader(trimmed []byte) ([]json.RawMessage, error) {
	var raw []json.RawMessage
	if err := json.Unmarshal(trimmed, &raw); err != nil {
		return nil, fmt.Errorf("codec/json: expected Value array: %w", err)
	}
	if len(raw) < 2 {
		return nil, fmt.Errorf("codec/json: expected Value array with at least 2 elements, got %d", len(raw))
	}
	return raw, nil
}

func decodeValueKindAndAttributes[VA any](opts Options, decodeVA ValueAttrDecoder[VA], raw []json.RawMessage) (string, VA, error) {
	var tag string
	if err := json.Unmarshal(raw[0], &tag); err != nil {
		var zero VA
		return "", zero, fmt.Errorf("codec/json: invalid Value tag: %w", err)
	}
	kind, err := kindFromValueTag(opts.FormatVersion, tag)
	if err != nil {
		var zero VA
		return "", zero, err
	}
	attrs, err := decodeVA(raw[1])
	if err != nil {
		var zero VA
		return "", zero, fmt.Errorf("codec/json: decode value attributes: %w", err)
	}
	return kind, attrs, nil
}

func decodeValueByKind[TA any, VA any](
	opts Options,
	decodeTA AttrDecoder[TA],
	decodeVA ValueAttrDecoder[VA],
	kind string,
	attrs VA,
	raw []json.RawMessage,
) (ir.Value[TA, VA], error) {
	switch kind {
	case "Literal":
		return decodeLiteralValue[TA, VA](opts, attrs, raw)
	case "Constructor":
		return decodeConstructorValue[TA, VA](opts, attrs, raw)
	case "Tuple":
		return decodeTupleValue(opts, decodeTA, decodeVA, attrs, raw)
	case "List":
		return decodeListValue(opts, decodeTA, decodeVA, attrs, raw)
	case "Record":
		return decodeRecordValueNode(opts, decodeTA, decodeVA, attrs, raw)
	case "Variable":
		return decodeVariableValue[TA, VA](opts, attrs, raw)
	case "Reference":
		return decodeReferenceValue[TA, VA](opts, attrs, raw)
	case "Field":
		return decodeFieldValueNode(opts, decodeTA, decodeVA, attrs, raw)
	case "FieldFunction":
		return decodeFieldFunctionValue[TA, VA](opts, attrs, raw)
	case "Apply":
		return decodeApplyValue(opts, decodeTA, decodeVA, attrs, raw)
	case "Lambda":
		return decodeLambdaValue(opts, decodeTA, decodeVA, attrs, raw)
	case "LetDefinition":
		return decodeLetDefinitionValue(opts, decodeTA, decodeVA, attrs, raw)
	case "LetRecursion":
		return decodeLetRecursionValue(opts, decodeTA, decodeVA, attrs, raw)
	case "Destructure":
		return decodeDestructureValue(opts, decodeTA, decodeVA, attrs, raw)
	case "IfThenElse":
		return decodeIfThenElseValue(opts, decodeTA, decodeVA, attrs, raw)
	case "PatternMatch":
		return decodePatternMatchValue(opts, decodeTA, decodeVA, attrs, raw)
	case "UpdateRecord":
		return decodeUpdateRecordValue(opts, decodeTA, decodeVA, attrs, raw)
	case "Unit":
		return decodeUnitValueNode[TA, VA](attrs, raw)
	default:
		return nil, fmt.Errorf("codec/json: unsupported Value kind %q", kind)
	}
}

func decodeLiteralValue[TA any, VA any](opts Options, attrs VA, raw []json.RawMessage) (ir.Value[TA, VA], error) {
	if len(raw) != 3 {
		return nil, fmt.Errorf("codec/json: Literal expects 3 elements, got %d", len(raw))
	}
	lit, err := DecodeLiteral(opts, raw[2])
	if err != nil {
		return nil, err
	}
	return ir.NewLiteralValue[TA, VA](attrs, lit), nil
}

func decodeConstructorValue[TA any, VA any](opts Options, attrs VA, raw []json.RawMessage) (ir.Value[TA, VA], error) {
	if len(raw) != 3 {
		return nil, fmt.Errorf("codec/json: Constructor expects 3 elements, got %d", len(raw))
	}
	fq, err := DecodeFQName(opts, raw[2])
	if err != nil {
		return nil, err
	}
	return ir.NewConstructorValue[TA, VA](attrs, fq), nil
}

func decodeTupleValue[TA any, VA any](opts Options, decodeTA AttrDecoder[TA], decodeVA ValueAttrDecoder[VA], attrs VA, raw []json.RawMessage) (ir.Value[TA, VA], error) {
	if len(raw) != 3 {
		return nil, fmt.Errorf("codec/json: Tuple expects 3 elements, got %d", len(raw))
	}
	elems, err := decodeValueList(opts, decodeTA, decodeVA, raw[2])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode Tuple elements: %w", err)
	}
	return ir.NewTupleValue(attrs, elems), nil
}

func decodeListValue[TA any, VA any](opts Options, decodeTA AttrDecoder[TA], decodeVA ValueAttrDecoder[VA], attrs VA, raw []json.RawMessage) (ir.Value[TA, VA], error) {
	if len(raw) != 3 {
		return nil, fmt.Errorf("codec/json: List expects 3 elements, got %d", len(raw))
	}
	items, err := decodeValueList(opts, decodeTA, decodeVA, raw[2])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode List items: %w", err)
	}
	return ir.NewListValue(attrs, items), nil
}

func decodeRecordValueNode[TA any, VA any](opts Options, decodeTA AttrDecoder[TA], decodeVA ValueAttrDecoder[VA], attrs VA, raw []json.RawMessage) (ir.Value[TA, VA], error) {
	if len(raw) != 3 {
		return nil, fmt.Errorf("codec/json: Record expects 3 elements, got %d", len(raw))
	}
	fields, err := decodeRecordFieldList(opts, decodeTA, decodeVA, raw[2])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode Record fields: %w", err)
	}
	return ir.NewRecordValue(attrs, fields), nil
}

func decodeVariableValue[TA any, VA any](opts Options, attrs VA, raw []json.RawMessage) (ir.Value[TA, VA], error) {
	if len(raw) != 3 {
		return nil, fmt.Errorf("codec/json: Variable expects 3 elements, got %d", len(raw))
	}
	name, err := DecodeName(opts, raw[2])
	if err != nil {
		return nil, err
	}
	return ir.NewVariableValue[TA, VA](attrs, name), nil
}

func decodeReferenceValue[TA any, VA any](opts Options, attrs VA, raw []json.RawMessage) (ir.Value[TA, VA], error) {
	if len(raw) != 3 {
		return nil, fmt.Errorf("codec/json: Reference expects 3 elements, got %d", len(raw))
	}
	fq, err := DecodeFQName(opts, raw[2])
	if err != nil {
		return nil, err
	}
	return ir.NewReferenceValue[TA, VA](attrs, fq), nil
}

func decodeFieldValueNode[TA any, VA any](opts Options, decodeTA AttrDecoder[TA], decodeVA ValueAttrDecoder[VA], attrs VA, raw []json.RawMessage) (ir.Value[TA, VA], error) {
	if len(raw) != 4 {
		return nil, fmt.Errorf("codec/json: Field expects 4 elements, got %d", len(raw))
	}
	subject, err := DecodeValue(opts, decodeTA, decodeVA, raw[2])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode Field subject: %w", err)
	}
	fieldName, err := DecodeName(opts, raw[3])
	if err != nil {
		return nil, err
	}
	return ir.NewFieldValue[TA, VA](attrs, subject, fieldName), nil
}

func decodeFieldFunctionValue[TA any, VA any](opts Options, attrs VA, raw []json.RawMessage) (ir.Value[TA, VA], error) {
	if len(raw) != 3 {
		return nil, fmt.Errorf("codec/json: FieldFunction expects 3 elements, got %d", len(raw))
	}
	fieldName, err := DecodeName(opts, raw[2])
	if err != nil {
		return nil, err
	}
	return ir.NewFieldFunctionValue[TA, VA](attrs, fieldName), nil
}

func decodeApplyValue[TA any, VA any](opts Options, decodeTA AttrDecoder[TA], decodeVA ValueAttrDecoder[VA], attrs VA, raw []json.RawMessage) (ir.Value[TA, VA], error) {
	if len(raw) != 4 {
		return nil, fmt.Errorf("codec/json: Apply expects 4 elements, got %d", len(raw))
	}
	fn, err := DecodeValue(opts, decodeTA, decodeVA, raw[2])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode Apply function: %w", err)
	}
	arg, err := DecodeValue(opts, decodeTA, decodeVA, raw[3])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode Apply argument: %w", err)
	}
	return ir.NewApplyValue[TA, VA](attrs, fn, arg), nil
}

func decodeLambdaValue[TA any, VA any](opts Options, decodeTA AttrDecoder[TA], decodeVA ValueAttrDecoder[VA], attrs VA, raw []json.RawMessage) (ir.Value[TA, VA], error) {
	if len(raw) != 4 {
		return nil, fmt.Errorf("codec/json: Lambda expects 4 elements, got %d", len(raw))
	}
	decodePatternVA := AttrDecoder[VA](decodeVA)
	pattern, err := DecodePattern(opts, decodePatternVA, raw[2])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode Lambda pattern: %w", err)
	}
	body, err := DecodeValue(opts, decodeTA, decodeVA, raw[3])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode Lambda body: %w", err)
	}
	return ir.NewLambdaValue[TA, VA](attrs, pattern, body), nil
}

func decodeLetDefinitionValue[TA any, VA any](opts Options, decodeTA AttrDecoder[TA], decodeVA ValueAttrDecoder[VA], attrs VA, raw []json.RawMessage) (ir.Value[TA, VA], error) {
	if len(raw) != 5 {
		return nil, fmt.Errorf("codec/json: LetDefinition expects 5 elements, got %d", len(raw))
	}
	valueName, err := DecodeName(opts, raw[2])
	if err != nil {
		return nil, err
	}
	def, err := decodeValueDefinition(opts, decodeTA, decodeVA, raw[3])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode LetDefinition definition: %w", err)
	}
	inValue, err := DecodeValue(opts, decodeTA, decodeVA, raw[4])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode LetDefinition inValue: %w", err)
	}
	return ir.NewLetDefinitionValue(attrs, valueName, def, inValue), nil
}

func decodeLetRecursionValue[TA any, VA any](opts Options, decodeTA AttrDecoder[TA], decodeVA ValueAttrDecoder[VA], attrs VA, raw []json.RawMessage) (ir.Value[TA, VA], error) {
	if len(raw) != 4 {
		return nil, fmt.Errorf("codec/json: LetRecursion expects 4 elements, got %d", len(raw))
	}
	defs, err := decodeNamedDefinitionsList(opts, decodeTA, decodeVA, raw[2])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode LetRecursion definitions: %w", err)
	}
	inValue, err := DecodeValue(opts, decodeTA, decodeVA, raw[3])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode LetRecursion inValue: %w", err)
	}
	return ir.NewLetRecursionValue(attrs, defs, inValue), nil
}

func decodeDestructureValue[TA any, VA any](opts Options, decodeTA AttrDecoder[TA], decodeVA ValueAttrDecoder[VA], attrs VA, raw []json.RawMessage) (ir.Value[TA, VA], error) {
	if len(raw) != 5 {
		return nil, fmt.Errorf("codec/json: Destructure expects 5 elements, got %d", len(raw))
	}
	decodePatternVA := AttrDecoder[VA](decodeVA)
	pattern, err := DecodePattern(opts, decodePatternVA, raw[2])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode Destructure pattern: %w", err)
	}
	valueToDestruct, err := DecodeValue(opts, decodeTA, decodeVA, raw[3])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode Destructure valueToDestruct: %w", err)
	}
	inValue, err := DecodeValue(opts, decodeTA, decodeVA, raw[4])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode Destructure inValue: %w", err)
	}
	return ir.NewDestructureValue[TA, VA](attrs, pattern, valueToDestruct, inValue), nil
}

func decodeIfThenElseValue[TA any, VA any](opts Options, decodeTA AttrDecoder[TA], decodeVA ValueAttrDecoder[VA], attrs VA, raw []json.RawMessage) (ir.Value[TA, VA], error) {
	if len(raw) != 5 {
		return nil, fmt.Errorf("codec/json: IfThenElse expects 5 elements, got %d", len(raw))
	}
	cond, err := DecodeValue(opts, decodeTA, decodeVA, raw[2])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode IfThenElse condition: %w", err)
	}
	thenBranch, err := DecodeValue(opts, decodeTA, decodeVA, raw[3])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode IfThenElse thenBranch: %w", err)
	}
	elseBranch, err := DecodeValue(opts, decodeTA, decodeVA, raw[4])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode IfThenElse elseBranch: %w", err)
	}
	return ir.NewIfThenElseValue[TA, VA](attrs, cond, thenBranch, elseBranch), nil
}

func decodePatternMatchValue[TA any, VA any](opts Options, decodeTA AttrDecoder[TA], decodeVA ValueAttrDecoder[VA], attrs VA, raw []json.RawMessage) (ir.Value[TA, VA], error) {
	if len(raw) != 4 {
		return nil, fmt.Errorf("codec/json: PatternMatch expects 4 elements, got %d", len(raw))
	}
	subject, err := DecodeValue(opts, decodeTA, decodeVA, raw[2])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode PatternMatch subject: %w", err)
	}
	cases, err := decodePatternMatchCasesList(opts, decodeTA, decodeVA, raw[3])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode PatternMatch cases: %w", err)
	}
	return ir.NewPatternMatchValue[TA, VA](attrs, subject, cases), nil
}

func decodeUpdateRecordValue[TA any, VA any](opts Options, decodeTA AttrDecoder[TA], decodeVA ValueAttrDecoder[VA], attrs VA, raw []json.RawMessage) (ir.Value[TA, VA], error) {
	if len(raw) != 4 {
		return nil, fmt.Errorf("codec/json: UpdateRecord expects 4 elements, got %d", len(raw))
	}
	valueToUpdate, err := DecodeValue(opts, decodeTA, decodeVA, raw[2])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode UpdateRecord valueToUpdate: %w", err)
	}
	fields, err := decodeRecordFieldList(opts, decodeTA, decodeVA, raw[3])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode UpdateRecord fields: %w", err)
	}
	return ir.NewUpdateRecordValue[TA, VA](attrs, valueToUpdate, fields), nil
}

func decodeUnitValueNode[TA any, VA any](attrs VA, raw []json.RawMessage) (ir.Value[TA, VA], error) {
	if len(raw) != 2 {
		return nil, fmt.Errorf("codec/json: Unit expects 2 elements, got %d", len(raw))
	}
	return ir.NewUnitValue[TA, VA](attrs), nil
}

// Helper decode functions

func decodeValueList[TA any, VA any](opts Options, decodeTA AttrDecoder[TA], decodeVA ValueAttrDecoder[VA], raw json.RawMessage) ([]ir.Value[TA, VA], error) {
	var items []json.RawMessage
	if err := json.Unmarshal(raw, &items); err != nil {
		return nil, fmt.Errorf("codec/json: expected list: %w", err)
	}
	out := make([]ir.Value[TA, VA], len(items))
	for i := range items {
		v, err := DecodeValue(opts, decodeTA, decodeVA, items[i])
		if err != nil {
			return nil, err
		}
		out[i] = v
	}
	return out, nil
}

func decodeRecordFieldList[TA any, VA any](opts Options, decodeTA AttrDecoder[TA], decodeVA ValueAttrDecoder[VA], raw json.RawMessage) ([]ir.RecordField[TA, VA], error) {
	var items []json.RawMessage
	if err := json.Unmarshal(raw, &items); err != nil {
		return nil, fmt.Errorf("codec/json: expected list: %w", err)
	}
	out := make([]ir.RecordField[TA, VA], len(items))
	for i := range items {
		var pair []json.RawMessage
		if err := json.Unmarshal(items[i], &pair); err != nil {
			return nil, fmt.Errorf("codec/json: expected field pair: %w", err)
		}
		if len(pair) != 2 {
			return nil, fmt.Errorf("codec/json: field pair expects 2 elements, got %d", len(pair))
		}
		name, err := DecodeName(opts, pair[0])
		if err != nil {
			return nil, err
		}
		value, err := DecodeValue(opts, decodeTA, decodeVA, pair[1])
		if err != nil {
			return nil, err
		}
		out[i] = ir.RecordFieldFromParts[TA, VA](name, value)
	}
	return out, nil
}

func decodeValueDefinition[TA any, VA any](opts Options, decodeTA AttrDecoder[TA], decodeVA ValueAttrDecoder[VA], raw json.RawMessage) (ir.ValueDefinition[TA, VA], error) {
	var obj struct {
		InputTypes json.RawMessage `json:"inputTypes"`
		OutputType json.RawMessage `json:"outputType"`
		Body       json.RawMessage `json:"body"`
	}
	if err := json.Unmarshal(raw, &obj); err != nil {
		return ir.ValueDefinition[TA, VA]{}, fmt.Errorf("codec/json: expected definition object: %w", err)
	}

	inputs, err := decodeDefinitionInputTypesList(opts, decodeTA, decodeVA, obj.InputTypes)
	if err != nil {
		return ir.ValueDefinition[TA, VA]{}, err
	}

	outputType, err := DecodeType(opts, decodeTA, obj.OutputType)
	if err != nil {
		return ir.ValueDefinition[TA, VA]{}, fmt.Errorf("codec/json: decode outputType: %w", err)
	}

	body, err := DecodeValue(opts, decodeTA, decodeVA, obj.Body)
	if err != nil {
		return ir.ValueDefinition[TA, VA]{}, fmt.Errorf("codec/json: decode body: %w", err)
	}

	return ir.NewValueDefinition(inputs, outputType, body), nil
}

func decodeDefinitionInputTypesList[TA any, VA any](opts Options, decodeTA AttrDecoder[TA], decodeVA ValueAttrDecoder[VA], raw json.RawMessage) ([]ir.ValueDefinitionInput[TA, VA], error) {
	var items []json.RawMessage
	if err := json.Unmarshal(raw, &items); err != nil {
		return nil, fmt.Errorf("codec/json: expected input types list: %w", err)
	}
	out := make([]ir.ValueDefinitionInput[TA, VA], len(items))
	for i := range items {
		var triple []json.RawMessage
		if err := json.Unmarshal(items[i], &triple); err != nil {
			return nil, fmt.Errorf("codec/json: expected input type triple: %w", err)
		}
		if len(triple) != 3 {
			return nil, fmt.Errorf("codec/json: input type expects 3 elements, got %d", len(triple))
		}
		name, err := DecodeName(opts, triple[0])
		if err != nil {
			return nil, err
		}
		attr, err := decodeVA(triple[1])
		if err != nil {
			return nil, fmt.Errorf("codec/json: decode input attribute: %w", err)
		}
		tpe, err := DecodeType(opts, decodeTA, triple[2])
		if err != nil {
			return nil, fmt.Errorf("codec/json: decode input type: %w", err)
		}
		out[i] = ir.ValueDefinitionInputFromParts(name, attr, tpe)
	}
	return out, nil
}

func decodeNamedDefinitionsList[TA any, VA any](opts Options, decodeTA AttrDecoder[TA], decodeVA ValueAttrDecoder[VA], raw json.RawMessage) ([]ir.NamedValueDefinition[TA, VA], error) {
	var items []json.RawMessage
	if err := json.Unmarshal(raw, &items); err != nil {
		return nil, fmt.Errorf("codec/json: expected definitions list: %w", err)
	}
	out := make([]ir.NamedValueDefinition[TA, VA], len(items))
	for i := range items {
		var pair []json.RawMessage
		if err := json.Unmarshal(items[i], &pair); err != nil {
			return nil, fmt.Errorf("codec/json: expected definition pair: %w", err)
		}
		if len(pair) != 2 {
			return nil, fmt.Errorf("codec/json: definition pair expects 2 elements, got %d", len(pair))
		}
		name, err := DecodeName(opts, pair[0])
		if err != nil {
			return nil, err
		}
		def, err := decodeValueDefinition(opts, decodeTA, decodeVA, pair[1])
		if err != nil {
			return nil, err
		}
		out[i] = ir.NamedValueDefinitionFromParts(name, def)
	}
	return out, nil
}

func decodePatternMatchCasesList[TA any, VA any](opts Options, decodeTA AttrDecoder[TA], decodeVA ValueAttrDecoder[VA], raw json.RawMessage) ([]ir.PatternMatchCase[TA, VA], error) {
	var items []json.RawMessage
	if err := json.Unmarshal(raw, &items); err != nil {
		return nil, fmt.Errorf("codec/json: expected cases list: %w", err)
	}
	decodePatternVA := AttrDecoder[VA](decodeVA)
	out := make([]ir.PatternMatchCase[TA, VA], len(items))
	for i := range items {
		var pair []json.RawMessage
		if err := json.Unmarshal(items[i], &pair); err != nil {
			return nil, fmt.Errorf("codec/json: expected case pair: %w", err)
		}
		if len(pair) != 2 {
			return nil, fmt.Errorf("codec/json: case pair expects 2 elements, got %d", len(pair))
		}
		pattern, err := DecodePattern(opts, decodePatternVA, pair[0])
		if err != nil {
			return nil, err
		}
		body, err := DecodeValue(opts, decodeTA, decodeVA, pair[1])
		if err != nil {
			return nil, err
		}
		out[i] = ir.PatternMatchCaseFromParts[TA, VA](pattern, body)
	}
	return out, nil
}

// Tag mapping functions

func tagForValue(version FormatVersion, kind string) string {
	if version == FormatV1 {
		switch kind {
		case "Literal":
			return "literal"
		case "Constructor":
			return "constructor"
		case "Tuple":
			return "tuple"
		case "List":
			return "list"
		case "Record":
			return "record"
		case "Variable":
			return "variable"
		case "Reference":
			return "reference"
		case "Field":
			return "field"
		case "FieldFunction":
			return "field_function"
		case "Apply":
			return "apply"
		case "Lambda":
			return "lambda"
		case "LetDefinition":
			return "let_definition"
		case "LetRecursion":
			return "let_recursion"
		case "Destructure":
			return "destructure"
		case "IfThenElse":
			return "if_then_else"
		case "PatternMatch":
			return "pattern_match"
		case "UpdateRecord":
			return "update_record"
		case "Unit":
			return "unit"
		default:
			return kind
		}
	}
	return kind
}

func kindFromValueTag(version FormatVersion, tag string) (string, error) {
	if version == FormatV1 {
		switch tag {
		case "literal":
			return "Literal", nil
		case "constructor":
			return "Constructor", nil
		case "tuple":
			return "Tuple", nil
		case "list":
			return "List", nil
		case "record":
			return "Record", nil
		case "variable":
			return "Variable", nil
		case "reference":
			return "Reference", nil
		case "field":
			return "Field", nil
		case "field_function":
			return "FieldFunction", nil
		case "apply":
			return "Apply", nil
		case "lambda":
			return "Lambda", nil
		case "let_definition":
			return "LetDefinition", nil
		case "let_recursion":
			return "LetRecursion", nil
		case "destructure":
			return "Destructure", nil
		case "if_then_else":
			return "IfThenElse", nil
		case "pattern_match":
			return "PatternMatch", nil
		case "update_record":
			return "UpdateRecord", nil
		case "unit":
			return "Unit", nil
		default:
			return "", fmt.Errorf("codec/json: unknown v1 Value tag %q", tag)
		}
	}

	// v2/v3
	switch tag {
	case "Literal", "Constructor", "Tuple", "List", "Record", "Variable", "Reference",
		"Field", "FieldFunction", "Apply", "Lambda", "LetDefinition", "LetRecursion",
		"Destructure", "IfThenElse", "PatternMatch", "UpdateRecord", "Unit":
		return tag, nil
	default:
		return "", fmt.Errorf("codec/json: unknown Value tag %q", tag)
	}
}
