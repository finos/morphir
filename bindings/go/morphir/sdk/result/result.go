package result

type Result[Error any, Value any] struct {
	err *Error
	ok  *Value
}

func IsOk[Error any, Value any](r Result[Error, Value]) bool {
	return r.ok != nil
}
