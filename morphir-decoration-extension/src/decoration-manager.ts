import * as path from "path";
import * as fs from "fs";

export function isConfigured(rootPath:string):boolean{
  const decorationConfig = getMorphirConfig(rootPath);
  return Boolean(decorationConfig.decorations)
}

function getMorphirConfig(rootPath: string) {
  const filePath = path.join(rootPath, "morphir.json");
  const fileContent = fs.readFileSync(filePath);
  return JSON.parse(fileContent.toString());
}

function getDecorationConfig(rootPath: string) {
  const morphirConfig = getMorphirConfig(rootPath);
  if (morphirConfig.decorations) {
    return morphirConfig.decorations;
  } else {
    return {};
  }
}

function getDecorationFilePath(decorationID: string, rootPath: string): string {
  const decorationConfig = getDecorationConfig(rootPath)[decorationID];
  let storageLocation = null;
  if (decorationConfig.storageLocation) {
    storageLocation = decorationConfig.storageLocation;
  } else {
    storageLocation = `${decorationID}.json`;
  }
  return path.join(rootPath, storageLocation);
}

function createEmptyDecorations (decorationFilePath : string){
  fs.writeFileSync(decorationFilePath, "{}")
}

export function getDecorations(rootPath: string):{ [key: string]: any } {
  const configJsonContent = getDecorationConfig(rootPath);

  const decorationIDs = Object.keys(configJsonContent);

  let responseJson: { [key: string]: any } = {};

  return decorationIDs.reduce((accum, decorationID) => {
    const decorationFilePath = getDecorationFilePath(decorationID, rootPath);
    const irFilePath = path.join(rootPath, configJsonContent[decorationID].ir);

    if (decorationFilePath) {
      try {
        fs.accessSync(decorationFilePath);
        const attrFileContent = fs.readFileSync(decorationFilePath);
        const irFileContent = fs.readFileSync(irFilePath);
        accum[decorationID] = {
          data: JSON.parse(attrFileContent.toString()),
          displayName: configJsonContent[decorationID].displayName,
          entryPoint: configJsonContent[decorationID].entryPoint,
          iR: JSON.parse(irFileContent.toString()),
        };
        return accum;
      } catch (error) {
        createEmptyDecorations;
      }
    }
    return accum;
  }, responseJson);
}

export function updateDecorations(
  decorationID: string,
  decorationValue: any,
  rootPath: string
) {
  try {
    let jsonData;
    const decIDPath = getDecorationFilePath(decorationID, rootPath);
    const decorationContent = fs.readFileSync(decIDPath);
    jsonData = JSON.parse(decorationContent.toString());
    jsonData[decorationValue.nodeID] = decorationValue.value;
    fs.writeFileSync(decIDPath, JSON.stringify(jsonData, null, 4));
    return jsonData;
  } catch (error) {
    return error;
  }
}
