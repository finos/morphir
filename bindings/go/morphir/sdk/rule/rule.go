package rule

import (
	"github.com/finos/morphir/bindings/go/morphir/sdk/basics"
	"github.com/finos/morphir/bindings/go/morphir/sdk/maybe"
)

type Rule[A any, B any] func(A) maybe.Maybe[B]

func Any[A any](value A) basics.Bool {
	return basics.True
}
