package morphir.classic.ir

import kyo.Chunk

import scala.util.matching.Regex


/**
  * Classic Path: list of classic Names. API aligned with morphir-elm Morphir.IR.Path.
  */
final case class Path(names: Chunk[Name]):
  self =>

  def toList: List[Name] =
    names.toSeq.toList

  /** Render path with custom name formatter and separator (morphir-elm toString). */
  def format(nameToString: Name => String, sep: String): String =
    toList.map(nameToString).mkString(sep)

  /** Canonical string: names joined by /, each in hyphen-joined form (classic has no acronym parens). */
  def toCanonicalString: String =
    toList.map(_.toCanonicalString).mkString("/")

  /** Is the given prefix a prefix of this path? Empty prefix is prefix of any path. */
  def isPrefixOf(prefix: Path): Boolean =
    Path.isPrefixOf(this, prefix)

  override def toString: String =
    format(_.toTitleCase, ".")
end Path

object Path:

  def fromList(names: List[Name]): Path =
    Path(Chunk(names*))

  /** Parse string; splits on non-word chars (except spaces), each segment with Name.fromString (classic). */
  def fromString(string: String): Path =
    val separatorRegex: Regex = """[^\w\s]+""".r
    val segments = separatorRegex.split(string).toList.map(_.trim).filter(_.nonEmpty)
    fromList(segments.map(Name.fromString))

  /** Is prefix a prefix of path? Empty prefix is prefix of any path. */
  def isPrefixOf(path: Path, prefix: Path): Boolean =
    (prefix.toList, path.toList) match
      case (Nil, _) => true
      case (_, Nil) => false
      case (ph :: pt, pathH :: pathT) =>
        if namesEqual(ph, pathH) then isPrefixOf(Path.fromList(pathT), Path.fromList(pt))
        else false

  private def namesEqual(a: Name, b: Name): Boolean =
    a.toList == b.toList
