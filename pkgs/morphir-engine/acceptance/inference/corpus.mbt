///|
/// Monomorphic Scheme programs. Each one must fill to concrete types, because the MoonBit generator has no
/// specialization. Pure generics, such as `(define (id x) x)`, are not in the corpus. A definition does not refer
/// to another top-level definition, because the frontend writes that reference as a local variable
/// (follow-up `morphir-ukvn.5.22.8`).
let corpus : Array[(String, String)] = [
  (
    "arithmetic", "(define (inc x) (+ x 1))\n(define (scale x) (* x 2))\n(define (half x) (/ x 2.0))\n(define answer (+ 41 1))",
  ),
  (
    "strings", "(define (greet name) (string-append \"Hello, \" name))\n(define greeting (string-append \"Hello, \" \"Morphir\"))",
  ),
  (
    "lets", "(define (sum-sq a b) (let ((x (* a a)) (y (* b b))) (+ (+ x y) 0)))\n(define (chain a) (let* ((b (+ a 1)) (c (* b 2))) c))",
  ),
  ("conditions", "(define (clamp x) (if (< x 0) 0 (if (> x 100) 100 x)))"),
  (
    "recursion", "(define (fact n) (letrec ((go (lambda (k) (if (= k 0) 1 (* k (go (- k 1))))))) (go n)))\n(define (count n) (letrec ((go (lambda (k acc) (if (= k 0) acc (go (- k 1) (+ acc 1)))))) (go n 0)))",
  ),
  (
    "lambdas", "(define (apply-twice x) (let ((f (lambda (y) (+ y 1)))) (f (f x))))",
  ),
  ("lists", "(define (bump xs) (morphir/SDK:list#map (lambda (x) (+ x 1)) xs))"),
]

///|
/// Corpus programs that the MoonBit generator does not support yet, with the error code it must raise. Elm checks
/// them; `moon build` does not. Follow-up: `morphir-ukvn.5.22.10` (LetRecursion).
let moonbit_gaps : Map[String, String] = {
  "recursion": "moonbit.unsupported_expression",
}
