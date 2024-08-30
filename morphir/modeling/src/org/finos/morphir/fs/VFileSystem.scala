package org.finos.morphir.fs
import kyo.*
import java.net.URI

trait VFileSystem:
    /** 
      * Parse a path from a String.
      * @param path - the string path to be converted to Path
      * @return
      */
    def parsePath(path:String):Either[VFileSystem.PathParseError, Path]
    def parsePath(uri:URI):Either[VFileSystem.PathParseError, Path]
    def parsePathUnsafe(path:String):vfs.Path = parsePath(path).fold(throw _, identity)
    def pathSeparator:String 


object VFileSystem:
    type PathParseError = UnsupportedOperationException | IllegalArgumentException