package rule

import (
	basics2 "github.com/finos/morphir/runtime/libs/go/morphir/sdk/basics"
	"github.com/finos/morphir/runtime/libs/go/morphir/sdk/maybe"
)

type Rule[A any, B any] func(A) maybe.Maybe[B]

func Any[A any](value A) basics2.Bool {
	return basics2.True
}
