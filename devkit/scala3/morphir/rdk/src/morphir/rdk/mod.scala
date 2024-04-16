package morphir.rdk
import morphir.cdk.*
import morphir.runtime.internal.*
import izumi.reflect.*

extension [Self: IntoName](self: Self)
  def intoVariable[V](using tag: Tag[V]): Symbol[V] =
    Symbol.Variable(self.intoName, tag)
