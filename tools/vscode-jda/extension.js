const vscode = require('vscode');
const { LanguageClient, TransportKind } = require('vscode-languageclient/node');
const path = require('path');
const fs = require('fs');

let client;

function activate(context) {
    const config = vscode.workspace.getConfiguration('jda');
    const lspEnabled = config.get('lsp.enabled', true);

    if (!lspEnabled) {
        return;
    }

    // Find jda-lsp.sh
    let lspPath = config.get('lsp.path', '');
    if (!lspPath) {
        // Auto-detect: look in tools/ relative to workspace, or in PATH
        const workspaceFolder = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
        if (workspaceFolder) {
            const candidate = path.join(workspaceFolder, 'tools', 'jda-lsp.sh');
            if (fs.existsSync(candidate)) {
                lspPath = candidate;
            }
        }
        if (!lspPath) {
            // Try relative to extension
            const extCandidate = path.join(__dirname, '..', 'jda-lsp.sh');
            if (fs.existsSync(extCandidate)) {
                lspPath = extCandidate;
            }
        }
    }

    if (!lspPath || !fs.existsSync(lspPath)) {
        vscode.window.showWarningMessage(
            'Jda LSP: jda-lsp.sh not found. Set jda.lsp.path in settings.'
        );
        return;
    }

    const serverOptions = {
        command: lspPath,
        transport: TransportKind.stdio,
    };

    const clientOptions = {
        documentSelector: [{ scheme: 'file', language: 'jda' }],
        synchronize: {
            fileEvents: vscode.workspace.createFileSystemWatcher('**/*.jda'),
        },
    };

    client = new LanguageClient(
        'jda-lsp',
        'Jda Language Server',
        serverOptions,
        clientOptions
    );

    client.start();
    context.subscriptions.push(client);
}

function deactivate() {
    if (client) {
        return client.stop();
    }
}

module.exports = { activate, deactivate };
