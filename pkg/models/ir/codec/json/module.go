package json

import (
	"bytes"
	"encoding/json"
	"fmt"

	ir "github.com/finos/morphir/pkg/models/ir"
)

// EncodeModuleSpecification encodes a ModuleSpecification using Morphir-compatible JSON.
//
// Format: { "types": [[name, docSpec], ...], "values": [[name, docSpec], ...], "doc": string|null }
func EncodeModuleSpecification[TA any](opts Options, encodeTypeAttributes AttrEncoder[TA], spec ir.ModuleSpecification[TA]) ([]byte, error) {
	opts = opts.withDefaults()
	if encodeTypeAttributes == nil {
		return nil, fmt.Errorf("codec/json: encodeTypeAttributes must not be nil")
	}

	// Encode types
	typesRaw, err := encodeModuleSpecificationTypes(opts, encodeTypeAttributes, spec.Types())
	if err != nil {
		return nil, err
	}

	// Encode values
	valuesRaw, err := encodeModuleSpecificationValues(opts, encodeTypeAttributes, spec.Values())
	if err != nil {
		return nil, err
	}

	// Encode doc
	var docRaw json.RawMessage
	if spec.Doc() != nil {
		docBytes, err := json.Marshal(*spec.Doc())
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode module doc: %w", err)
		}
		docRaw = docBytes
	} else {
		docRaw = json.RawMessage("null")
	}

	obj := map[string]json.RawMessage{
		"types":  typesRaw,
		"values": valuesRaw,
		"doc":    docRaw,
	}
	encoded, err := json.Marshal(obj)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode module specification: %w", err)
	}
	return encoded, nil
}

func encodeModuleSpecificationTypes[TA any](opts Options, encodeTA AttrEncoder[TA], types []ir.ModuleSpecificationType[TA]) (json.RawMessage, error) {
	typesRaw := make([]json.RawMessage, len(types))
	for i, t := range types {
		nameRaw, err := EncodeName(opts, t.Name())
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode type name: %w", err)
		}

		// Encode Documented[TypeSpecification]
		docSpec := t.Spec()
		encodeTypeSpec := func(ts ir.TypeSpecification[TA]) (json.RawMessage, error) {
			data, err := EncodeTypeSpecification(opts, encodeTA, ts)
			if err != nil {
				return nil, err
			}
			return json.RawMessage(data), nil
		}
		docSpecRaw, err := encodeDocumentedRaw(opts, encodeTypeSpec, docSpec)
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode type spec: %w", err)
		}

		pair := []json.RawMessage{json.RawMessage(nameRaw), docSpecRaw}
		pairRaw, err := json.Marshal(pair)
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode type pair: %w", err)
		}
		typesRaw[i] = json.RawMessage(pairRaw)
	}

	encoded, err := json.Marshal(typesRaw)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode types list: %w", err)
	}
	return encoded, nil
}

func encodeModuleSpecificationValues[TA any](opts Options, encodeTA AttrEncoder[TA], values []ir.ModuleSpecificationValue[TA]) (json.RawMessage, error) {
	valuesRaw := make([]json.RawMessage, len(values))
	for i, v := range values {
		nameRaw, err := EncodeName(opts, v.Name())
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode value name: %w", err)
		}

		// Encode Documented[ValueSpecification]
		docSpec := v.Spec()
		encodeValueSpec := func(vs ir.ValueSpecification[TA]) (json.RawMessage, error) {
			return encodeValueSpecificationRaw(opts, encodeTA, vs)
		}
		docSpecRaw, err := encodeDocumentedRaw(opts, encodeValueSpec, docSpec)
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode value spec: %w", err)
		}

		pair := []json.RawMessage{json.RawMessage(nameRaw), docSpecRaw}
		pairRaw, err := json.Marshal(pair)
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode value pair: %w", err)
		}
		valuesRaw[i] = json.RawMessage(pairRaw)
	}

	encoded, err := json.Marshal(valuesRaw)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode values list: %w", err)
	}
	return encoded, nil
}

