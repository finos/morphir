package org.finos.morphir.lang.elm.projectsystem

enum ElmProject:
  self =>
  case ElmPackage
  case ElmApplication
  
  def kind: ElmProject.Kind = self match
    case ElmPackage => ElmProject.Kind.Package
    case ElmApplication => ElmProject.Kind.Application

object ElmProject:
  enum Kind:
    case Package, Application