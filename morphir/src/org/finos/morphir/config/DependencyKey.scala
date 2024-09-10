package org.finos.morphir.config

import metaconfig.*

enum DependencyKey:
  case Package(text: String)
  case PackageUrl(text: String)

object DependencyKey