// DecodeModuleSpecification decodes a ModuleSpecification using Morphir-compatible JSON.
func DecodeModuleSpecification[TA any](opts Options, decodeTypeAttributes AttrDecoder[TA], data []byte) (ir.ModuleSpecification[TA], error) {
	opts = opts.withDefaults()
	if decodeTypeAttributes == nil {
		return ir.EmptyModuleSpecification[TA](), fmt.Errorf("codec/json: decodeTypeAttributes must not be nil")
	}

	trimmed := bytes.TrimSpace(data)
	if bytes.Equal(trimmed, []byte("null")) {
		return ir.EmptyModuleSpecification[TA](), fmt.Errorf("codec/json: expected module specification, got null")
	}

	var obj struct {
		Types  json.RawMessage `json:"types"`
		Values json.RawMessage `json:"values"`
		Doc    *string         `json:"doc"`
	}
	if err := json.Unmarshal(trimmed, &obj); err != nil {
		return ir.EmptyModuleSpecification[TA](), fmt.Errorf("codec/json: decode module specification: %w", err)
	}

	types, err := decodeModuleSpecificationTypes(opts, decodeTypeAttributes, obj.Types)
	if err != nil {
		return ir.EmptyModuleSpecification[TA](), err
	}

	values, err := decodeModuleSpecificationValues(opts, decodeTypeAttributes, obj.Values)
	if err != nil {
		return ir.EmptyModuleSpecification[TA](), err
	}

	return ir.NewModuleSpecification(types, values, obj.Doc), nil
}

func decodeModuleSpecificationTypes[TA any](opts Options, decodeTA AttrDecoder[TA], data json.RawMessage) ([]ir.ModuleSpecificationType[TA], error) {
	var typesRaw []json.RawMessage
	if err := json.Unmarshal(data, &typesRaw); err != nil {
		return nil, fmt.Errorf("codec/json: decode types list: %w", err)
	}

	types := make([]ir.ModuleSpecificationType[TA], len(typesRaw))
	for i, typeRaw := range typesRaw {
		var pair []json.RawMessage
		if err := json.Unmarshal(typeRaw, &pair); err != nil {
			return nil, fmt.Errorf("codec/json: decode type pair: %w", err)
		}
		if len(pair) != 2 {
			return nil, fmt.Errorf("codec/json: type pair expects 2 elements, got %d", len(pair))
		}

		name, err := DecodeName(opts, pair[0])
		if err != nil {
			return nil, fmt.Errorf("codec/json: decode type name: %w", err)
		}

		decodeTypeSpec := func(raw json.RawMessage) (ir.TypeSpecification[TA], error) {
			return DecodeTypeSpecification(opts, decodeTA, raw)
		}
		docSpec, err := DecodeDocumented(opts, decodeTypeSpec, pair[1])
		if err != nil {
			return nil, fmt.Errorf("codec/json: decode type spec: %w", err)
		}

		types[i] = ir.ModuleSpecificationTypeFromParts[TA](name, docSpec)
	}

	return types, nil
}

func decodeModuleSpecificationValues[TA any](opts Options, decodeTA AttrDecoder[TA], data json.RawMessage) ([]ir.ModuleSpecificationValue[TA], error) {
	var valuesRaw []json.RawMessage
	if err := json.Unmarshal(data, &valuesRaw); err != nil {
		return nil, fmt.Errorf("codec/json: decode values list: %w", err)
	}

	values := make([]ir.ModuleSpecificationValue[TA], len(valuesRaw))
	for i, valueRaw := range valuesRaw {
		var pair []json.RawMessage
		if err := json.Unmarshal(valueRaw, &pair); err != nil {
			return nil, fmt.Errorf("codec/json: decode value pair: %w", err)
		}
		if len(pair) != 2 {
			return nil, fmt.Errorf("codec/json: value pair expects 2 elements, got %d", len(pair))
		}

		name, err := DecodeName(opts, pair[0])
		if err != nil {
			return nil, fmt.Errorf("codec/json: decode value name: %w", err)
		}

		decodeValueSpec := func(raw json.RawMessage) (ir.ValueSpecification[TA], error) {
			return DecodeValueSpecification(opts, decodeTA, raw)
		}
		docSpec, err := DecodeDocumented(opts, decodeValueSpec, pair[1])
		if err != nil {
			return nil, fmt.Errorf("codec/json: decode value spec: %w", err)
		}

		values[i] = ir.ModuleSpecificationValueFromParts(name, docSpec)
	}

	return values, nil
}

