package rule

import (
	"github.com/finos/morphir/corelib/go/morphir/sdk/basics"
	"github.com/finos/morphir/corelib/go/morphir/sdk/maybe"
)

type Rule[A any, B any] func(A) maybe.Maybe[B]

func Any[A any](value A) basics.Bool {
	return basics.True
}
