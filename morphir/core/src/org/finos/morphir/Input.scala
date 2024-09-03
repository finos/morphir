package org.finos.morphir

trait GenericInput:
  type Contents
  final lazy val chars: Array[Char] = text.toCharArray()
  def path: GenericPath
  def contents: Contents
  def text: String

sealed trait Input extends GenericInput

object Input:
  // case object NotAvailable extends Input {
  //   type Contents = Unit
  //   val path:GenericPath = new GenericPath {

  //     override def name: String = "nopath"

  //     override def suffix: Option[String] = None

  //     override def fragment: Option[String] = None

  //     override protected def copyWith(basename: String, suffix: Option[String], fragment: Option[String]): Self =

  //     override def /(path: RelativePath): Self = ???

  //   }
  //   def contents:Contents = ()
  //   def text:String = ""
  // }
  final case class VirtualFile(path: GenericPath, contents: VirtualFile#Contents) extends Input:
    type Contents = String
    inline final def text = contents

  final case class NonExistentFile()
