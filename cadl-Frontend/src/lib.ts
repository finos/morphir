import {
  createCadlLibrary,
  JSONSchemaType,
} from "@cadl-lang/compiler";

export interface EmitterOption {
  "output-file"?: string;
  "type-only"?: boolean
}

const MorphirOption: JSONSchemaType<EmitterOption> = {
  type: "object",
  additionalProperties: false,
  properties: {
    "output-file": { type: "string" , nullable:true},
    "type-only":{type:"boolean", nullable:true}
  },
  required: [],
};

const libDef = {
  name: "morphirLib",
  diagnostics: {},
  emitter: {
    options: MorphirOption,
  },
} as const;

export const morphirLib = createCadlLibrary(libDef);
export const {reportDiagnostic} = morphirLib


