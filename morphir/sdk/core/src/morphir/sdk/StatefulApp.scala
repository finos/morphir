package morphir.sdk

import morphir.sdk.Maybe.Maybe

object StatefulApp {

  case class StatefulApp[K, C, S, E](logic: Maybe[S] => C => (Maybe[S], E))

}
