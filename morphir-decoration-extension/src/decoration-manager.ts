import * as path from "path";
import * as vscode from "vscode";
import * as fs from "fs";

// const rootPath =
//   vscode.workspace.workspaceFolders &&
//   vscode.workspace.workspaceFolders.length > 0
//     ? vscode.workspace.workspaceFolders[0].uri.fsPath
//     : "";

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

function getDecorationFilePath(decorationID: string, rootPath: string) {
  const decorationConfig = getDecorationConfig(rootPath)[decorationID];
  let storageLocation = null;
  if (decorationConfig.storageLocation) {
    storageLocation = decorationConfig.storageLocation;
  } else {
    storageLocation = `${decorationID}.json`;
  }
  return path.join(rootPath, storageLocation);
}

export function getDecorations(rootPath: string) {
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
        (accum[decorationID] = {
          data: JSON.parse(attrFileContent.toString()),
          displayName: configJsonContent[decorationID].displayName,
          entryPoint: configJsonContent[decorationID].entryPoint,
          iR: JSON.parse(irFileContent.toString()),
        });
        return accum
      } catch (error) {
        fs.writeFileSync(decorationFilePath, "{}");
      }
    }
    return accum;
  }, responseJson) 
}

export function updateDecorations(
  decorationID: string,
  decorationValue: any,
  rootPath: string
) {
  try {
    const data = getDecorationFilePath(decorationID, rootPath);
    if (data) {
      fs.writeFileSync(data, JSON.stringify(decorationValue, null, 4));
    }
    return decorationValue;
  } catch (error) {
    return error;
  }
}
