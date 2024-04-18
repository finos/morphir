package morphir.rdk
import morphir.runtime.internal.*
import izumi.reflect.*
import morphir.cdk.IntoName

extension [Self: IntoName](self: Self)
  def intoVariable[V](using tag: Tag[V]): Symbol[V] =
    Symbol.Variable(self.intoName, tag)
