package list

import (
	"github.com/finos/morphir/bindings/go/morphir/sdk/basics"
)

func Nil[T any]() List[T] {
	return []T{}
}

func Singleton[T any](value T) List[T] {
	return []T{value}
}

func Repeat[T any](count basics.Int) func(value T) List[T] {
	return func(value T) List[T] {
		ls := make([]T, count)
		for i := range ls {
			ls[i] = value
		}
		return ls
	}
}

func FromSlice[T any](slice []T) List[T] {
	return slice
}
