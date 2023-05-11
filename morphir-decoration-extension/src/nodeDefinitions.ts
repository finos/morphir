import * as vscode from "vscode";
import * as fs from "fs";
import * as util from "util";
import * as path from "path";
import { Morphir, toDistribution } from "morphir-elm";

export class DepNodeProvider implements vscode.TreeDataProvider<Dependency> {
  private _onDidChangeTreeData: vscode.EventEmitter<
    Dependency | undefined | void
  > = new vscode.EventEmitter<Dependency | undefined | void>();
  readonly onDidChangeTreeData: vscode.Event<Dependency | undefined | void> =
    this._onDidChangeTreeData.event;

  constructor(private workspaceRoot: string | undefined) {}

  refresh(): void {
    this._onDidChangeTreeData.fire();
  }

  getTreeItem(element: Dependency): vscode.TreeItem {
    return element;
  }

  getChildren(element?: Dependency): Thenable<Dependency[]> {
    if (!this.workspaceRoot) {
      vscode.window.showInformationMessage("No dependency in empty workspace");
      return Promise.resolve([]);
    }
    const morphirIRPath = path.join(this.workspaceRoot, "morphir-ir.json");
    if (element) {
      return Promise.resolve(this.getDefinitionTree(morphirIRPath, element));
    } else {
      if (this.pathExists(morphirIRPath)) {
        return Promise.resolve(this.getDefinitionTree(morphirIRPath));
      } else {
        vscode.window.showInformationMessage(
          "Workspace has no morphir-ir.json"
        );
        return Promise.resolve([]);
      }
    }
  }

  private toDefinitionTree = (
    fQname: string,
    types?: Array<string>
  ): Dependency => {
    let displayName = fQname.split(".").pop()
    if (types && types.length !== 0) {
      return new Dependency(displayName!,
        fQname,
        vscode.TreeItemCollapsibleState.Collapsed,
        {
          command: "nodeDependencies.editor",
          title: "opening",
          arguments: [fQname],
        }
      );
    } else {
      return new Dependency(displayName!, fQname, vscode.TreeItemCollapsibleState.None, {
        command: "nodeDependencies.editor",
        title: "opening",
        arguments: [fQname],
      });
    }
  };

  private capitalize(str: string): string {
    return str.substring(0, 1).toUpperCase() + str.substring(1).toLowerCase();
  }

  private definitionArr = (
    ir: Morphir.IR.Distribution.Distribution,
    element?: Dependency
  ): Dependency[] => {
    let moduleNameArr: Array<string> = [];
    let moduleDef = new Map<string, Array<string>>();
    switch (ir.kind) {
      case "Library":
        ir.arg3.modules.forEach((accessControlledModuleDef, moduleName) => {
          let childrenNames: Array<string> = [];
          let fQName = [...ir.arg1, moduleName.map((n) => n.map(this.capitalize).join("")).join("")].join(".")
          moduleNameArr.push(
            fQName
            // moduleName.map((n) => n.map(this.capitalize).join("")).join(" ")
          );

          accessControlledModuleDef.value.types.forEach(
            (documentedAccessControlledTypeDef, typeName) => {
              let childFQName = [fQName, typeName.join("")].join(".")
              childrenNames.push(childFQName);
            }
          );

          accessControlledModuleDef.value.values.forEach(
            (documentedAccessControlledValueDef, valueName) => {
              let childFQName = [fQName, valueName.join("")].join(".")
              childrenNames.push(childFQName);
            }
          );

          moduleDef.set(
            fQName,
            childrenNames
          );
        });
        if (element) {
          let modType = moduleDef.get(element.version)!;
          return modType.map((typ) => {
            return this.toDefinitionTree(typ);
          });
        }
        return moduleNameArr.map((moduleStr) => {
          let modType = moduleDef.get(moduleStr)!;
          return this.toDefinitionTree(moduleStr, modType);
        });
    }
  };

  /**
   * Given the path to the IR, read all its content.
   */
  private getDefinitionTree(
    iRPath: string,
    element?: Dependency
  ): Dependency[] {
    const workspaceRoot = this.workspaceRoot;
    if (this.pathExists(iRPath) && workspaceRoot) {
      const morphirIR = fs.readFileSync(iRPath!);
      const dist = toDistribution(morphirIR.toString());
      console.log(dist)
      return this.definitionArr(dist, element);
    } else {
      return [];
    }
  }

  // private getDefinitionChildren(
  //   ir: Morphir.IR.Distribution.Distribution,
  //   element: Dependency
  // ): Dependency[] {
  //   let moduleDef = new Map<string, Array<string>>();
  //   switch (ir.kind) {
  //     case "Library":
  //       ir.arg3.modules.forEach((accessControlledModuleDef, moduleName) => {
  //         let moduleValues: Array<string> = [];

  //         accessControlledModuleDef.value.types.forEach(
  //           (documentedAccessControlledTypeDef, typeName) => {
  //             moduleValues.push(typeName.map(this.capitalize).join(" "));
  //           }
  //         );
  //         accessControlledModuleDef.value.values.forEach(
  //           (documentedAccessControlledValueDef, valueName) => {
  //             moduleValues.push(valueName.map(this.capitalize).join(" "));
  //           }
  //         );
  //         moduleDef.set(
  //           moduleName.map((n) => n.map(this.capitalize).join("")).join(" "),
  //           moduleValues
  //         );
  //       });
  //       let modType = moduleDef.get(element.label)!;
  //       return modType.map((typ) => {
  //         return this.toDefinitionTree(typ);
  //       });
  //   }
  // }

  private pathExists(p: string): boolean {
    try {
      fs.accessSync(p);
    } catch (err) {
      return false;
    }
    return true;
  }
}

export class Dependency extends vscode.TreeItem {
  constructor(
    public readonly label: string,
    public readonly version: string,
    public readonly collapsibleState: vscode.TreeItemCollapsibleState,
    public readonly command?: vscode.Command
  ) {
    super(label, collapsibleState);

    this.tooltip = `${this.label}`;
    this.description = this.version;
  }

  iconPath = {
    light: path.join(__filename, "..", "..", "media", "light-dependency.svg"),
    dark: path.join(__filename, "..", "..", "media", "dark-dependency.svg"),
  };
  contextValue = "dependency";
}
