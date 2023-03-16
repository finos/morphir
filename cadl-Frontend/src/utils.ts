import { Morphir } from 'morphir-elm'


export namespace Utils {
    // export function emptyDistro():Morphir.IR.Distribution.Distribution{
    //     return new Morphir.IR.Distribution.Library([],new Map(),{modules: new Map()})
    // }

    export function mapDefinition(def: Morphir.IR.Type.Definition<{}>, mappedType:Morphir.IR.Type.Type<{}>){
        switch (def.kind) {
            case "TypeAliasDefinition":
                return new Morphir.IR.Type.TypeAliasDefinition<{}>([],mappedType)
            
            case "CustomTypeDefinition":
                const decodeAccess = Morphir.IR.AccessControlled.decodePublic("Public")
                const accesConTypeConst = {
                    access: decodeAccess,
                    value: new Map()
                }
                return new Morphir.IR.Type.CustomTypeDefinition<{}>([],accesConTypeConst)
        }
    }

    export function mapTypeAttributes(tpe: Morphir.IR.Type.Type<{}>): Morphir.IR.Type.Type<{}>{
        switch (tpe.kind) {
            case "ExtensibleRecord":
                return new Morphir.IR.Type.ExtensibleRecord<{}>({},tpe.arg2,tpe.arg3)
            
            case "Record":
                return new Morphir.IR.Type.Record({},tpe.arg2)

            case "Variable":
                return new Morphir.IR.Type.Variable({},tpe.arg2)

            case "Reference":
                let decodedFQname = Morphir.IR.FQName.decodeFQName(tpe.arg2)
                return new Morphir.IR.Type.Reference({},decodedFQname,tpe.arg3.map(e => mapTypeAttributes(e)))

            case "Function":
                return new Morphir.IR.Type.Function({},mapTypeAttributes(tpe.arg2),mapTypeAttributes(tpe.arg3))

            case "Unit":
                return new Morphir.IR.Type.Unit({})

            case "Tuple":
                return new Morphir.IR.Type.Tuple({},tpe.arg2)
        }
    }

    export function insertTypes(typeData: Array<string[]> ){
        const documentedTypeDef = {
            doc: "",
            value: []
        }
        const decodeAccess = Morphir.IR.AccessControlled.decodePublic("Public")
        const accessConTypeDef = {
            access: decodeAccess,
            value: documentedTypeDef
        }
        const typeDef = new Map();
        typeData.forEach(name => {
            typeDef.set(name,accessConTypeDef)
        });
            
        return typeDef;
    }

    export function insertModuleDef(typeData: Array<string[]>){

        const moduleDef ={
            types: insertTypes(typeData),
            values: new Map(),
            doc: ""
        }
        const decodeAccess = Morphir.IR.AccessControlled.decodePublic("Public")
        return {
            access: decodeAccess,
            value: moduleDef
        }
    }

    export function genDistro(moduleData: Map<Array<string[]>,Array<string[]>>):Morphir.IR.Distribution.Distribution{

        const modulesMap = new Map();
        const packageDef = {
            modules: modulesMap
        }
        for(let [moduleName, moduleMember] of moduleData){
            const moduleDef = insertModuleDef(moduleMember)
            modulesMap.set([moduleName],moduleDef)
        }
        // moduleData.forEach(moduleName => {
        //     const moduleDef = insertModuleDef(typeData)
        //     modulesMap.set([moduleName],moduleDef)
        // });
        packageDef.modules = modulesMap
        
        return new Morphir.IR.Distribution.Library([],new Map(),packageDef)
    }

}