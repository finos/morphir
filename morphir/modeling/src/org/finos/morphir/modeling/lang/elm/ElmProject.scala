package org.finos.morphir.modeling.lang.elm

import io.github.iltotore.iron.*
import io.github.iltotore.iron.constraint.string.*
import org.finos.morphir.constraint.string.ValidElmPackageName

enum ElmProject:
  self =>
  case ElmPackage(name:ElmPackageName)
  case ElmApplication(sourceDirectories:Seq[String])
  
  def kind: ElmProject.Kind = self match
    case _:ElmPackage => ElmProject.Kind.Package
    case _:ElmApplication => ElmProject.Kind.Application

object ElmProject:
  enum Kind:
    case Package, Application

opaque type ElmPackageName <: String :| ValidElmPackageName = String :| ValidElmPackageName 
object ElmPackageName extends RefinedTypeOps[String, ValidElmPackageName, ElmPackageName]
