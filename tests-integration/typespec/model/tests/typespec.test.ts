// imports
import * as fs from "fs";
import * as util from "util"
import * as path from "path"


// process constants
const writeFile = util.promisify(fs.writeFile)
const rmdir = util.promisify(fs.rmSync)
const execa = require("execa")

// cadl model related paths
const projectDir = path.join("tests-integration","typespec", "model")
const generatedCadl = path.join(projectDir, "dist")
const morphirIR = path.join(projectDir,"morphir-ir.json")

// cli stuffs
const cli = require("../../../../cli/cli.js")
const makeCmdOpts = { typesOnly: false, output: projectDir }
const genCmdOpts = { target: "TypeSpec" }

// test
describe("Validating Generated TypeSpec", () => {
    test("Compiling TypeSpec", async () => {
        const opts = {recursive: true, force: true}

        // run make cmd
        const IR = await cli.make(projectDir, makeCmdOpts)

        // write IR
        await writeFile(morphirIR,JSON.stringify(IR))

        // run gen cmd
        await cli.gen(morphirIR, generatedCadl, genCmdOpts)

        // compile generated Cadl to look for errors
        const args = ['compile', path.join(generatedCadl,"TestModel.tsp")]
        const {stdout} = await execa('tsp', args)
        
        expect(stdout).toContain("Compilation completed successfully")
    })
})

