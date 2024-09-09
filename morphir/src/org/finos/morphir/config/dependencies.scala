package org.finos.morphir.config
import metaconfig.*

opaque type Dependency = String
object Dependency:
  given confEncoder: ConfEncoder[Dependency] = ConfEncoder.StringEncoder.contramap(_.value)
  given confDecoder: ConfDecoder[Dependency] = ConfDecoder.stringConfDecoder.map(Dependency(_))

  def apply(value: String): Dependency            = value
  extension (value: Dependency) def value: String = value

final case class Dependencies(items: IndexedSeq[Dependency] = IndexedSeq.empty)
object Dependencies:
  val empty: Dependencies                      = Dependencies()
  given confEncoder: ConfEncoder[Dependencies] = ConfEncoder[IndexedSeq[Dependency]].contramap(_.items)
  given confDecoder: ConfDecoder[Dependencies] = ConfDecoder[IndexedSeq[Dependency]].map(Dependencies(_))
