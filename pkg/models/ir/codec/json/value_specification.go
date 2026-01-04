package json

import (
	"bytes"
	"encoding/json"
	"fmt"

	ir "github.com/finos/morphir/pkg/models/ir"
)

// EncodeValueSpecification encodes a ValueSpecification using Morphir-compatible JSON.
//
// In Morphir-Elm: { "inputs": [[name, type], ...], "output": type }
func EncodeValueSpecification[TA any](opts Options, encodeTypeAttributes AttrEncoder[TA], spec ir.ValueSpecification[TA]) ([]byte, error) {
	opts = opts.withDefaults()
	if encodeTypeAttributes == nil {
		return nil, fmt.Errorf("codec/json: encodeTypeAttributes must not be nil")
	}

	raw, err := encodeValueSpecificationRaw(opts, encodeTypeAttributes, spec)
	if err != nil {
		return nil, err
	}
	return raw, nil
}

func encodeValueSpecificationRaw[TA any](opts Options, encodeTA AttrEncoder[TA], spec ir.ValueSpecification[TA]) (json.RawMessage, error) {
	// Encode inputs as [[name, type], ...]
	inputs := spec.Inputs()
	inputsRaw := make([]json.RawMessage, len(inputs))
	for i, inp := range inputs {
		nameRaw, err := EncodeName(opts, inp.Name())
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode input name: %w", err)
		}
		typeRaw, err := encodeTypeRaw(opts, encodeTA, inp.Type())
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode input type: %w", err)
		}
		pair := []json.RawMessage{json.RawMessage(nameRaw), typeRaw}
		pairRaw, err := json.Marshal(pair)
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode input pair: %w", err)
		}
		inputsRaw[i] = json.RawMessage(pairRaw)
	}

	inputsListRaw, err := json.Marshal(inputsRaw)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode inputs list: %w", err)
	}

	// Encode output type
	outputRaw, err := encodeTypeRaw(opts, encodeTA, spec.Output())
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode output type: %w", err)
	}

	obj := map[string]json.RawMessage{
		"inputs": json.RawMessage(inputsListRaw),
		"output": outputRaw,
	}
	encoded, err := json.Marshal(obj)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode value specification: %w", err)
	}
	return encoded, nil
}

// DecodeValueSpecification decodes a ValueSpecification using Morphir-compatible JSON.
func DecodeValueSpecification[TA any](opts Options, decodeTypeAttributes AttrDecoder[TA], data []byte) (ir.ValueSpecification[TA], error) {
	opts = opts.withDefaults()
	if decodeTypeAttributes == nil {
		var zero ir.ValueSpecification[TA]
		return zero, fmt.Errorf("codec/json: decodeTypeAttributes must not be nil")
	}

	trimmed := bytes.TrimSpace(data)
	if bytes.Equal(trimmed, []byte("null")) {
		var zero ir.ValueSpecification[TA]
		return zero, fmt.Errorf("codec/json: expected value specification, got null")
	}

	var obj struct {
		Inputs json.RawMessage `json:"inputs"`
		Output json.RawMessage `json:"output"`
	}
	if err := json.Unmarshal(trimmed, &obj); err != nil {
		var zero ir.ValueSpecification[TA]
		return zero, fmt.Errorf("codec/json: decode value specification: %w", err)
	}

	// Decode inputs
	var inputsRaw []json.RawMessage
	if err := json.Unmarshal(obj.Inputs, &inputsRaw); err != nil {
		var zero ir.ValueSpecification[TA]
		return zero, fmt.Errorf("codec/json: decode inputs list: %w", err)
	}

	inputs := make([]ir.ValueSpecificationInput[TA], len(inputsRaw))
	for i, inputRaw := range inputsRaw {
		var pair []json.RawMessage
		if err := json.Unmarshal(inputRaw, &pair); err != nil {
			var zero ir.ValueSpecification[TA]
			return zero, fmt.Errorf("codec/json: decode input pair: %w", err)
		}
		if len(pair) != 2 {
			var zero ir.ValueSpecification[TA]
			return zero, fmt.Errorf("codec/json: input pair expects 2 elements, got %d", len(pair))
		}

		name, err := DecodeName(opts, pair[0])
		if err != nil {
			var zero ir.ValueSpecification[TA]
			return zero, fmt.Errorf("codec/json: decode input name: %w", err)
		}
		tpe, err := DecodeType(opts, decodeTypeAttributes, pair[1])
		if err != nil {
			var zero ir.ValueSpecification[TA]
			return zero, fmt.Errorf("codec/json: decode input type: %w", err)
		}
		inputs[i] = ir.ValueSpecificationInputFromParts(name, tpe)
	}

	// Decode output type
	output, err := DecodeType(opts, decodeTypeAttributes, obj.Output)
	if err != nil {
		var zero ir.ValueSpecification[TA]
		return zero, fmt.Errorf("codec/json: decode output type: %w", err)
	}

	return ir.NewValueSpecification(inputs, output), nil
}
