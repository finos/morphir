package list

import (
	"github.com/finos/morphir/runtime/libs/go/morphir/ir/tuple"
	"github.com/finos/morphir/runtime/libs/go/morphir/sdk/basics"
	maybe2 "github.com/finos/morphir/runtime/libs/go/morphir/sdk/maybe"
)

// Drop the first `n` members of a list.
func Drop[T any](n basics.Int) func(ls List[T]) List[T] {
	return func(ls List[T]) List[T] {
		if n > basics.Int(len(ls)) {
			return []T{}
		}
		return ls[n:]
	}
}

func Head[T any](ls List[T]) maybe2.Maybe[T] {
	if len(ls) == 0 {
		return maybe2.Nothing[T]()
	}
	return maybe2.Just(ls[0])
}

func HeadAndTail[T any](ls List[T]) (head T, tail List[T], ok bool) {
	if len(ls) == 0 {
		return head, tail, false
	}
	return ls[0], ls[1:], true
}

func IsEmpty[T any](ls List[T]) basics.Bool {
	return len(ls) == 0
}

// Partition a list based on some test. The first list contains all values that satisfy the test,
// and the second list contains all values that do not.
func Partition[T any](f func(T) basics.Bool) func(List[T]) (List[T], List[T]) {
	return func(ls List[T]) (List[T], List[T]) {
		var left, right List[T]
		for _, v := range ls {
			if f(v) {
				left = append(left, v)
			} else {
				right = append(right, v)
			}
		}
		return left, right
	}
}

// Tail extract the tail of a list, which is the list without the first element.
func Tail[T any](ls List[T]) maybe2.Maybe[List[T]] {
	if len(ls) == 0 {
		return maybe2.Nothing[List[T]]()
	}
	return maybe2.Just(ls[1:])
}

// Take the first `n` members of a list.
func Take[T any](n basics.Int) func(ls List[T]) List[T] {
	return func(ls List[T]) List[T] {
		if n > basics.Int(len(ls)) {
			return ls
		}
		return ls[:n]
	}
}

func Unzip[T any, U any](ls List[tuple.Tuple2[T, U]]) (List[T], List[U]) {
	var ts []T
	var us []U
	for _, pair := range ls {
		ts = append(ts, pair.First())
		us = append(us, pair.Second())
	}
	return ts, us
}
