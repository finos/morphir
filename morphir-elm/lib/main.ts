import { Morphir_IR_Distribution as Distribution } from "./generated/morphir/ir/Distribution";
import { Morphir_IR_Module } from "./generated/morphir/ir/Module";
import { Morphir_IR_Package } from "./generated/morphir/ir/Package";
import { Morphir_IR_Path } from "./generated/morphir/ir/Path";
import { Morphir_IR_Type } from "./generated/morphir/ir/Type";
import { Morphir } from "./generated/Morphir";


function toDistribution(text: string): Distribution.Distribution {
  let data = JSON.parse(text);

  if (data["formatVersion"] != 3) {
    throw "Unsupported morphir-ir.json format";
  }

  return Distribution.decodeDistribution(data["distribution"]);
}

function fromDistribution(distro: Distribution.Library): string {
  return Distribution.encodeDistribution(distro);
}

function capitalize(str: string): string {
  return str.substring(0, 1).toUpperCase() + str.substring(1).toLowerCase();
}

function lookupPackageName(
  distro: Distribution.Distribution
): Morphir_IR_Path.Path {
  switch (distro.kind) {
    case "Library":
      return distro.arg1;
  }
}

function lookupPackageDef(
  distro: Distribution.Distribution
): Morphir_IR_Package.Definition<[], Morphir_IR_Type.Type<[]>> {
  switch (distro.kind) {
    case "Library":
      return distro.arg3;
  }
}

function lookupModuleDefinition(
  moduleName: Morphir_IR_Path.Path,
  packagDef: Morphir_IR_Package.Definition<[], Morphir_IR_Type.Type<[]>>
): Morphir_IR_Module.Definition<[], Morphir_IR_Type.Type<[]>> {
  return packagDef.modules.get(moduleName).value;
}

function getModules(distro: Distribution.Distribution) {
  switch (distro.kind) {
    case "Library":
      return distro.arg3.modules;
  }
}

export {
  Morphir,
  toDistribution,
  fromDistribution,
  lookupPackageName,
  lookupPackageDef,
  lookupModuleDefinition,
  getModules,
};
