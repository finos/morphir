package bdd

import (
	"context"
	"testing"

	"github.com/cucumber/godog"
	"github.com/finos/morphir-go/tests/bdd/features"
	"github.com/finos/morphir-go/tests/bdd/steps"
	"github.com/finos/morphir-go/tests/bdd/testdata"
)

func TestFeatures(t *testing.T) {
	suite := godog.TestSuite{
		Name: "morphir-ir-bdd",
		ScenarioInitializer: func(sc *godog.ScenarioContext) {
			// Create test context with embedded fixtures
			tc := steps.NewTestContext(testdata.Fixtures)

			// Set up before/after hooks
			sc.Before(func(ctx context.Context, sc *godog.Scenario) (context.Context, error) {
				tc.Reset()
				return steps.WithTestContext(ctx, tc), nil
			})

			// Register all step definitions
			steps.RegisterCommonSteps(sc)
			steps.RegisterDistributionSteps(sc)
			steps.RegisterTypeSteps(sc)
		},
		Options: &godog.Options{
			Format:   "pretty",
			Paths:    []string{"."},
			FS:       features.Features,
			TestingT: t,
			Strict:   true,
		},
	}

	if suite.Run() != 0 {
		t.Fatal("non-zero status returned, failed to run feature tests")
	}
}
