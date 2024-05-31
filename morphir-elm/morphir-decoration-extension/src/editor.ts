import * as vscode from "vscode";
import { getDecorations, isConfigured, updateDecorations } from "./decoration-manager";
import { NodeDetail } from "./nodeDefinitions";

export function getWebviewOptions(
  extensionUri: vscode.Uri
): vscode.WebviewOptions {
  return {
    // Enable javascript in the webview
    enableScripts: true,

    // And restrict the webview to only loading content from the directory paths added in here.
    localResourceRoots: [
      vscode.Uri.joinPath(extensionUri, "media"),
      vscode.Uri.joinPath(extensionUri, "../cli/web"),
      vscode.Uri.joinPath(extensionUri, "../test-integration"),
    ],
  };
}

const rootPath =
  vscode.workspace.workspaceFolders &&
  vscode.workspace.workspaceFolders.length > 0
    ? vscode.workspace.workspaceFolders[0].uri.fsPath
    : undefined;

function nodeIDtoFqname(nodeID: string) {
  return nodeID.split("/")[0].toLowerCase();
}

export function getDecorationValues(rootPath: string, nodeDetail: NodeDetail) {
  let docs = getDecorations(rootPath);
  let jsonVal: { [key: string]: any } = {};
  return Object.entries(docs).reduce((accum, [decId, decConfig]) => {
    const filteredNodeId = Object.keys(decConfig.data).find(
      (nodeId) => nodeIDtoFqname(nodeId) === nodeDetail.name.toLowerCase()
    );
    accum[decId] = {
      distro: decConfig.iR,
      entryPoint: decConfig.entryPoint,
      initialValue: filteredNodeId ? decConfig.data[filteredNodeId] : null,
      displayName: decConfig.displayName,
      nodeID: filteredNodeId ? filteredNodeId : null,
    };
    return accum;
  }, jsonVal);
}

/**
 * Manages decorator webview panels
 */
export class DecorationPanel {
  /**
   * Track the currently panel. Only allow a single panel to exist at a time.
   */
  public static currentPanel: DecorationPanel | undefined;

  public static readonly viewType: string;

  private readonly _panel: vscode.WebviewPanel;
  private readonly _extensionUri: vscode.Uri;
  private _disposables: vscode.Disposable[] = [];

  public static createOrShow(extensionUri: vscode.Uri, nodeDetail: NodeDetail) {
    const column = vscode.window.activeTextEditor
      ? vscode.window.activeTextEditor.viewColumn
      : undefined;

    // If we already have a panel, show it.
    if (DecorationPanel.currentPanel) {
      DecorationPanel.currentPanel._panel.reveal(column);
      return;
    }

    // Otherwise, create a new panel.
    let panel = vscode.window.createWebviewPanel(
      nodeDetail.name,
      nodeDetail.name.split(":").pop()!,
      column || vscode.ViewColumn.One,
      getWebviewOptions(extensionUri)
    );

    DecorationPanel.currentPanel = new DecorationPanel(
      panel,
      extensionUri,
      nodeDetail
    );
  }

  public static revive(
    panel: vscode.WebviewPanel,
    extensionUri: vscode.Uri,
    nodeDetail: NodeDetail
  ) {
    DecorationPanel.currentPanel = new DecorationPanel(
      panel,
      extensionUri,
      nodeDetail
    );
  }

  private constructor(
    panel: vscode.WebviewPanel,
    extensionUri: vscode.Uri,
    nodeDetail: NodeDetail
  ) {
    this._panel = panel;
    this._extensionUri = extensionUri;

    // Set the webview's initial html content
    this._update(nodeDetail);

    // Listen for when the panel is disposed
    // This happens when the user closes the panel or when the panel is closed programmatically
    this._panel.onDidDispose(() => this.dispose(), null, this._disposables);

    // Update the content based on view changes
    this._panel.onDidChangeViewState(
      (e) => {
        if (this._panel.visible) {
          this._update(nodeDetail);
        }
      },
      null,
      this._disposables
    );
  }

  public dispose() {
    DecorationPanel.currentPanel = undefined;

    // Clean up our resources
    this._panel.dispose();

    while (this._disposables.length) {
      const x = this._disposables.pop();
      if (x) {
        x.dispose();
      }
    }
  }

