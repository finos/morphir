import * as vscode from "vscode";
import * as fs from "fs";
import * as path from "path";
import { Morphir, toDistribution } from "morphir-elm";

export class DepNodeProvider implements vscode.TreeDataProvider<Decoration> {
  private _onDidChangeTreeData: vscode.EventEmitter<
    Decoration | undefined | void
  > = new vscode.EventEmitter<Decoration | undefined | void>();
  readonly onDidChangeTreeData: vscode.Event<Decoration | undefined | void> =
    this._onDidChangeTreeData.event;

  constructor(private workspaceRoot: string | undefined) {}

  refresh(): void {
    this._onDidChangeTreeData.fire();
  }

  getTreeItem(element: Decoration): vscode.TreeItem {
    return element;
  }

  getChildren(element?: Decoration): Thenable<Decoration[]> {
    if (!this.workspaceRoot) {
      vscode.window.showInformationMessage("No Decoration in empty workspace");
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
  ): Decoration => {
    let displayName = fQname.split(".").pop()
    if (types && types.length !== 0) {
      return new Decoration(displayName!,
        fQname,
        vscode.TreeItemCollapsibleState.Collapsed,
        {
          command: "decorations.editor",
          title: "opening",
          arguments: [fQname],
        }
      );
    } else {
      return new Decoration(displayName!, fQname, vscode.TreeItemCollapsibleState.None, {
        command: "decorations.editor",
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
    element?: Decoration
  ): Decoration[] => {
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
    element?: Decoration
  ): Decoration[] {
    const workspaceRoot = this.workspaceRoot;
    if (this.pathExists(iRPath) && workspaceRoot) {
      const morphirIR = fs.readFileSync(iRPath!);
      const dist = toDistribution(morphirIR.toString());
      return this.definitionArr(dist, element);
    } else {
      return [];
    }
  }

  private pathExists(p: string): boolean {
    try {
      fs.accessSync(p);
    } catch (err) {
      return false;
    }
    return true;
  }
}

export class Decoration extends vscode.TreeItem {
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
    light: path.join(__filename, "..", "..", "media", "light-Decoration.svg"),
    dark: path.join(__filename, "..", "..", "media", "dark-Decoration.svg"),
  };
  contextValue = "Decoration";
}
