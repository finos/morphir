package org.finos.morphir.lang.elm
import kyo.{Path as KyoPath, *}
import org.finos.morphir.*

trait ElmProjectLoaderPlatformSpecific extends ElmProjectLoader:
  protected def loadProjectPlatformSpecific(path: GenericPath): ElmProject < IO & Abort[String | Exception] =
    path match
      case path: FilePath    => 
        val kyoPath = kyo.Path(path.)
      case path: VirtualPath => ???
      case _                 => Abort.fail("Unsupported path type")

  
  private def loadProjectFromPath(path: KyoPath): ElmProject < IO & Abort[String | Exception] = ???