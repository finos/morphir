package morphir.classic.ir
import kyo.Chunk
import morphir.classic.ir.{Literal as Lit}

sealed trait Value[+TA, +VA] extends Product with Serializable
object Value:
    final case class Literal[VA](attributes: VA, literal: Lit) extends Value[Nothing, VA]
    final case class Constructor[VA](attributes: VA, fqname: FQName) extends Value[Nothing, VA]
    final case class Tuple[TA,VA](attributes: VA, elements: Chunk[Value[TA, VA]]) extends Value[TA, VA]
    final case class Unit[VA](attributes: VA) extends Value[Nothing, VA]