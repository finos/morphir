package morphir.ir

/** Generated based on IR.Documented
*/
object Documented{

  final case class Documented[A](
    doc: morphir.sdk.String.String,
    value: A
  ){}
  
  def map[A, B](
    f: A => B
  )(
    d: morphir.ir.Documented.Documented[A]
  ): morphir.ir.Documented.Documented[B] =
    (morphir.ir.Documented.Documented(
      d.doc,
      f(d.value)
    ) : morphir.ir.Documented.Documented[B])

}