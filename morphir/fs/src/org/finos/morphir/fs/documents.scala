package org.finos.morphir.fs

trait Navigatable {
  def path: Path

  /** The local name of this navigatable.
    */
  lazy val name: String = path.name
}
