package org.finos.morphir.lang.elm.frontend.playground
import mainargs.{main,arg, ParserForMethods,Flag}
import org.treesitter.* 

object TryTreeSitter:
    @main 
    def run() =
        val parser = new TSParser()
        val elm = new TreeSitterElm()
        parser.setLanguage(elm)
        val tree = parser.parseString(null, "module Main exposing (..)")
        val rootNode = tree.getRootNode()
        pprint.pprintln(rootNode)
        val start = rootNode.getStartPoint()
        val end = rootNode.getEndPoint()
        pprint.pprintln(s"Start: $start, End: $end")        
        //val cursor = new TSTreeCursor(rootNode)
        


    
    def main (args: Array[String]): Unit = ParserForMethods(this).runOrExit(args)
end TryTreeSitter