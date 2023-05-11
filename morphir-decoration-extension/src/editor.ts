import * as vscode from "vscode";
import { getDecorations } from "./decoration-manager";
import { Morphir, toDistribution } from "morphir-elm";

export function getWebviewOptions(
  extensionUri: vscode.Uri
): vscode.WebviewOptions {
  return {
    // Enable javascript in the webview
    enableScripts: true,

    // And restrict the webview to only loading content from our extension's `media` directory.
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
  return nodeID.split("/")[0].replace(new RegExp(":", "g"), ".").toLowerCase();
}
function isObjectEmpty(obj: object): boolean {
  return Object.keys(obj).length !== 0;
}
export function getDecorationValues(rootPath: string, fqName: string) {
  let docs = getDecorations(rootPath);
  let jsonVal: { [key: string]: any } = {};
  //   // if (isObjectEmpty(decConfig.data)) {
  //   Object.keys(decConfig.data)
  //     .map((nodeId) => {
  //       console.log(nodeId)
  //       jsonVal[decId] = {
  //         distro: decConfig.iR,
  //         entryPoint: decConfig.entryPoint,
  //         initialValue: decConfig.data[nodeId],
  //         displayName: decConfig.displayName,
  //       }
  //       // if (nodeIDtoFqname(nodeId) === fqName.toLowerCase()) {
  //       //   console.log(decConfig.data[nodeId])
  //       //   return decConfig.data[nodeId];
  //       // }
  //     })
  //     // .join("");
  //   // console.dir(decConfig.data)
  //   return jsonVal;
  //   //   }

  //   // })
  //   // }
  //   // return accum;
  //   // accum = {
  //   //   distro: decConfig.iR,
  //   //   entryPoint: decConfig.entryPoint,
  //   //   initialValue: ,
  //   //   displayName: decConfig.displayName,
  //   // };
  // });
  return Object.entries(docs).reduce((accum, [decId, decConfig]) => {
    if (isObjectEmpty(decConfig.data)) {
      Object.keys(decConfig.data).map((nodeId) => {
        if (nodeIDtoFqname(nodeId) === fqName.toLowerCase()) {
          accum[decId] = {
            distro: decConfig.iR,
            entryPoint: decConfig.entryPoint,
            initialValue: decConfig.data[nodeId],
            displayName: decConfig.displayName,
          };
        }
      });
    } else {
      accum[decId] = {
        distro: decConfig.iR,
        entryPoint: decConfig.entryPoint,
        initialValue: [],
        displayName: decConfig.displayName,
      };
    }
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

  public static readonly viewType = "decoration-editor";

  private readonly _panel: vscode.WebviewPanel;
  private readonly _extensionUri: vscode.Uri;
  private _disposables: vscode.Disposable[] = [];

  public static createOrShow(extensionUri: vscode.Uri, moduleName: string) {
    const column = vscode.window.activeTextEditor
      ? vscode.window.activeTextEditor.viewColumn
      : undefined;

    // If we already have a panel, show it.
    if (DecorationPanel.currentPanel) {
      // getDecorationValues(rootPath!,moduleName)
      DecorationPanel.currentPanel._panel.reveal(column);
      return;
    }

    // Otherwise, create a new panel.
    let panel = vscode.window.createWebviewPanel(
      DecorationPanel.viewType,
      moduleName.split(".").pop()!,
      column || vscode.ViewColumn.One,
      getWebviewOptions(extensionUri)
    );

    DecorationPanel.currentPanel = new DecorationPanel(
      panel,
      extensionUri,
      moduleName
    );
  }

  public static revive(
    panel: vscode.WebviewPanel,
    extensionUri: vscode.Uri,
    fqName: string
  ) {
    DecorationPanel.currentPanel = new DecorationPanel(
      panel,
      extensionUri,
      fqName
    );
  }

  private constructor(
    panel: vscode.WebviewPanel,
    extensionUri: vscode.Uri,
    fqName: string
  ) {
    this._panel = panel;
    this._extensionUri = extensionUri;

    // Set the webview's initial html content
    this._update(fqName);

    // Listen for when the panel is disposed
    // This happens when the user closes the panel or when the panel is closed programmatically
    this._panel.onDidDispose(() => this.dispose(), null, this._disposables);

    // Update the content based on view changes
    this._panel.onDidChangeViewState(
      (e) => {
        if (this._panel.visible) {
          this._update(fqName);
        }
      },
      null,
      this._disposables
    );

    // // Handle messages from the webview
    this._panel.webview.onDidReceiveMessage(
      (message) => {
        switch (message.command) {
          case "alert":
            vscode.window.showErrorMessage(message.text);
            return;
        }
      },
      null,
      this._disposables
    );
  }

  public doRefactor() {
    // Send a message to the webview webview.
    // You can send any JSON serializable data.
    this._panel.webview.postMessage({ command: "refactor" });
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

  private _update(fqName: string) {
    const webview = this._panel.webview;
    this._updateForDecorations(webview, fqName);
  }

  // private _update() {
  // 	const webview = this._panel.webview;

  // 	// Vary the webview's content based on where it is located in the editor.
  // 	switch (this._panel.viewColumn) {
  // 		case vscode.ViewColumn.Two:
  // 			this._updateForCat(webview, 'Compiling Cat');
  // 			return;

  // 		case vscode.ViewColumn.Three:
  // 			this._updateForCat(webview, 'Testing Cat');
  // 			return;

  // 		case vscode.ViewColumn.One:
  // 		default:
  // 			this._updateForCat(webview, 'Coding Cat');
  // 			return;
  // 	}
  // }

  // private _updateForCat(webview: vscode.Webview, catName: keyof typeof cats) {
  // 	this._panel.title = catName;
  // 	this._panel.webview.html = this._getHtmlForWebview(webview, cats[catName]);
  // }
  private _updateForDecorations(webview: vscode.Webview, fqName: string) {
    this._panel.webview.html = this._getHtmlForWebview(webview, fqName);
    // webview.onDidReceiveMessage(async (data) => {
    //   switch (data.type) {
    //     case "onInfo": {
    //       if (!data.value) {
    //         return;
    //       }
    //       vscode.window.showInformationMessage(data.value);
    //       break;
    //     }
    //     case "onError": {
    //       if (!data.value) {
    //         return;
    //       }
    //       vscode.window.showErrorMessage(data.value);
    //       break;
    //     }
    //   }
    // });
  }

  private _getHtmlForWebview(webview: vscode.Webview, fqName: string) {
    // Local path to main script run in the webview
    const scriptPathOnDisk = vscode.Uri.joinPath(
      this._extensionUri,
      "media",
      "main.js"
    );
    let flagValues = getDecorationValues(rootPath!, fqName);

    // And the uri we use to load this script in the webview
    const scriptUri = webview.asWebviewUri(scriptPathOnDisk);

    const customValueEditorPath = vscode.Uri.joinPath(
      this._extensionUri,
      "../cli/web/valueEditor.js"
    );

    const customEditorUri = webview.asWebviewUri(customValueEditorPath);

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

    return `<!DOCTYPE html>
			<html lang="en">
			<head>
				<meta charset="UTF-8">

				<!--
					Use a content security policy to only allow loading images from https or from our extension directory,
					and only allow scripts that have a specific nonce.
				-->
				 <meta http-equiv="Content-Security-Policy" content=" img-src ${
           webview.cspSource
         } https:; script-src 'nonce-${nonce}';">

				<meta name="viewport" content="width=device-width, initial-scale=1.0">

				<link href="${stylesResetUri}" rel="stylesheet">
				<link href="${stylesMainUri}" rel="stylesheet">
        <style>
          .value-editor{
            color: red;
            font-weight: bold;
            cursor: pointer;
          }
        </style>
       
				<title>Value Editor</title>
			</head>
			<body>
        ${Object.entries(flagValues).map(
          ([decorationID, decorationConfig]) => {
            return `<h1>${decorationConfig.displayName}</h1>
            <value-editor id="value-editor" distribution=${JSON.stringify(
              decorationConfig.distro
            )} entrypoint="${
              decorationConfig.entryPoint
            }" initialvalue=${JSON.stringify(
              decorationConfig.initialValue
            )}></value-editor>`;
          }
        )}
				<script nonce="${nonce}" src="${scriptUri}" type="module"></script>
        <script nonce="${nonce}" src="${customEditorUri}"></script>
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