// EncodeModuleDefinition encodes a ModuleDefinition using Morphir-compatible JSON.
//
// Format: { "types": [[name, accessControlled], ...], "values": [[name, accessControlled], ...], "doc": string|null }
func EncodeModuleDefinition[TA any, VA any](
	opts Options,
	encodeTypeAttributes AttrEncoder[TA],
	encodeValueAttributes ValueAttrEncoder[VA],
	def ir.ModuleDefinition[TA, VA],
) ([]byte, error) {
	opts = opts.withDefaults()
	if encodeTypeAttributes == nil {
		return nil, fmt.Errorf("codec/json: encodeTypeAttributes must not be nil")
	}
	if encodeValueAttributes == nil {
		return nil, fmt.Errorf("codec/json: encodeValueAttributes must not be nil")
	}

	// Encode types
	typesRaw, err := encodeModuleDefinitionTypes(opts, encodeTypeAttributes, def.Types())
	if err != nil {
		return nil, err
	}

	// Encode values
	valuesRaw, err := encodeModuleDefinitionValues(opts, encodeTypeAttributes, encodeValueAttributes, def.Values())
	if err != nil {
		return nil, err
	}

	// Encode doc
	var docRaw json.RawMessage
	if def.Doc() != nil {
		docBytes, err := json.Marshal(*def.Doc())
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode module doc: %w", err)
		}
		docRaw = docBytes
	} else {
		docRaw = json.RawMessage("null")
	}

	obj := map[string]json.RawMessage{
		"types":  typesRaw,
		"values": valuesRaw,
		"doc":    docRaw,
	}
	encoded, err := json.Marshal(obj)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode module definition: %w", err)
	}
	return encoded, nil
}

func encodeModuleDefinitionTypes[TA any](opts Options, encodeTA AttrEncoder[TA], types []ir.ModuleDefinitionType[TA]) (json.RawMessage, error) {
	typesRaw := make([]json.RawMessage, len(types))
	for i, t := range types {
		nameRaw, err := EncodeName(opts, t.Name())
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode type name: %w", err)
		}

		// Encode AccessControlled[Documented[TypeDefinition]]
		acDocDef := t.Definition()
		encodeDocTypeDef := func(docDef ir.Documented[ir.TypeDefinition[TA]]) (json.RawMessage, error) {
			encodeTypeDef := func(td ir.TypeDefinition[TA]) (json.RawMessage, error) {
				data, err := EncodeTypeDefinition(opts, encodeTA, td)
				if err != nil {
					return nil, err
				}
				return json.RawMessage(data), nil
			}
			return encodeDocumentedRaw(opts, encodeTypeDef, docDef)
		}
		acRaw, err := EncodeAccessControlled(opts, encodeDocTypeDef, acDocDef)
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode type definition: %w", err)
		}

		pair := []json.RawMessage{json.RawMessage(nameRaw), json.RawMessage(acRaw)}
		pairRaw, err := json.Marshal(pair)
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode type pair: %w", err)
		}
		typesRaw[i] = json.RawMessage(pairRaw)
	}

	encoded, err := json.Marshal(typesRaw)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode types list: %w", err)
	}
	return encoded, nil
}

func encodeModuleDefinitionValues[TA any, VA any](
	opts Options,
	encodeTA AttrEncoder[TA],
	encodeVA ValueAttrEncoder[VA],
	values []ir.ModuleDefinitionValue[TA, VA],
) (json.RawMessage, error) {
	valuesRaw := make([]json.RawMessage, len(values))
	for i, v := range values {
		nameRaw, err := EncodeName(opts, v.Name())
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode value name: %w", err)
		}

		// Encode AccessControlled[Documented[ValueDefinition]]
		acDocDef := v.Definition()
		encodeDocValueDef := func(docDef ir.Documented[ir.ValueDefinition[TA, VA]]) (json.RawMessage, error) {
			encodeValueDef := func(vd ir.ValueDefinition[TA, VA]) (json.RawMessage, error) {
				return encodeValueDefinitionRaw(opts, encodeTA, encodeVA, vd)
			}
			return encodeDocumentedRaw(opts, encodeValueDef, docDef)
		}
		acRaw, err := EncodeAccessControlled(opts, encodeDocValueDef, acDocDef)
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode value definition: %w", err)
		}

		pair := []json.RawMessage{json.RawMessage(nameRaw), json.RawMessage(acRaw)}
		pairRaw, err := json.Marshal(pair)
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode value pair: %w", err)
		}
		valuesRaw[i] = json.RawMessage(pairRaw)
	}

	encoded, err := json.Marshal(valuesRaw)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode values list: %w", err)
	}
	return encoded, nil
}

