// The module 'vscode' contains the VS Code extensibility API
// Import the module and reference it with the alias vscode in your code below
import * as vscode from "vscode";
import { DepNodeProvider } from "./nodeDefinitions";
import { DecorationPanel, getWebviewOptions } from "./editor";
import { isConfigured } from "./decoration-manager";

export function activate(context: vscode.ExtensionContext) {
  const rootPath =
    vscode.workspace.workspaceFolders &&
    vscode.workspace.workspaceFolders.length > 0
      ? vscode.workspace.workspaceFolders[0].uri.fsPath
      : undefined;

  const nodeDependenciesProvider = new DepNodeProvider(rootPath);
  vscode.window.registerTreeDataProvider(
    "decorations",
    nodeDependenciesProvider
  );

  let decorationNodeDetail: any;
  const editorCommand: vscode.Disposable = vscode.commands.registerCommand(
    "decorations.editor",
    (nodeDetail) => {
      decorationNodeDetail = nodeDetail;
      DecorationPanel.createOrShow(context.extensionUri, nodeDetail);
    }
  );

  context.subscriptions.push(editorCommand);

  if (vscode.window.registerWebviewPanelSerializer) {
    vscode.window.registerWebviewPanelSerializer(DecorationPanel.viewType, {
      async deserializeWebviewPanel(
        webviewPanel: vscode.WebviewPanel,
        state: any
      ) {
        console.log(`Got state: ${state}`);
        // Reset the webview options so we use latest uri for `localResourceRoots`.
        webviewPanel.webview.options = getWebviewOptions(context.extensionUri);
        DecorationPanel.revive(
          webviewPanel,
          context.extensionUri,
          decorationNodeDetail
        );
      },
    });
  }
}

// This method is called when your extension is deactivated
export function deactivate() {}
