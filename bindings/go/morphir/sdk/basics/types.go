package basics

type Int int64

type Float float64

type Number interface {
	Int | Float
}
