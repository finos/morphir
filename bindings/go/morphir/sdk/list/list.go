package list

import (
	"github.com/finos/morphir/bindings/go/morphir/sdk/basics"
)

type List[T any] []T

func Append[T any](l1 List[T], l2 List[T]) List[T] {
	return append(l1, l2...)
}

func (ls List[T]) IsEmpty() basics.Bool {
	return IsEmpty(ls)
}
