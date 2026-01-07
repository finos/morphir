package bdd

import (
	"context"
	"testing"

	"github.com/cucumber/godog"
	"github.com/finos/morphir/tests/bdd/features"
	"github.com/finos/morphir/tests/bdd/steps"
	"github.com/finos/morphir/tests/bdd/testdata"
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

				// Cleanup workspace test context if present
				if wtc, getErr := steps.GetWorkspaceTestContext(ctx); getErr == nil && wtc != nil {
					if cleanupErr := wtc.Cleanup(); cleanupErr != nil && err == nil {
						err = cleanupErr
					}
				}

				// Cleanup example test context if present
				if etc, getErr := steps.GetExampleTestContext(ctx); getErr == nil && etc != nil {
					if cleanupErr := etc.Cleanup(); cleanupErr != nil && err == nil {
						err = cleanupErr
					}
				}

				return ctx, err
			})

			// Register all step definitions
			steps.RegisterCommonSteps(sc)
			steps.RegisterDistributionSteps(sc)
			steps.RegisterTypeSteps(sc)
			steps.RegisterConfigSteps(sc)
			steps.RegisterWorkspaceSteps(sc)
			steps.RegisterExampleSteps(sc)
			steps.RegisterCLISteps(sc)
		},
		Options: &godog.Options{
			Format:   "pretty",
			Paths:    []string{"."},
			FS:       features.Features,
			TestingT: t,
			Strict:   true,
			Tags:     "~@pending", // Skip scenarios tagged with @pending
		},
	}

	if suite.Run() != 0 {
		t.Fatal("non-zero status returned, failed to run feature tests")
	}
}
