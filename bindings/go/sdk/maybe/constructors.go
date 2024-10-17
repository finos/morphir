package maybe

import "reflect"

func Nothing[T any]() Maybe[T] {
	return Maybe[T]{empty: true}
}

func Just[T any](value T) Maybe[T] {
	return Maybe[T]{value: value}
}

// New creates a new Maybe and performs emptiness/nil-ness checks of the given value.
func New[T any](value T) Maybe[T] {
	if isNotNil(value) {
		return Just(value)
	}
	return Nothing[T]()
}

func isNotNil[T any](value T) bool {
	v := reflect.ValueOf(value)
	k := v.Kind()
	if k == reflect.Invalid {
		return false
	}
	switch k {
	case reflect.Slice, reflect.Map:
		if v.IsNil() || v.Len() == 0 {
			return false
		}
	case reflect.Chan, reflect.Func, reflect.Interface, reflect.Pointer, reflect.UnsafePointer:
		if v.IsNil() {
			return false
		}
	default:
		return true
	}
	return true
}
