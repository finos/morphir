package basics

type Int int64

type Bool bool

type Float float64

type Number interface {
	Int | Float
}
