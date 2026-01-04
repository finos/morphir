package steps

import (
	"context"
	"fmt"
	"strings"

	"github.com/cucumber/godog"
)

// RegisterCommonSteps registers common step definitions used across features.
func RegisterCommonSteps(sc *godog.ScenarioContext) {
	sc.Step(`^I have the fixture "([^"]*)"$`, iHaveTheFixture)
	sc.Step(`^the decoding should succeed$`, theDecodingShouldSucceed)
	sc.Step(`^the decoding should fail$`, theDecodingShouldFail)
	sc.Step(`^the decoding should fail with error containing "([^"]*)"$`, theDecodingShouldFailWithErrorContaining)
	sc.Step(`^the encoding should succeed$`, theEncodingShouldSucceed)
}

func iHaveTheFixture(ctx context.Context, fixturePath string) (context.Context, error) {
	tc, err := GetTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	if err := tc.LoadFixture(fixturePath); err != nil {
		return ctx, err
	}

	return ctx, nil
}

func theDecodingShouldSucceed(ctx context.Context) error {
	tc, err := GetTestContext(ctx)
	if err != nil {
		return err
	}

	if tc.LastError != nil {
		return fmt.Errorf("expected decoding to succeed, but got error: %v", tc.LastError)
	}

	return nil
}

func theDecodingShouldFail(ctx context.Context) error {
	tc, err := GetTestContext(ctx)
	if err != nil {
		return err
	}

	if tc.LastError == nil {
		return fmt.Errorf("expected decoding to fail, but it succeeded")
	}

	return nil
}

func theDecodingShouldFailWithErrorContaining(ctx context.Context, expected string) error {
	tc, err := GetTestContext(ctx)
	if err != nil {
		return err
	}

	if tc.LastError == nil {
		return fmt.Errorf("expected decoding to fail with error containing %q, but it succeeded", expected)
	}

	if !strings.Contains(tc.LastError.Error(), expected) {
		return fmt.Errorf("expected error to contain %q, but got: %v", expected, tc.LastError)
	}

	return nil
}

func theEncodingShouldSucceed(ctx context.Context) error {
	tc, err := GetTestContext(ctx)
	if err != nil {
		return err
	}

	if tc.LastError != nil {
		return fmt.Errorf("expected encoding to succeed, but got error: %v", tc.LastError)
	}

	if tc.EncodedJSON == nil {
		return fmt.Errorf("expected encoded JSON to be present")
	}

	return nil
}
