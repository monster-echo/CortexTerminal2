if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface TerminalPage_Params {
    sessionId?: string;
    sessionName?: string;
    currentState?: TerminalState;
    keyBarExpanded?: boolean;
    gatewayUrl?: string;
    authToken?: string;
    isKeyboardVisible?: boolean;
    keyboardHeight?: number;
    stateManager?: TerminalStateManager;
    transport?: TerminalTransport;
    webviewController?: webview.WebviewController;
    lastCols?: number;
    lastRows?: number;
}
import buffer from "@ohos:buffer";
import webview from "@ohos:web.webview";
import { TerminalStateManager } from "@bundle:top.rwecho.cortexterminal/entry@terminal/ets/service/TerminalStateManager";
import { TerminalTransport } from "@bundle:top.rwecho.cortexterminal/entry@terminal/ets/service/TerminalTransport";
import { TerminalState } from "@bundle:top.rwecho.cortexterminal/entry@terminal/ets/model/TerminalState";
import { StatusStrip } from "@bundle:top.rwecho.cortexterminal/entry@terminal/ets/view/StatusStrip";
import { XtermWebview } from "@bundle:top.rwecho.cortexterminal/entry@terminal/ets/view/XtermWebview";
import { VirtualKeyBar } from "@bundle:top.rwecho.cortexterminal/entry@terminal/ets/view/VirtualKeyBar";
export class TerminalPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__sessionId = this.createStorageLink('navSessionId', '', "sessionId");
        this.__sessionName = this.createStorageLink('navSessionName', 'Terminal', "sessionName");
        this.__currentState = new ObservedPropertySimplePU(TerminalState.Disconnected, this, "currentState");
        this.__keyBarExpanded = new ObservedPropertySimplePU(false, this, "keyBarExpanded");
        this.__gatewayUrl = this.createStorageLink('gatewayUrl', '', "gatewayUrl");
        this.__authToken = this.createStorageLink('authToken', '', "authToken");
        this.__isKeyboardVisible = this.createStorageLink('isKeyboardVisible', false, "isKeyboardVisible");
        this.__keyboardHeight = this.createStorageLink('keyboardHeight', 0, "keyboardHeight");
        this.stateManager = new TerminalStateManager();
        this.transport = new TerminalTransport();
        this.webviewController = new webview.WebviewController();
        this.lastCols = 80;
        this.lastRows = 24;
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: TerminalPage_Params) {
        if (params.currentState !== undefined) {
            this.currentState = params.currentState;
        }
        if (params.keyBarExpanded !== undefined) {
            this.keyBarExpanded = params.keyBarExpanded;
        }
        if (params.stateManager !== undefined) {
            this.stateManager = params.stateManager;
        }
        if (params.transport !== undefined) {
            this.transport = params.transport;
        }
        if (params.webviewController !== undefined) {
            this.webviewController = params.webviewController;
        }
        if (params.lastCols !== undefined) {
            this.lastCols = params.lastCols;
        }
        if (params.lastRows !== undefined) {
            this.lastRows = params.lastRows;
        }
    }
    updateStateVars(params: TerminalPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__sessionId.purgeDependencyOnElmtId(rmElmtId);
        this.__sessionName.purgeDependencyOnElmtId(rmElmtId);
        this.__currentState.purgeDependencyOnElmtId(rmElmtId);
        this.__keyBarExpanded.purgeDependencyOnElmtId(rmElmtId);
        this.__gatewayUrl.purgeDependencyOnElmtId(rmElmtId);
        this.__authToken.purgeDependencyOnElmtId(rmElmtId);
        this.__isKeyboardVisible.purgeDependencyOnElmtId(rmElmtId);
        this.__keyboardHeight.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__sessionId.aboutToBeDeleted();
        this.__sessionName.aboutToBeDeleted();
        this.__currentState.aboutToBeDeleted();
        this.__keyBarExpanded.aboutToBeDeleted();
        this.__gatewayUrl.aboutToBeDeleted();
        this.__authToken.aboutToBeDeleted();
        this.__isKeyboardVisible.aboutToBeDeleted();
        this.__keyboardHeight.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __sessionId: ObservedPropertyAbstractPU<string>;
    get sessionId() {
        return this.__sessionId.get();
    }
    set sessionId(newValue: string) {
        this.__sessionId.set(newValue);
    }
    private __sessionName: ObservedPropertyAbstractPU<string>;
    get sessionName() {
        return this.__sessionName.get();
    }
    set sessionName(newValue: string) {
        this.__sessionName.set(newValue);
    }
    private __currentState: ObservedPropertySimplePU<TerminalState>;
    get currentState() {
        return this.__currentState.get();
    }
    set currentState(newValue: TerminalState) {
        this.__currentState.set(newValue);
    }
    private __keyBarExpanded: ObservedPropertySimplePU<boolean>;
    get keyBarExpanded() {
        return this.__keyBarExpanded.get();
    }
    set keyBarExpanded(newValue: boolean) {
        this.__keyBarExpanded.set(newValue);
    }
    private __gatewayUrl: ObservedPropertyAbstractPU<string>;
    get gatewayUrl() {
        return this.__gatewayUrl.get();
    }
    set gatewayUrl(newValue: string) {
        this.__gatewayUrl.set(newValue);
    }
    private __authToken: ObservedPropertyAbstractPU<string>;
    get authToken() {
        return this.__authToken.get();
    }
    set authToken(newValue: string) {
        this.__authToken.set(newValue);
    }
    private __isKeyboardVisible: ObservedPropertyAbstractPU<boolean>;
    get isKeyboardVisible() {
        return this.__isKeyboardVisible.get();
    }
    set isKeyboardVisible(newValue: boolean) {
        this.__isKeyboardVisible.set(newValue);
    }
    private __keyboardHeight: ObservedPropertyAbstractPU<number>;
    get keyboardHeight() {
        return this.__keyboardHeight.get();
    }
    set keyboardHeight(newValue: number) {
        this.__keyboardHeight.set(newValue);
    }
    private stateManager: TerminalStateManager;
    private transport: TerminalTransport;
    private webviewController: webview.WebviewController;
    private lastCols: number;
    private lastRows: number;
    aboutToAppear() {
        this.stateManager.onStateChanged = (state: TerminalState) => {
            this.currentState = state;
        };
        this.connectSession();
    }
    aboutToDisappear() {
        this.transport.disconnect();
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.width('100%');
            Column.height('100%');
            Column.backgroundColor({ "id": 50331715, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Top bar with session name and back button
            Row.create();
            // Top bar with session name and back button
            Row.width('100%');
            // Top bar with session name and back button
            Row.height(52);
            // Top bar with session name and back button
            Row.padding({ left: 8, right: 8 });
            // Top bar with session name and back button
            Row.alignItems(VerticalAlign.Center);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithChild();
            Button.width(40);
            Button.height(40);
            Button.borderRadius(20);
            Button.backgroundColor(Color.Transparent);
            Button.onClick(() => {
                this.handleBack();
            });
        }, Button);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('<');
            Text.fontSize(20);
            Text.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Text);
        Text.pop();
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.sessionName);
            Text.fontSize(17);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.layoutWeight(1);
            Text.maxLines(1);
            Text.textOverflow({ overflow: TextOverflow.Ellipsis });
            Text.margin({ left: 8 });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Detach button
            Button.createWithChild();
            // Detach button
            Button.height(32);
            // Detach button
            Button.borderRadius(8);
            // Detach button
            Button.backgroundColor(Color.Transparent);
            // Detach button
            Button.onClick(() => {
                this.transport.sendDetach();
            });
        }, Button);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Detach');
            Text.fontSize(13);
            Text.fontColor({ "id": 50331713, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Text);
        Text.pop();
        // Detach button
        Button.pop();
        // Top bar with session name and back button
        Row.pop();
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new 
                    // Status strip
                    StatusStrip(this, { currentState: this.currentState }, undefined, elmtId, () => { }, { page: "feature/terminal/src/main/ets/view/TerminalPage.ets", line: 90, col: 7 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            currentState: this.currentState
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        currentState: this.currentState
                    });
                }
            }, { name: "StatusStrip" });
        }
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            __Common__.create();
            __Common__.layoutWeight(1);
        }, __Common__);
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new 
                    // Xterm webview (main terminal area)
                    XtermWebview(this, {
                        webviewController: this.webviewController,
                        onInputReady: () => {
                            // Webview initialized — trigger initial fit
                            this.fitAndResize();
                        }
                    }, undefined, elmtId, () => { }, { page: "feature/terminal/src/main/ets/view/TerminalPage.ets", line: 93, col: 7 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            webviewController: this.webviewController,
                            onInputReady: () => {
                                // Webview initialized — trigger initial fit
                                this.fitAndResize();
                            }
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        webviewController: this.webviewController,
                        onInputReady: () => {
                            // Webview initialized — trigger initial fit
                            this.fitAndResize();
                        }
                    });
                }
            }, { name: "XtermWebview" });
        }
        __Common__.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // Virtual key bar (only show when hardware keyboard is not active)
            if (!this.isKeyboardVisible) {
                this.ifElseBranchUpdateFunction(0, () => {
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new VirtualKeyBar(this, {
                                    onKeyPress: (key: string) => {
                                        this.handleVirtualKey(key);
                                    },
                                    expanded: this.keyBarExpanded,
                                    onToggleExpand: () => {
                                        this.keyBarExpanded = !this.keyBarExpanded;
                                    }
                                }, undefined, elmtId, () => { }, { page: "feature/terminal/src/main/ets/view/TerminalPage.ets", line: 104, col: 9 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {
                                        onKeyPress: (key: string) => {
                                            this.handleVirtualKey(key);
                                        },
                                        expanded: this.keyBarExpanded,
                                        onToggleExpand: () => {
                                            this.keyBarExpanded = !this.keyBarExpanded;
                                        }
                                    };
                                };
                                componentCall.paramsGenerator_ = paramsLambda;
                            }
                            else {
                                this.updateStateVarsOfChildByElmtId(elmtId, {
                                    onKeyPress: (key: string) => {
                                        this.handleVirtualKey(key);
                                    },
                                    onToggleExpand: () => {
                                        this.keyBarExpanded = !this.keyBarExpanded;
                                    }
                                });
                            }
                        }, { name: "VirtualKeyBar" });
                    }
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        Column.pop();
    }
    private async connectSession() {
        this.stateManager.setState(TerminalState.Connecting);
        try {
            this.transport.onFrame = (frame: Record<string, Object>) => {
                this.handleFrame(frame);
            };
            this.transport.onDisconnected = () => {
                if (this.currentState !== TerminalState.Detached &&
                    this.currentState !== TerminalState.Exited) {
                    this.stateManager.setState(TerminalState.Reconnecting);
                }
            };
            await this.transport.connect(this.sessionId, this.authToken, this.gatewayUrl);
            // State will be set to Replaying/Live by the server frames
        }
        catch (e) {
            this.stateManager.setState(TerminalState.Error);
            console.error('Failed to connect terminal session: ' + (e as Error).message);
        }
    }
    private handleFrame(frame: Record<string, Object>) {
        const type = frame['type'] as string ?? '';
        switch (type) {
            case 'output':
            case 'replay':
                const payload = frame['payload'] as string ?? '';
                try {
                    this.webviewController.runJavaScript(`writeBase64Output("${payload}")`);
                }
                catch (e) {
                    console.warn('Failed to write terminal output: ' + (e as Error).message);
                }
                break;
            case 'replaying':
                this.stateManager.setState(TerminalState.Replaying);
                break;
            case 'replayCompleted':
                // Clear terminal before going live to avoid stale replay + live overlap
                try {
                    this.webviewController.runJavaScript('clearTerminal()');
                }
                catch (e) {
                    console.warn('Failed to clear terminal: ' + (e as Error).message);
                }
                break;
            case 'live':
                this.stateManager.setState(TerminalState.Live);
                // After going live, fit terminal to container and send resize
                setTimeout(() => { this.fitAndResize(); }, 200);
                break;
            case 'pong':
                break;
            case 'latencyAck':
                break;
            case 'error':
                this.stateManager.setState(TerminalState.Error);
                break;
            case 'expired':
                this.stateManager.setState(TerminalState.Expired);
                break;
            case 'exited':
                this.stateManager.setState(TerminalState.Exited);
                break;
        }
    }
    /**
     * Fit the xterm terminal to its container and send resize to the PTY.
     */
    private fitAndResize() {
        try {
            this.webviewController.runJavaScript('fitTerminal()');
            // Read the actual terminal size after fitting
            this.webviewController.runJavaScript('getTerminalSize()')
                .then((result: string) => {
                const size = JSON.parse(result) as Record<string, number>;
                if (size['cols'] && size['rows'] &&
                    (size['cols'] !== this.lastCols || size['rows'] !== this.lastRows)) {
                    this.lastCols = size['cols'];
                    this.lastRows = size['rows'];
                    this.transport.sendResize(this.lastCols, this.lastRows);
                }
            })
                .catch(() => {
                // Ignore — terminal not yet ready
            });
        }
        catch (e) {
            // Ignore fit errors
        }
    }
    private handleVirtualKey(key: string) {
        const inputMap: Record<string, string> = {
            'Escape': '\x1b',
            'Tab': '\t',
            'ArrowUp': '\x1b[A',
            'ArrowDown': '\x1b[B',
            'ArrowRight': '\x1b[C',
            'ArrowLeft': '\x1b[D'
        };
        if (inputMap[key]) {
            this.sendInput(inputMap[key]);
        }
        else if (key.startsWith('Ctrl+')) {
            const ch = key.substring(5).toLowerCase().charCodeAt(0);
            if (ch >= 97 && ch <= 122) {
                this.sendInput(String.fromCharCode(ch - 96));
            }
        }
        else if (key.startsWith('Alt+')) {
            this.sendInput('\x1b' + key.substring(4));
        }
        else {
            this.sendInput(key);
        }
    }
    private sendInput(data: string) {
        const base64 = this.stringToBase64(data);
        this.transport.sendInput(base64);
    }
    private stringToBase64(str: string): string {
        const bytes: number[] = [];
        for (let i = 0; i < str.length; i++) {
            const code = str.charCodeAt(i);
            bytes.push(code & 0xFF);
        }
        let binary = '';
        for (const byte of bytes) {
            binary += String.fromCharCode(byte);
        }
        return buffer.from(binary, 'binary').toString('base64');
    }
    private handleBack() {
        this.transport.sendDetach();
        this.stateManager.setState(TerminalState.Detached);
    }
    rerender() {
        this.updateDirtyElements();
    }
}
