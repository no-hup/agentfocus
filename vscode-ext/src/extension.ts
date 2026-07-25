import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import { execSync } from 'child_process';

const APP_NAME = 'agentfocus';
const CACHE_DIR = path.join(os.homedir(), '.cache', APP_NAME);

export function activate(context: vscode.ExtensionContext) {
    if (!fs.existsSync(CACHE_DIR)) {
        fs.mkdirSync(CACHE_DIR, { recursive: true, mode: 0o700 });
    }

    let debounceTimer: NodeJS.Timeout | null = null;
    let watcher: fs.FSWatcher;
    
    try {
        watcher = fs.watch(CACHE_DIR, (eventType, filename) => {
            if ((eventType === 'change' || eventType === 'rename') && filename && filename.endsWith('.json')) {
                if (debounceTimer) clearTimeout(debounceTimer);
                debounceTimer = setTimeout(() => {
                    handleSignalFile(path.join(CACHE_DIR, filename));
                }, 75);
            }
        });
        context.subscriptions.push({ dispose: () => watcher.close() });
    } catch (e) {
        console.error('Failed to watch cache dir', e);
    }
}

function getAncestorPids(startPid: number): Set<number> {
    const ancestors = new Set<number>();
    let currentPid = startPid;
    while (currentPid > 1) {
        try {
            const out = execSync(`ps -p ${currentPid} -o ppid=`, { encoding: 'utf8' }).trim();
            if (!out) break;
            const ppid = parseInt(out, 10);
            if (isNaN(ppid) || ppid <= 1) break;
            ancestors.add(ppid);
            currentPid = ppid;
        } catch (e) {
            break;
        }
    }
    return ancestors;
}

async function handleSignalFile(filePath: string) {
    try {
        let content: string;
        try {
            content = fs.readFileSync(filePath, 'utf8');
        } catch (e: any) {
            if (e.code === 'ENOENT') return;
            throw e;
        }

        let data: any;
        try {
            data = JSON.parse(content);
        } catch (e) {
            // retry once for partial writes
            await new Promise(r => setTimeout(r, 50));
            content = fs.readFileSync(filePath, 'utf8');
            data = JSON.parse(content);
        }
        
        const signalPid = data.pid;
        let matchedTerminal: vscode.Terminal | null = null;
        
        if (signalPid) {
            const ancestors = getAncestorPids(signalPid);
            const terms = vscode.window.terminals;
            for (const term of terms) {
                const termPid = await term.processId;
                if (termPid && ancestors.has(termPid)) {
                    matchedTerminal = term;
                    break;
                }
            }
        }
        
        if (!matchedTerminal) {
            return; // on tty/pid MISS, do NOTHING
        }

        const action = "Focus Terminal";
        vscode.window.showInformationMessage(`Agent: ${data.title} - ${data.message}`, action)
            .then(selection => {
                if (selection === action) {
                    matchedTerminal!.show();
                }
            });
    } catch (e) {}
}

export function deactivate() {}
