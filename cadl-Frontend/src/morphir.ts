import { Program, navigateProgram, Model, Namespace, getServiceNamespace, createStateAccessors } from "@cadl-lang/compiler";
import * as path from "path";
import {Morphir} from "morphir-elm"
import { EmitterOption, morphirLib } from "./lib.js";
import { Utils } from "./utils.js";

export async function $onEmit(program: Program) {
  if (!program.compilerOptions.outputPath) return;
  const outputDir = path.join(program.compilerOptions.outputPath, "morphir-ir.json");
  await createTypeEmmiter(program, outputDir)
}

// const modelMembers : {[index: string]: string[] } = {}
const modelMembers = new Map<Array<string[]>,Array<string[]>>()
let modules: Array<string[]> = []
let dist :Morphir.IR.Distribution.Distribution;

// function collectModels(modelMap: Map<string,Model>){
//   // let members: {[index: string]: string } = {}
//   let memberNames: string[]= []
//   for(let[modelName, model] of modelMap){
   
//     model.properties.forEach(element => {
//       // if(element.type.node){
//       //   members[element.name] = element.type.node.symbol.name
//       // }
//       memberNames.push(element.name)
//       // console.log(element.type.node?.symbol.name)
//     });
//     // if (model.kind === "Model") {   
//     //   new Morphir.IR.Type.Record({},)
//     // }
//     // Utils.mapDefinition(Morphir.IR.Type.TypeAliasDefinition<{}>)
//     modelMembers.set([modelName], memberNames)
//   }
//   return modelMembers;
// }


async function createTypeEmmiter(program: Program, basePath: string) {
  navigateProgram(program, {
    async namespace(n){
      if(n.name === ""){  
        for (let [key, val] of n.namespaces) {
          if (key === "Cadl") continue;

          //Collecting models
          let modelNames: Array<string[]> =[]
          for(let [modelName, models] of val.models){
            modelNames.push([modelName])
          }
          modelMembers.set([[key]],modelNames)
          dist = Utils.genDistro(modelMembers)
        }
      }
    },
  });
  const generatedIR: string = Morphir.IR.Distribution.encodeDistribution(dist)
  await program.host.writeFile(basePath, JSON.stringify(generatedIR, null, 4))
}