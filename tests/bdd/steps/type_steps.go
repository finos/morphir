package steps

import (
	"context"
	"fmt"

	"github.com/cucumber/godog"
	ir "github.com/finos/morphir/pkg/models/ir"
)

// RegisterTypeSteps registers step definitions for type features.
func RegisterTypeSteps(sc *godog.ScenarioContext) {
	sc.Step(`^I decode as type format version (\d+)$`, iDecodeAsTypeFormatVersion)
	sc.Step(`^the type should be a "([^"]*)"$`, theTypeShouldBeA)
	sc.Step(`^the type kind should be "([^"]*)"$`, theTypeKindShouldBe)
}

func iDecodeAsTypeFormatVersion(ctx context.Context, version int) (context.Context, error) {
	tc, err := GetTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	if err := tc.SetFormatVersion(version); err != nil {
		return ctx, err
	}

	if err := tc.DecodeType(); err != nil {
		return ctx, err
	}

	return ctx, nil
}

func theTypeShouldBeA(ctx context.Context, expectedKind string) error {
	tc, err := GetTestContext(ctx)
	if err != nil {
		return err
	}

	if tc.DecodedType == nil {
		if tc.LastError != nil {
			return fmt.Errorf("type not decoded due to error: %v", tc.LastError)
		}
		return fmt.Errorf("no type decoded")
	}

	actualKind := getTypeKind(tc.DecodedType)
	if actualKind != expectedKind {
		return fmt.Errorf("expected type kind %q, got %q", expectedKind, actualKind)
	}

	return nil
}

func theTypeKindShouldBe(ctx context.Context, expectedKind string) error {
	return theTypeShouldBeA(ctx, expectedKind)
}

// getTypeKind returns the kind name of a Type.
func getTypeKind(t ir.Type[ir.Unit]) string {
	switch t.(type) {
	case ir.TypeVariable[ir.Unit]:
		return "Variable"
	case ir.TypeReference[ir.Unit]:
		return "Reference"
	case ir.TypeTuple[ir.Unit]:
		return "Tuple"
	case ir.TypeRecord[ir.Unit]:
		return "Record"
	case ir.TypeExtensibleRecord[ir.Unit]:
		return "ExtensibleRecord"
	case ir.TypeFunction[ir.Unit]:
		return "Function"
	case ir.TypeUnit[ir.Unit]:
		return "Unit"
	default:
		return fmt.Sprintf("%T", t)
	}
}
