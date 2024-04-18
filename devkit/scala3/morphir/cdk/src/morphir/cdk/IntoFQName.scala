package morphir.cdk

trait IntoFQName[-A]:
  extension (a: A) def intoFQName: FQName

object IntoFQName:
  def apply[A](using intoFQName: IntoFQName[A]): IntoFQName[A] = intoFQName
