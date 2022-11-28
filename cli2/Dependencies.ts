import * as util from "util";
import * as fs from "fs";

const fsExists = util.promisify(fs.exists);
const fsReadFile = util.promisify(fs.readFile);

let dependeciesIR: string[];

export async function getDependecies(localDependencies: string[]):Promise<string[]> {
  localDependencies.forEach(async (dependencyPath) => {
    if (await fsExists(dependencyPath)) {
      const dependencyIR = (await fsReadFile(dependencyPath)).toString();
      dependeciesIR.push(dependencyIR);
    }
  });
  return dependeciesIR;
}
