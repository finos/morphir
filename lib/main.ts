import * as fs from "fs";
import * as util from "util";
import { Morphir } from './generated/Morphir'


const fsReadFile = util.promisify(fs.readFile);

fsReadFile('./morphir-ir.json')
    .then(content => {
        const ir: Morphir.IR.Distribution.Distribution = loadMorphirIR(content.toString())
        switch (ir.kind) {
            case 'Library':
                ir.arg3.modules.forEach((accessControlledModuleDef, moduleName) => {
                    console.log(moduleName.map(n => n.map(capitalize).join('')).join('.'))
                    accessControlledModuleDef.value.types.forEach((documentedAccessControlledTypeDef, typeName) => {
                        console.log(`  - ${typeName}`)
                    })
                })
        }
    })
    .catch(error => {
        console.error(error)
    })


function loadMorphirIR(text): Morphir.IR.Distribution.Distribution {
    let data = JSON.parse(text);

    if (data['formatVersion'] != 2) {
        throw "Unsupported morphir-ir.json format";
    }

    return Morphir.IR.Distribution.decodeDistribution(data['distribution']);
}

function capitalize(str: string): string {
    return str.substring(0, 1).toUpperCase() + str.substring(1).toLowerCase()
}