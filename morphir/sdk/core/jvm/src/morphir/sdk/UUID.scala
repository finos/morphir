package morphir.sdk

import memeid4s.{ UUID => MUUID }

import java.util.{ UUID => JUUID }
import scala.util.Try

object UUID {
  type UUID = MUUID

  trait Error                                                      extends Throwable
  case class WrongFormat(message: String, cause: Throwable)        extends Error
  case class WrongLength(message: String, cause: Throwable)        extends Error
  case class UnsupportedVariant(message: String, cause: Throwable) extends Error
  case class IsNil(message: String, cause: Throwable)              extends Error
  case class NoVersion(message: String, cause: Throwable)          extends Error

  val Nil: UUID = MUUID.Nil

  val dnsNamespace  = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
  val urlNamespace  = "6ba7b811-9dad-11d1-80b4-00c04fd430c8"
  val oidNamespace  = "6ba7b812-9dad-11d1-80b4-00c04fd430c8"
  val x500Namespace = "6ba7b814-9dad-11d1-80b4-00c04fd430c8"

  def compare(uuid1: UUID, uuid2: UUID): Int = uuid1.compareTo(uuid2)
  def forName(s: String, uuid: UUID): UUID   = MUUID.V5(uuid, s)

  /** Creates a valid [[UUID]] from two [[_root_.scala.Long Long]] values representing the most/least significant bits.
    *
    * @param msb
    *   Most significant bit in [[_root_.scala.Long Long]] representation
    * @param lsb
    *   Least significant bit in [[_root_.scala.Long Long]] representation
    * @return
    *   a new [[UUID]] constructed from msb and lsb
    */
  @inline def from(msb: Long, lsb: Long): UUID = MUUID.from(msb, lsb)

  /** Creates a [[UUID UUID]] from the [[java.util.UUID#toString string standard representation]] wrapped in a
    * [[_root_.scala.util.Right Right]].
    *
    * Returns [[_root_.scala.util.Left Left]] with the error in case the string doesn't follow the string standard
    * representation.
    *
    * @param s
    *   String for the [[java.util.UUID UUID]] to be generated as an [[UUID]]
    * @return
    *   [[_root_.scala.util.Either Either]] with [[_root_.scala.util.Left Left]] with the error in case the string
    *   doesn't follow the string standard representation or [[_root_.scala.util.Right Right]] with the [[UUID UUID]]
    *   representation.
    */
  @inline def parse(s: String): Either[Error, UUID] = {
    val result = MUUID.from(s)
    result match {
      case Left(e)  => Left(WrongFormat(e.getMessage, e.getCause))
      case Right(u) => Right(u)
    }
  }

  /** Similar to `parse` but returns an `Option` instead of an `Either`.
    * @param s
    * @return
    */
  @inline def fromString(s: String): Option[UUID] = MUUID.from(s).toOption

  /** Creates a valid [[UUID]] from a [[JUUID]].
    *
    * @param juuid
    *   the {@link java.util.UUID}
    * @return
    *   a valid {@link UUID} created from a {@link java.util.UUID}
    */
  @inline def fromUUID(juuid: JUUID): UUID = MUUID.fromUUID(juuid)

  /** Returns true if the given string represents the Nil UUID
    *
    * @param s
    *   the string to check
    * @return
    *   boolean indicating if the string represents the Nil UUID
    */
  @inline def isNil(s: String): Boolean = Nil.toString.equals(s)

  @inline def toString(uuid: UUID): String       = uuid.toString
  @inline def version(uuid: UUID): Int           = uuid.version
  @inline def nilString(): String                = Nil.toString
  @inline def isNilString(uuid: String): Boolean = Nil.toString.equals(uuid)
}
