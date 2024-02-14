#r "nuget: Fun.Build, 1.0.3"
#r "nuget: CliWrap, 3.6.4"
#r "nuget: FSharp.Data, 6.3.0"
#r "nuget: Ionide.KeepAChangelog, 0.1.8"
#r "nuget: Humanizer.Core, 2.14.1"

open System
open System.IO
open System.IO.Compression
open System.Xml.Linq
open System.Xml.XPath
open Fun.Build
open CliWrap
open CliWrap.Buffered
open FSharp.Data

let (</>) a b = Path.Combine(a, b)

let cleanFolders (input: string seq) =
    async {
        input
        |> Seq.iter (fun dir ->
            if Directory.Exists(dir) then
                Directory.Delete(dir, true))
    }

let pushPackage nupkg =
    async {
        let key = Environment.GetEnvironmentVariable("NUGET_KEY")
        let! result =
            Cli
                .Wrap("dotnet")
                .WithArguments($"nuget push {nupkg} --api-key {key} --source https://api.nuget.org/v3/index.json")
                .ExecuteAsync()
                .Task
            |> Async.AwaitTask
        return result.ExitCode
    }
    
let analysisReportsDir = "analysisreports"

let runGitCommand (arguments: string) =
    async {
        let! result =
            Cli
                .Wrap("git")
                .WithArguments(arguments)
                .WithWorkingDirectory(__SOURCE_DIRECTORY__)
                .ExecuteBufferedAsync()
                .Task
            |> Async.AwaitTask
        return result.ExitCode, result.StandardOutput, result.StandardError
    }

let runCmd file (arguments: string) =
    async {
        let! result = Cli.Wrap(file).WithArguments(arguments).ExecuteAsync().Task |> Async.AwaitTask
        return result.ExitCode
    }
    
let codeFilesDir = __SOURCE_DIRECTORY__ </> ".codefiles"
let morphirElmHash =
    let xDoc = XElement.Load(__SOURCE_DIRECTORY__ </> "morphir-dotnet" </> "Directory.Build.props")
    xDoc.XPathSelectElements("//MorphirElmCommitHash") |> Seq.head |> (fun xe -> xe.Value)
    
let updateFileRaw (file: FileInfo) =
    let lines = File.ReadAllLines file.FullName
    let updatedLines =
        lines
        |> Array.map (fun line ->
            if line.Contains("FSharp.Compiler") then
                line.Replace("FSharp.Compiler", "Fantomas.FCS")
            else
                line)
    File.WriteAllLines(file.FullName, updatedLines)
    
let downloadArchiveFromGitRepo owner projectName shaOrBranch extract =
    async {
        let downloadDir = codeFilesDir </> "downloads" </> owner </> projectName  </> shaOrBranch
        let targetDir = codeFilesDir </> owner </> projectName
        let fileName = $"{projectName}.zip"
        let file = FileInfo(downloadDir </> fileName)
        if file.Exists && file.Length <> 0 then
            return ()
        else
            file.Directory.Create()
            let fs = file.Create()
            
            
            let url = $"https://github.com/{owner}/{projectName}/archive/{shaOrBranch}.zip"
            let! response = Http.AsyncRequestStream(
                    url,
                    headers = [| "Content-Disposition", $"attachment; filename=\"{fileName}\"" |]
                )
            if response.StatusCode <> 200 then
                printfn $"Could not download %s{url}"
            do! Async.AwaitTask(response.ResponseStream.CopyToAsync(fs))
            fs.Close()
            if extract then    
                use zip = ZipFile.OpenRead(file.FullName)
                zip.ExtractToDirectory(FileInfo(targetDir).FullName)
            else
                ()
                
    }
    
let downloadMorphirElmFile commitHash relativePath =
    async {
        let file = FileInfo(codeFilesDir </> "morphir-elm" </> commitHash </> relativePath)
        if file.Exists && file.Length <> 0 then
            return ()
        else
            file.Directory.Create()
            use fs = file.Create()
            let fileName = Path.GetFileName(relativePath)
            let url =
                $"https://raw.githubusercontent.com/finos/morphir-elm/{commitHash}/{relativePath}"
            let! response =
                Http.AsyncRequestStream(
                    url,
                    headers = [| "Content-Disposition", $"attachment; filename=\"{fileName}\"" |]
                )
            if response.StatusCode <> 200 then
                printfn $"Could not download %s{relativePath}"
            do! Async.AwaitTask(response.ResponseStream.CopyToAsync(fs))
            fs.Close()
            //updateFileRaw file
    }
    

pipeline "Init" {
    workingDir __SOURCE_DIRECTORY__
    stage "Download morphir-elm files" {
        run (fun _ ->
            downloadArchiveFromGitRepo "finos" "morphir-elm" morphirElmHash true
            |> Async.Ignore)
    }
    runIfOnlySpecified
}

pipeline "CleanupCodeFiles" {
    workingDir __SOURCE_DIRECTORY__
    stage "Clean up code files" {
        run (fun _ -> cleanFolders [codeFilesDir])
    }
    runIfOnlySpecified
}

tryPrintPipelineCommandHelp ()