  private _update(nodeDetail: NodeDetail) {
    const webview = this._panel.webview;
    this._updateForDecorations(webview, nodeDetail);
  }

  private _updateForDecorations(
    webview: vscode.Webview,
    nodeDetail: NodeDetail
  ) {
    this._panel.webview.html = this._getHtmlForWebview(webview, nodeDetail);
  }

  private _getHtmlForWebview(webview: vscode.Webview, nodeDetail: NodeDetail) {
    let flagValues = getDecorationValues(rootPath!, nodeDetail);
    let jsonVal = {};
    webview.onDidReceiveMessage(
      async (data) => {
        if (data.type == "update") {
          const payload = data.payload;
          let val = flagValues[payload.id];
          let updateValue = payload.value;
          if (val.nodeID !== null) {
            jsonVal = {
              nodeID: val.nodeID,
              value: updateValue,
            };
            return updateDecorations(payload.id, jsonVal, rootPath!);
          } else {
            jsonVal = {
              nodeID: `${nodeDetail.name}/${nodeDetail.type}`,
              value: updateValue,
            };
            return updateDecorations(payload.id, jsonVal, rootPath!);
          }
        }
      },
      null,
      this._disposables
    );

    const customValueEditorPath = vscode.Uri.joinPath(
      this._extensionUri,
      "../cli/web/valueEditor.js"
    );
    const customEditorUri = webview.asWebviewUri(customValueEditorPath);

    const customElementPath = vscode.Uri.joinPath(
      this._extensionUri,
      "../cli/web/editor-custom-element.js"
    );
    const customElementUri = webview.asWebviewUri(customElementPath);

    // Local path to css styles
    const styleResetPath = vscode.Uri.joinPath(
      this._extensionUri,
      "media",
      "reset.css"
    );
    const stylesPathMainPath = vscode.Uri.joinPath(
      this._extensionUri,
      "media",
      "vscode.css"
    );

    // Uri to load styles into webview
    const stylesResetUri = webview.asWebviewUri(styleResetPath);

    const stylesMainUri = webview.asWebviewUri(stylesPathMainPath);

    // Use a nonce to only allow specific scripts to be run
    const nonce = getNonce();

    /* Each Editor is a custom element and as a result, creates its own stacking context.
    * This causes editors that appear later to have a stacking valuethat is higher than the editors above them.
    * The list is reversed here but also reserved later on in the  flex-direction, so that the elements can be laid out
    * in the prefered  stacking order.
    */
    const editors = Object.entries(flagValues)
      .reverse()
      .map(([decorationID, decorationConfig]) => {
        return `
        <div class="value-editor">
        <h1>${
          decorationConfig.displayName
        }</h1> <value-editor class=editor id=${decorationID} distribution=${JSON.stringify(
          decorationConfig.distro
        )} entrypoint="${
          decorationConfig.entryPoint
        }" initialvalue=${JSON.stringify(
          decorationConfig.initialValue
        )}></value-editor> </div>`;
      })
      .join("");

    return `<!DOCTYPE html>
			<html lang="en">
			<head>

				<meta charset="UTF-8">

				<meta name="viewport" content="width=device-width, initial-scale=1.0">

				<link href="${stylesResetUri}" rel="stylesheet">
				<link href="${stylesMainUri}" rel="stylesheet">
       
				<title>Value Editor</title>
			</head>
			<body>
        <div class="editor-wrapper">
        ${editors}
        </div>
        <script nonce="${nonce}" src="${customEditorUri}"></script>  
        <script nonce="${nonce}" src="${customElementUri}"></script> 
        <script nonce="${nonce}">
            const valueEditor = document.createElement("value-editor");
            const vscode = acquireVsCodeApi();
            
            
            const valueElements = document.querySelectorAll("value-editor");
              valueElements.forEach((valueUpdate)=>{
                valueUpdate.addEventListener("valueUpdated", (event) => {
                  const target = event.target;
                  
                  const updatedValue = event.detail;
                  const jsonData = {
                    id: target.id,
                    value: updatedValue,
                  }
                  vscode.postMessage({ type: "update", payload: jsonData });
                });
              })
        </script>
			</body>
			</html>`;
  }
}

function getNonce() {
  let text = "";
  const possible =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  for (let i = 0; i < 32; i++) {
    text += possible.charAt(Math.floor(Math.random() * possible.length));
  }
  return text;
}
