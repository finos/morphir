package json

import (
	"encoding/json"
	"github.com/finos/morphir/runtime/libs/go/morphir/encoding"
)

type MarshalSettings struct {
	FormatVersion encoding.FormatVersion
}

func Marshal(v any, settings MarshalSettings) ([]byte, error) {
	// TODO: Implement
	switch v.(type) {
	case Marshaller:
		return v.(Marshaller).MarshalMorphirJSON(settings)
		//TODO: Add special handling for Versioned types
	default:
		bytes, err := json.Marshal(v)
		if err != nil {
			return nil, err
		}
		return bytes, nil
	}
}

type Marshaller interface {
	MarshalMorphirJSON(settings MarshalSettings) ([]byte, error)
}