// DecodeModuleDefinition decodes a ModuleDefinition using Morphir-compatible JSON.
func DecodeModuleDefinition[TA any, VA any](
	opts Options,
	decodeTypeAttributes AttrDecoder[TA],
	decodeValueAttributes ValueAttrDecoder[VA],
	data []byte,
) (ir.ModuleDefinition[TA, VA], error) {
	opts = opts.withDefaults()
	if decodeTypeAttributes == nil {
		return ir.EmptyModuleDefinition[TA, VA](), fmt.Errorf("codec/json: decodeTypeAttributes must not be nil")
	}
	if decodeValueAttributes == nil {
		return ir.EmptyModuleDefinition[TA, VA](), fmt.Errorf("codec/json: decodeValueAttributes must not be nil")
	}

	trimmed := bytes.TrimSpace(data)
	if bytes.Equal(trimmed, []byte("null")) {
		return ir.EmptyModuleDefinition[TA, VA](), fmt.Errorf("codec/json: expected module definition, got null")
	}

	var obj struct {
		Types  json.RawMessage `json:"types"`
		Values json.RawMessage `json:"values"`
		Doc    *string         `json:"doc"`
	}
	if err := json.Unmarshal(trimmed, &obj); err != nil {
		return ir.EmptyModuleDefinition[TA, VA](), fmt.Errorf("codec/json: decode module definition: %w", err)
	}

	types, err := decodeModuleDefinitionTypes(opts, decodeTypeAttributes, obj.Types)
	if err != nil {
		return ir.EmptyModuleDefinition[TA, VA](), err
	}

	values, err := decodeModuleDefinitionValues(opts, decodeTypeAttributes, decodeValueAttributes, obj.Values)
	if err != nil {
		return ir.EmptyModuleDefinition[TA, VA](), err
	}

	return ir.NewModuleDefinition(types, values, obj.Doc), nil
}

func decodeModuleDefinitionTypes[TA any](opts Options, decodeTA AttrDecoder[TA], data json.RawMessage) ([]ir.ModuleDefinitionType[TA], error) {
	var typesRaw []json.RawMessage
	if err := json.Unmarshal(data, &typesRaw); err != nil {
		return nil, fmt.Errorf("codec/json: decode types list: %w", err)
	}

	types := make([]ir.ModuleDefinitionType[TA], len(typesRaw))
	for i, typeRaw := range typesRaw {
		var pair []json.RawMessage
		if err := json.Unmarshal(typeRaw, &pair); err != nil {
			return nil, fmt.Errorf("codec/json: decode type pair: %w", err)
		}
		if len(pair) != 2 {
			return nil, fmt.Errorf("codec/json: type pair expects 2 elements, got %d", len(pair))
		}

		name, err := DecodeName(opts, pair[0])
		if err != nil {
			return nil, fmt.Errorf("codec/json: decode type name: %w", err)
		}

		decodeDocTypeDef := func(raw json.RawMessage) (ir.Documented[ir.TypeDefinition[TA]], error) {
			decodeTypeDef := func(raw json.RawMessage) (ir.TypeDefinition[TA], error) {
				return DecodeTypeDefinition(opts, decodeTA, raw)
			}
			return DecodeDocumented(opts, decodeTypeDef, raw)
		}
		acDocDef, err := DecodeAccessControlled(opts, decodeDocTypeDef, pair[1])
		if err != nil {
			return nil, fmt.Errorf("codec/json: decode type definition: %w", err)
		}

		types[i] = ir.ModuleDefinitionTypeFromParts[TA](name, acDocDef)
	}

	return types, nil
}

func decodeModuleDefinitionValues[TA any, VA any](
	opts Options,
	decodeTA AttrDecoder[TA],
	decodeVA ValueAttrDecoder[VA],
	data json.RawMessage,
) ([]ir.ModuleDefinitionValue[TA, VA], error) {
	var valuesRaw []json.RawMessage
	if err := json.Unmarshal(data, &valuesRaw); err != nil {
		return nil, fmt.Errorf("codec/json: decode values list: %w", err)
	}

	values := make([]ir.ModuleDefinitionValue[TA, VA], len(valuesRaw))
	for i, valueRaw := range valuesRaw {
		var pair []json.RawMessage
		if err := json.Unmarshal(valueRaw, &pair); err != nil {
			return nil, fmt.Errorf("codec/json: decode value pair: %w", err)
		}
		if len(pair) != 2 {
			return nil, fmt.Errorf("codec/json: value pair expects 2 elements, got %d", len(pair))
		}

		name, err := DecodeName(opts, pair[0])
		if err != nil {
			return nil, fmt.Errorf("codec/json: decode value name: %w", err)
		}

		decodeDocValueDef := func(raw json.RawMessage) (ir.Documented[ir.ValueDefinition[TA, VA]], error) {
			decodeValueDef := func(raw json.RawMessage) (ir.ValueDefinition[TA, VA], error) {
				return decodeValueDefinition(opts, decodeTA, decodeVA, raw)
			}
			return DecodeDocumented(opts, decodeValueDef, raw)
		}
		acDocDef, err := DecodeAccessControlled(opts, decodeDocValueDef, pair[1])
		if err != nil {
			return nil, fmt.Errorf("codec/json: decode value definition: %w", err)
		}

		values[i] = ir.ModuleDefinitionValueFromParts(name, acDocDef)
	}

	return values, nil
}
