import * as util from "util";
import * as fs from "fs";

const fsExists = util.promisify(fs.exists);
const fsReadFile = util.promisify(fs.readFile);

export async function getDependecies(
  localDependencies: string[]
): Promise<any[]> {
  const loadedDependencies = localDependencies.map(async (dependencyPath) => {
    if (await fsExists(dependencyPath)) {
      const dependencyIR = (await fsReadFile(dependencyPath)).toString();
      return JSON.parse(dependencyIR);
    } else {
      throw new Error(`${dependencyPath} does not exist`);
    }
  });
  return Promise.all(loadedDependencies);
}
