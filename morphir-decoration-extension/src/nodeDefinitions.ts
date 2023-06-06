import * as vscode from "vscode";
import * as fs from "fs";
import * as path from "path";
import { Morphir, toDistribution } from "morphir-elm";
import { isConfigured } from "./decoration-manager";

export interface NodeDetail {
  name: string;
  type: string;
}
export class DepNodeProvider implements vscode.TreeDataProvider<TreeItem> {
  private _onDidChangeTreeData: vscode.EventEmitter<
    TreeItem | undefined | void
  > = new vscode.EventEmitter<TreeItem | undefined | void>();
  readonly onDidChangeTreeData: vscode.Event<TreeItem | undefined | void> =
    this._onDidChangeTreeData.event;

  constructor(private workspaceRoot: string | undefined) {}

  refresh(): void {
    this._onDidChangeTreeData.fire();
  }

  getTreeItem(element: TreeItem): vscode.TreeItem {
    return element;
  }

  getChildren(element?: TreeItem): Thenable<TreeItem[]> {
    if (!this.workspaceRoot) {
      vscode.window.showInformationMessage("No TreeItem in empty workspace");
      return Promise.resolve([]);
    }
    const morphirIRPath = path.join(this.workspaceRoot, "morphir-ir.json");
    if (!this.pathExists(morphirIRPath)) {
      vscode.commands.executeCommand('setContext', 'decorations.isConfigured', true)
      return Promise.resolve([])
    }
    if(!isConfigured(this.workspaceRoot)){
      vscode.commands.executeCommand('setContext', 'decorations.isConfigured', true)
      return Promise.resolve([])
    }
    if (element) {
      return Promise.resolve(this.getNodeTree(morphirIRPath, element));
    } else {
      return Promise.resolve(this.getNodeTree(morphirIRPath));
    }
  }

  private creatTreeItems = (
    node: NodeDetail,
    treeNodes?: Array<NodeDetail>
  ): TreeItem => {
    let displayName = node.name.split(":").pop();
    if (treeNodes && treeNodes.length !== 0) {
      return new TreeItem(
        displayName!,
        node,
        vscode.TreeItemCollapsibleState.Collapsed,
        {
          command: "decorations.editor",
          title: "opening",
          arguments: [node],
        }
      );
    } else {
      return new TreeItem(
        displayName!,
        node,
        vscode.TreeItemCollapsibleState.None,
        {
          command: "decorations.editor",
          title: "opening",
          arguments: [node],
        }
      );
    }
  };

  private capitalize(str: string): string {
    return str.substring(0, 1).toUpperCase() + str.substring(1).toLowerCase();
  }

  private toCamelCase(array: string[]) {
    if (array.length === 0) {
      return "";
    }
    const camelCaseString = array
      .map((word, index) => {
        if (index === 0) {
          return word.toLowerCase();
        }
        return this.capitalize(word);
      })
      .join("");
    return camelCaseString;
  }

  private createTree = (
    ir: Morphir.IR.Distribution.Distribution,
    element?: TreeItem
  ) => {
    let parentNode: NodeDetail;
    let parentArr: Array<NodeDetail> = [];
    let treeNodes: [NodeDetail, Array<NodeDetail>][] = [];
    switch (ir.kind) {
      case "Library":
        ir.arg3.modules.forEach((accessControlledModuleDef, moduleName) => {
          let childNodes: Array<NodeDetail> = [];
          let packageName = ir.arg1.map((p) => p.map(this.capitalize).join(".")).join(".");
          let nodeName = [
            packageName,
            moduleName.map((n) => n.map(this.capitalize).join("")).join("."),
          ].join(":");
          parentNode = {
            name: nodeName,
            type: "module",
          };
          parentArr.push(parentNode);

          accessControlledModuleDef.value.types.forEach(
            (documentedAccessControlledTypeDef, typeName) => {
              let childFQName = [nodeName, this.toCamelCase(typeName)].join(
                ":"
              );
              childNodes.push({ name: childFQName, type: "type" });
            }
          );

          accessControlledModuleDef.value.values.forEach(
            (documentedAccessControlledValueDef, valueName) => {
              let childFQName = [nodeName, this.toCamelCase(valueName)].join(
                ":"
              );
              childNodes.push({ name: childFQName, type: "value" });
            }
          );

          treeNodes.push([parentNode, childNodes]);
        });
        for (const [k, v] of treeNodes) {
          if (element && JSON.stringify(k) === JSON.stringify(element.data)) {
            return v.map((node) => {
              return this.creatTreeItems(node);
            });
          }
        }
        return parentArr.map((pNode) => {
          const res = treeNodes.find(
            ([node]) => node.name == pNode.name && node.type == node.type
          );
          return this.creatTreeItems(res![0], res![1]);
        });
    }
  };

  /**
   * Given the path to the IR, read all its content.
   */
  private getNodeTree(iRPath: string, element?: TreeItem) {
    const workspaceRoot = this.workspaceRoot;
    if (this.pathExists(iRPath) && workspaceRoot) {
      const morphirIR = fs.readFileSync(iRPath!);
      const dist = toDistribution(morphirIR.toString());
      return this.createTree(dist, element);
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

export class TreeItem extends vscode.TreeItem {
  constructor(
    public readonly label: string,
    public readonly data: NodeDetail,
    public readonly collapsibleState: vscode.TreeItemCollapsibleState,
    public readonly command?: vscode.Command
  ) {
    super(label, collapsibleState);
    this.description = this.data.type == "type" ? "ⓣ" : this.data.type == "value" ? "ⓥ" : ""
    this.tooltip = `${this.label}`;
  }
  contextValue = "Decoration";
}
