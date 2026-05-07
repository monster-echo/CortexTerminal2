if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface XtermWebview_Params {
    webviewController?: webview.WebviewController;
    onInputReady?: OnInputReadyCallback;
    gatewayUrl?: string;
    jsPort?: NativeTerminalProxy;
}
import webview from "@ohos:web.webview";
/**
 * Callback type for when the webview is ready for input.
 */
type OnInputReadyCallback = () => void;
/**
 * Proxy object for JavaScript bridge methods.
 */
class NativeTerminalProxy {
    sendInput(_data: string): void { }
}
export class XtermWebview extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__webviewController = new SynchedPropertyObjectOneWayPU(params.webviewController, this, "webviewController");
        this.__onInputReady = new SynchedPropertyObjectOneWayPU(params.onInputReady, this, "onInputReady");
        this.__gatewayUrl = this.createStorageLink('gatewayUrl', ''
        // JavaScript port for receiving messages from xterm.js
        , "gatewayUrl");
        this.jsPort = new NativeTerminalProxy();
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: XtermWebview_Params) {
        if (params.webviewController === undefined) {
            this.__webviewController.set(new webview.WebviewController());
        }
        if (params.onInputReady === undefined) {
            this.__onInputReady.set(() => { });
        }
        if (params.jsPort !== undefined) {
            this.jsPort = params.jsPort;
        }
    }
    updateStateVars(params: XtermWebview_Params) {
        this.__webviewController.reset(params.webviewController);
        this.__onInputReady.reset(params.onInputReady);
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__webviewController.purgeDependencyOnElmtId(rmElmtId);
        this.__onInputReady.purgeDependencyOnElmtId(rmElmtId);
        this.__gatewayUrl.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__webviewController.aboutToBeDeleted();
        this.__onInputReady.aboutToBeDeleted();
        this.__gatewayUrl.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __webviewController: SynchedPropertySimpleOneWayPU<webview.WebviewController>;
    get webviewController() {
        return this.__webviewController.get();
    }
    set webviewController(newValue: webview.WebviewController) {
        this.__webviewController.set(newValue);
    }
    private __onInputReady: SynchedPropertySimpleOneWayPU<OnInputReadyCallback>;
    get onInputReady() {
        return this.__onInputReady.get();
    }
    set onInputReady(newValue: OnInputReadyCallback) {
        this.__onInputReady.set(newValue);
    }
    private __gatewayUrl: ObservedPropertyAbstractPU<string>;
    get gatewayUrl() {
        return this.__gatewayUrl.get();
    }
    set gatewayUrl(newValue: string) {
        this.__gatewayUrl.set(newValue);
    }
    // JavaScript port for receiving messages from xterm.js
    private jsPort: NativeTerminalProxy;
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.width('100%');
            Column.height('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Web.create({ src: { "id": 0, "type": 30000, params: ['xterm/index.html'], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" }, controller: this.webviewController });
            Web.width('100%');
            Web.height('100%');
            Web.backgroundColor('#1a1b26');
            Web.javaScriptAccess(true);
            Web.domStorageAccess(true);
            Web.mixedMode(MixedMode.All);
            Web.onlineImageAccess(true);
            Web.zoomAccess(false);
            Web.databaseAccess(true);
            Web.cacheMode(CacheMode.Default);
            Web.darkMode(WebDarkMode.On);
            Web.onPageEnd(() => {
                this.onWebviewReady();
            });
            Web.javaScriptProxy({
                object: this.jsPort,
                name: 'NativeTerminal',
                methodList: ['sendInput'],
                controller: this.webviewController
            });
        }, Web);
        Column.pop();
    }
    /**
     * Called when the webview finishes loading the xterm.html page.
     * Initializes the terminal and signals readiness.
     */
    private onWebviewReady() {
        // Initialize xterm.js with appropriate dimensions
        try {
            this.webviewController.runJavaScript(`
        if (typeof initTerminal === 'function') {
          initTerminal();
        }
      `);
        }
        catch (e) {
            console.warn('Failed to init xterm: ' + (e as Error).message);
        }
        this.onInputReady();
    }
    /**
     * Send output data to the xterm.js terminal for rendering.
     * @param base64Payload Base64-encoded terminal output data.
     */
    writeOutput(base64Payload: string) {
        try {
            const escaped = base64Payload.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
            this.webviewController.runJavaScript(`handleOutput("${escaped}")`);
        }
        catch (e) {
            console.warn('Failed to write output: ' + (e as Error).message);
        }
    }
    /**
     * Notify xterm.js of a terminal resize event.
     * @param cols New column count
     * @param rows New row count
     */
    resize(cols: number, rows: number) {
        try {
            this.webviewController.runJavaScript(`resizeTerminal(${cols}, ${rows})`);
        }
        catch (e) {
            console.warn('Failed to resize terminal: ' + (e as Error).message);
        }
    }
    rerender() {
        this.updateDirtyElements();
    }
}
