package org.finos.morphir.build.elm

import org.finos.morphir.build._
import mill._
import mill.scalalib._
import mill.api.PathRef
import os.RelPath
import org.finos.morphir.build.elm
import org.finos.morphir.build.elm.api._

trait ElmModule extends Module {
    def compile = T {
        val projType = elmProjectType()
        val results = projType match {
            case Some(ElmProjectType.Package) => 
                elmDocTask(skip = false)()
            case target => 
                elmMakeTask(true)()
        }
        results
    }

    def elmSources = T.sources{ elmSourcesFromProject() }

    def elmSourcesFromProject = T{ 
        val elmJsonFolder = elmJsonDir()
        elmProject()        
        .map(_.sourceDirectories.map{p => 
            val path = os.FilePath(p)
            val nioPath = path.toNIO
            if(nioPath.isAbsolute) {
                PathRef(os.Path(nioPath))
            } else {
                PathRef(elmJsonFolder / os.RelPath(nioPath))
            }
        }).getOrElse(Seq(PathRef(millSourcePath / "src"))) 
    }

    def allElmSourceFiles = T{ gatherAllElmSourceFiles() }
    def elmDocCommandLine = T.task{     
        val outputPath = T.ctx().dest / "docs.json"
        //def sourceFiles = allElmSourceFiles().map(_.path.toString) 
        CommandLine.Elm
            .withSubcommandArgs("make")              
            .withAfterArgs(s"--docs=$outputPath")
            //.appendArgs(sourceFiles)
    }

    def elmDocTask(skip:Boolean) = T.task  {
        if(skip) {
            Seq.empty[PathRef]
        } else {
            val outputPath = T.ctx().dest / "docs.json"
            val cmd = elmDocCommandLine().toSeq
            os.proc(cmd).call(cwd = elmJsonDir(), stdout = os.Inherit, stderr = os.Inherit)
            
            Seq(PathRef(outputPath))
        }
    }

    def elmDoc(outputPath:String ) = {
        val outputPathResolved = os.Path(outputPath)
        T.command {            
            val cmd = elmDocCommandLine().toSeq
            os.proc(cmd).call(cwd = elmJsonDir(), stdout = os.Inherit, stderr = os.Inherit)
            outputPath
        }
    }

    def elmJsonPath = T{ PathRef(millSourcePath / "elm.json") }
    final def elmJsonDir = T{ elmJsonPath().path / os.up }

    def elmProject: T[Option[ElmProject]] = T{        
        if(os.exists(elmJsonPath().path)) {
            val jsonString = os.read(elmJsonPath().path)
            val json = ujson.read(jsonString)
            val projectType = ElmProjectType.fromString(json("type").str)
            val project = projectType match {
                case ElmProjectType.Application => ElmPickler.read[ElmProject.ElmApplication](json)
                case ElmProjectType.Package => ElmPickler.read[ElmProject.ElmPackage](json)
            }
            Some(project)
        } else {
            None
        }
    }

    def elmProjectType = T{ elmProject().map(_.projectType) }

    def elmEntryPoints:T[Option[Seq[PathRef]]] = None

    def elmMakeSourceFiles = T.sources{
        elmEntryPoints() match {
            case Some(entryPoints) => entryPoints
            case None => 
                elmProjectType() match {
                    case Some(ElmProjectType.Package) => exposedModuleSourceFiles()
                    case _ => allElmSourceFiles()
                }
        }
    }

    def targetDir = T{ T.ctx().dest }

    def elmMakeOutputFile = T.source{ targetDir() / "elm.js" }

    def elmMakeCommandLine = T{
        val elmJsonFolder = elmJsonDir()
        val sources = elmMakeSourceFiles().map(_.path.relativeTo(elmJsonFolder).toString)
        val output = elmMakeOutputFile().path.toString
        CommandLine.Elm
            .withSubcommandArgs("make")
            .appendArgs(sources)
            .appendAfterArgs(Seq("--output", output))
    }

    def elmMakeTask(skip:Boolean) = T.task {
        if(skip) {
            Seq()
        } else {
            val cmd = elmMakeCommandLine()
            os.proc(cmd.toSeq).call(cwd = elmJsonDir())
            Seq(elmMakeOutputFile())
        }        
    }

    def elmMake(
        debug:mainargs.Flag, 
        optimize:mainargs.Flag,   
        @mainargs.arg(doc = "Specify the name of the resulting JS file.")                     
        output:Option[String],
        @mainargs.arg(doc="You can say --report=json to get error messages as JSON.")
        report:Option[String],
        @mainargs.arg(doc = "Generate a JSON file of documentation for a package.")
        docs:Option[String],      
        elmFiles:mainargs.Leftover[String]  
    ) = T.command {
        T.log.info("Running elm make command:")
        T.log.info(s"Debug: $debug")
        T.log.info(s"Optimize: $optimize")
        T.log.info(s"Output: $output")
        T.log.info(s"Report: $report")
        T.log.info(s"Docs: $docs")
        T.log.info(s"Elm Files: ${elmFiles.value.mkString(",")}")
        //elmMakeTask(false)()
    }
    
    def exposedModules = T {
        elmProject().flatMap { proj =>
            proj match {
                case p: ElmProject.ElmPackage => Some(p.exposedModules)
                case _ => None
            }
        }
    }

    def exposedModuleSourceFiles = T {
        elmProjectType().map{
            case ElmProjectType.Package => elmSources()
            case ElmProjectType.Application => allElmSourceFiles()
        }
        
        val modules = exposedModules().getOrElse(Nil)
        val srcDir = elmJsonDir() / "src"
        val expectedPaths = Set.from(modules.map(_.toPath(srcDir)))
        
        gatherAllElmSourceFiles().collect { 
            case pathRef if expectedPaths.contains(pathRef.path) => pathRef
        }
    }

    private def gatherAllElmSourceFiles = T.task {
        Lib.findSourceFiles(elmSources(), Seq("elm")).map(PathRef(_))
    }    
}