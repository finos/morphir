package org.finos.morphir
package vfs
import kyo.*
import java.net.URI

trait VFileSystem:
    /** 
      * Parse a path from a String.
      * @param path - the string path to be converted to Path
      * @return
      */
    def parsePath(path:String):Either[VFileSystem.PathParseError, vfs.Path]
    def parsePath(uri:URI):Either[VFileSystem.PathParseError, vfs.Path]
    def parsePathUnsafe(path:String):vfs.Path = parsePath(path).fold(throw _, identity)
    def pathSeparator:String 


object VFileSystem:
    type PathParseError = UnsupportedOperationException | IllegalArgumentException