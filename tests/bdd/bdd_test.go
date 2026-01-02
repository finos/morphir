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

			// Create config test context
			ctc := steps.NewConfigTestContext()

			// Set up before/after hooks
			sc.Before(func(ctx context.Context, sc *godog.Scenario) (context.Context, error) {
				tc.Reset()
				ctc.Reset()
				ctx = steps.WithTestContext(ctx, tc)
				return ctx, nil
			})

			sc.After(func(ctx context.Context, sc *godog.Scenario, err error) (context.Context, error) {
				// Cleanup config test context
				if cleanupErr := ctc.Cleanup(); cleanupErr != nil && err == nil {
					err = cleanupErr
				}
				return ctx, err
			})

			// Register all step definitions
			steps.RegisterCommonSteps(sc)
			steps.RegisterDistributionSteps(sc)
			steps.RegisterTypeSteps(sc)
			steps.RegisterConfigSteps(sc)
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
