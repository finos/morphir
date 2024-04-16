package morphir.cdk

trait IntoPath[-A]:
  extension (a: A) def intoPath: Path

object IntoPath:
  def apply[A](using intoPath: IntoPath[A]): IntoPath[A] = intoPath
