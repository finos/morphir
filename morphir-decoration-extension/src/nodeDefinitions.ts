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

    if (element) {
      return Promise.resolve(
        this.getDefsInIR(
          path.join(
            this.workspaceRoot,
            "node_modules",
            element.label,
            "package.json"
          )
        )
      );
    } else {
      const morphirIRPath = path.join(this.workspaceRoot, "morphir-ir.json");
      if (this.pathExists(morphirIRPath)) {
        return Promise.resolve(this.getDefsInIR(morphirIRPath));
      } else {
        vscode.window.showInformationMessage(
          "Workspace has no morphir-ir.json"
        );
        return Promise.resolve([]);
      }
    }
  }

  /**
   * Given the path to the IR, read all its content.
   */
  private getDefsInIR(iRPath: string): Dependency[] {
    const workspaceRoot = this.workspaceRoot;
    if (this.pathExists(iRPath) && workspaceRoot) {
      const toDep = (moduleName: string): Dependency => {
        if (
          this.pathExists(path.join(workspaceRoot, "node_modules", moduleName))
        ) {
          return new Dependency(
            moduleName,
            vscode.TreeItemCollapsibleState.Collapsed
          );
        } else {
          return new Dependency(
            moduleName,
            vscode.TreeItemCollapsibleState.None,
            {
              command: "extension.openPackageOnNpm",
              title: "opening",
              arguments: [moduleName],
            }
          );
        }
      };

      function capitalize(str: string): string {
        return (
          str.substring(0, 1).toUpperCase() + str.substring(1).toLowerCase()
        );
      }

      const morphirIR = fs.readFileSync(iRPath);
      function deps() {
        const ir = toDistribution(morphirIR.toString());
        let moduleNameArr: Array<string> = [];
        switch (ir.kind) {
          case "Library":
            ir.arg3.modules.forEach((accessControlledModuleDef, moduleName) => {
              moduleNameArr.push(
                moduleName.map((n) => n.map(capitalize).join("")).join(" ")
              );
              //   console.log(strModuleName);
              // accessControlledModuleDef.value.types.forEach(
              //   (documentedAccessControlledTypeDef, typeName) => {
              //     console.log(`${typeName.map(capitalize).join(" ")}`);
              //   }
              // );
            });
            return moduleNameArr.map((moduleStr) => toDep(moduleStr));
        }
      }
      // console.log(deps)
      // const devDeps = morphirIR.devDependencies
      // 	? Object.keys(morphirIR.devDependencies).map(dep => toDep(dep, morphirIR.devDependencies[dep]))
      // 	: [];
      // return deps;
      return deps();
      // return deps.concat(devDeps);
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

export class Dependency extends vscode.TreeItem {
  constructor(
    public readonly label: string,
    public readonly collapsibleState: vscode.TreeItemCollapsibleState,
    public readonly command?: vscode.Command
  ) {
    super(label, collapsibleState);

    this.tooltip = `${this.label}`;
    // this.description = this.version;
  }

  iconPath = {
    light: path.join(__filename, "..", "..", "media", "light-dependency.svg"),
    dark: path.join(__filename, "..", "..", "media", "dark-dependency.svg"),
  };
  contextValue = "dependency";
}
