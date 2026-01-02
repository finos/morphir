package json

import (
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

func TestNameDefaultEncodesAsArrayOfStrings(t *testing.T) {
	name := ir.NameFromParts([]string{"local", "name"})

	data, err := EncodeName(Options{FormatVersion: FormatV3}, name)
	if err != nil {
		t.Fatalf("EncodeName: %v", err)
	}

	decoded, err := DecodeName(Options{FormatVersion: FormatV3}, data)
	if err != nil {
		t.Fatalf("DecodeName: %v", err)
	}

	if !name.Equal(decoded) {
		t.Fatalf("expected roundtrip equality; got %v", decoded.Parts())
	}
}

func TestNameUnsupportedEncodingsFail(t *testing.T) {
	name := ir.NameFromParts([]string{"x"})

	if _, err := EncodeName(Options{NameEncoding: NameAsString}, name); err == nil {
		t.Fatal(expectedError)
	}
	if _, err := EncodeName(Options{NameEncoding: NameAsURL}, name); err == nil {
		t.Fatal(expectedError)
	}
}
