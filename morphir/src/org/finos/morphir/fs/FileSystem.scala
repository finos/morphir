package org.finos.morphir.fs
import kyo.*
import java.net.URI

trait FileSystem:
  /** Parse a path from a String.
    * @param path
    *   \- the string path to be converted to Path
    * @return
    */
  def parsePath(path: String): Either[FileSystem.PathParseError, Path]
  def parsePath(uri: URI): Either[FileSystem.PathParseError, Path]
  def parsePathUnsafe(path: String): Path = parsePath(path).fold(throw _, identity)
  def pathSeparator: String

object FileSystem:
  type PathParseError = UnsupportedOperationException | IllegalArgumentException
