// The module 'vscode' contains the VS Code extensibility API
// Import the module and reference it with the alias vscode in your code below
import * as vscode from "vscode";
import { Dependency, DepNodeProvider } from "./nodeDefinitions";
import * as fs from "fs";
import { DecorationPanel, getWebviewOptions } from "./editor";

export function activate(context: vscode.ExtensionContext) {
  const rootPath =
    vscode.workspace.workspaceFolders &&
    vscode.workspace.workspaceFolders.length > 0
      ? vscode.workspace.workspaceFolders[0].uri.fsPath
      : undefined;

  // Samples of `window.registerTreeDataProvider`
  const nodeDependenciesProvider = new DepNodeProvider(rootPath);
  vscode.window.registerTreeDataProvider(
    "nodeDependencies",
    nodeDependenciesProvider
  );
  vscode.commands.registerCommand("nodeDependencies.refreshEntry", () =>
    nodeDependenciesProvider.refresh()
  );

  // context.subscriptions.push(
  // 	vscode.commands.registerCommand('catCoding.start', () => {
  // 		DecorationPanel.createOrShow(context.extensionUri);
  // 	})
  // );

  // context.subscriptions.push(
  //   vscode.commands.registerCommand("catCoding.doRefactor", () => {
  //     if (DecorationPanel.currentPanel) {
  //       DecorationPanel.currentPanel.doRefactor();
  //     }
  //   })
  // );

  // vscode.commands.registerCommand("extension.openPackageOnNpm", (moduleName) =>
  //   vscode.commands.executeCommand(
  //     "vscode.open",
  //     vscode.Uri.parse(`https://www.npmjs.com/package/${moduleName}`)
  //   )
  // );
  // const editorHTML = fs.readFileSync('view/valueEditor.html')

  context.subscriptions.push(
    vscode.commands.registerCommand("nodeDependencies.editor", (moduleName) => {
        DecorationPanel.createOrShow(context.extensionUri, moduleName);
    }) 
  );

  if (vscode.window.registerWebviewPanelSerializer) {
    // Make sure we register a serializer in activation event
    vscode.window.registerWebviewPanelSerializer(DecorationPanel.viewType, {
      async deserializeWebviewPanel(
        webviewPanel: vscode.WebviewPanel,
        state: any
      ) {
        console.log(`Got state: ${state}`);
        // Reset the webview options so we use latest uri for `localResourceRoots`.
        webviewPanel.webview.options = getWebviewOptions(context.extensionUri);
        // DecorationPanel.revive(webviewPanel, context.extensionUri);
      },
    });
  }

  vscode.commands.registerCommand("nodeDependencies.addEntry", () =>
    vscode.window.showInformationMessage(`Successfully called add entry.`)
  );
  vscode.commands.registerCommand(
    "nodeDependencies.editEntry",
    (node: Dependency) =>
      vscode.window.showInformationMessage(
        `Successfully called edit entry on ${node.label}.`
      )
  );
  vscode.commands.registerCommand(
    "nodeDependencies.deleteEntry",
    (node: Dependency) =>
      vscode.window.showInformationMessage(
        `Successfully called delete entry on ${node.label}.`
      )
  );
}

// This method is called when your extension is deactivated
export function deactivate() {}
