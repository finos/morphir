package morphir.sdk

case class StatefulApp[K, C, S, E](businessLogic: (K, Option[S], C) => (K, Option[S], E))
