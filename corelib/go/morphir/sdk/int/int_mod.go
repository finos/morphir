package int

import (
	"github.com/finos/morphir/corelib/go/morphir/sdk/basics"
	"github.com/finos/morphir/corelib/go/morphir/sdk/maybe"
)

type Int8 int8

type Int16 int16

type Int32 int32

type Int64 int64

func FromInt8[I8 ~int8](i I8) basics.Int {
	return basics.Int(int64(i))
}

func FromInt16[I16 ~int16](i I16) basics.Int {
	return basics.Int(int64(i))
}

func FromInt32[I32 ~int32](i I32) basics.Int {
	return basics.Int(int64(i))
}

func FromInt64[I64 ~int64](i I64) basics.Int {
	return basics.Int(i)
}

func ToInt8(i basics.Int) maybe.Maybe[Int8] {
	if i < -128 || i > 127 {
		return maybe.Nothing[Int8]()
	}
	return maybe.Just(Int8(i))
}

func ToInt16(i basics.Int) maybe.Maybe[Int16] {
	if i < -32768 || i > 32767 {
		return maybe.Nothing[Int16]()
	}
	return maybe.Just(Int16(i))
}

func ToInt32(i basics.Int) maybe.Maybe[Int32] {
	if i < -2147483648 || i > 2147483647 {
		return maybe.Nothing[Int32]()
	}
	return maybe.Just(Int32(i))
}

func ToInt64(i basics.Int) maybe.Maybe[Int64] {
	if i < -9223372036854775808 || i > 9223372036854775807 {
		return maybe.Nothing[Int64]()
	}
	return maybe.Just(Int64(i))
}
