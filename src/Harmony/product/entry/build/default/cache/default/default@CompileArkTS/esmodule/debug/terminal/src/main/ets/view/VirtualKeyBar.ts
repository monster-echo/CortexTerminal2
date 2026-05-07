if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface VirtualKeyBar_Params {
    onKeyPress?: OnKeyPressCallback;
    onToggleExpand?: OnToggleExpandCallback;
    expanded?: boolean;
    ctrlLatched?: boolean;
    altLatched?: boolean;
}
import pasteboard from "@ohos:pasteboard";
/**
 * Callback type for virtual key press events.
 */
type OnKeyPressCallback = (key: string) => void;
/**
 * Callback type for expand toggle events.
 */
type OnToggleExpandCallback = () => void;
export class VirtualKeyBar extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__onKeyPress = new SynchedPropertyObjectOneWayPU(params.onKeyPress, this, "onKeyPress");
        this.__onToggleExpand = new SynchedPropertyObjectOneWayPU(params.onToggleExpand, this, "onToggleExpand");
        this.__expanded = new ObservedPropertySimplePU(false, this, "expanded");
        this.__ctrlLatched = new ObservedPropertySimplePU(false, this, "ctrlLatched");
        this.__altLatched = new ObservedPropertySimplePU(false, this, "altLatched");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: VirtualKeyBar_Params) {
        if (params.onKeyPress === undefined) {
            this.__onKeyPress.set((_key: string) => { });
        }
        if (params.onToggleExpand === undefined) {
            this.__onToggleExpand.set(() => { });
        }
        if (params.expanded !== undefined) {
            this.expanded = params.expanded;
        }
        if (params.ctrlLatched !== undefined) {
            this.ctrlLatched = params.ctrlLatched;
        }
        if (params.altLatched !== undefined) {
            this.altLatched = params.altLatched;
        }
    }
    updateStateVars(params: VirtualKeyBar_Params) {
        this.__onKeyPress.reset(params.onKeyPress);
        this.__onToggleExpand.reset(params.onToggleExpand);
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__onKeyPress.purgeDependencyOnElmtId(rmElmtId);
        this.__onToggleExpand.purgeDependencyOnElmtId(rmElmtId);
        this.__expanded.purgeDependencyOnElmtId(rmElmtId);
        this.__ctrlLatched.purgeDependencyOnElmtId(rmElmtId);
        this.__altLatched.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__onKeyPress.aboutToBeDeleted();
        this.__onToggleExpand.aboutToBeDeleted();
        this.__expanded.aboutToBeDeleted();
        this.__ctrlLatched.aboutToBeDeleted();
        this.__altLatched.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __onKeyPress: SynchedPropertySimpleOneWayPU<OnKeyPressCallback>;
    get onKeyPress() {
        return this.__onKeyPress.get();
    }
    set onKeyPress(newValue: OnKeyPressCallback) {
        this.__onKeyPress.set(newValue);
    }
    private __onToggleExpand: SynchedPropertySimpleOneWayPU<OnToggleExpandCallback>;
    get onToggleExpand() {
        return this.__onToggleExpand.get();
    }
    set onToggleExpand(newValue: OnToggleExpandCallback) {
        this.__onToggleExpand.set(newValue);
    }
    private __expanded: ObservedPropertySimplePU<boolean>;
    get expanded() {
        return this.__expanded.get();
    }
    set expanded(newValue: boolean) {
        this.__expanded.set(newValue);
    }
    private __ctrlLatched: ObservedPropertySimplePU<boolean>;
    get ctrlLatched() {
        return this.__ctrlLatched.get();
    }
    set ctrlLatched(newValue: boolean) {
        this.__ctrlLatched.set(newValue);
    }
    private __altLatched: ObservedPropertySimplePU<boolean>;
    get altLatched() {
        return this.__altLatched.get();
    }
    set altLatched(newValue: boolean) {
        this.__altLatched.set(newValue);
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.width('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Main key row
            Row.create();
            // Main key row
            Row.width('100%');
            // Main key row
            Row.height(52);
            // Main key row
            Row.justifyContent(FlexAlign.SpaceEvenly);
            // Main key row
            Row.padding({ left: 4, right: 4 });
            // Main key row
            Row.backgroundColor({ "id": 50331716, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Row);
        this.KeyButton.bind(this)('Esc', () => {
            this.onKeyPress('Escape');
        });
        this.LatchButton.bind(this)('Ctrl', this.ctrlLatched, () => {
            this.ctrlLatched = !this.ctrlLatched;
        });
        this.LatchButton.bind(this)('Alt', this.altLatched, () => {
            this.altLatched = !this.altLatched;
        });
        this.KeyButton.bind(this)('Tab', () => {
            this.onKeyPress('Tab');
        });
        this.KeyButton.bind(this)('Paste', () => {
            this.handlePaste();
        });
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Expand/collapse toggle
            Button.createWithChild();
            // Expand/collapse toggle
            Button.width(44);
            // Expand/collapse toggle
            Button.height(44);
            // Expand/collapse toggle
            Button.borderRadius(8);
            // Expand/collapse toggle
            Button.backgroundColor({ "id": 50331716, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            // Expand/collapse toggle
            Button.onClick(() => {
                this.onToggleExpand();
            });
        }, Button);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.expanded ? '▼' : '▲');
            Text.fontSize(14);
            Text.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Text);
        Text.pop();
        // Expand/collapse toggle
        Button.pop();
        // Main key row
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // Expandable arrow key row
            if (this.expanded) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Row.create();
                        Row.width('100%');
                        Row.height(52);
                        Row.justifyContent(FlexAlign.SpaceEvenly);
                        Row.padding({ left: 4, right: 4 });
                        Row.backgroundColor({ "id": 50331716, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                    }, Row);
                    this.KeyButton.bind(this)('↑', () => {
                        this.onKeyPress('ArrowUp');
                    });
                    this.KeyButton.bind(this)('↓', () => {
                        this.onKeyPress('ArrowDown');
                    });
                    this.KeyButton.bind(this)('←', () => {
                        this.onKeyPress('ArrowLeft');
                    });
                    this.KeyButton.bind(this)('→', () => {
                        this.onKeyPress('ArrowRight');
                    });
                    // Home and End
                    this.KeyButton.bind(this)('Home', () => {
                        this.onKeyPress('\x1b[H');
                    });
                    this.KeyButton.bind(this)('End', () => {
                        this.onKeyPress('\x1b[F');
                    });
                    Row.pop();
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
    KeyButton(label: string, action: () => void, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel(label);
            Button.height(44);
            Button.constraintSize({ minWidth: 44 });
            Button.borderRadius(8);
            Button.backgroundColor({ "id": 50331717, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Button.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Button.fontSize(14);
            Button.fontWeight(FontWeight.Medium);
            Button.onClick(() => {
                if (this.ctrlLatched) {
                    this.onKeyPress(`Ctrl+${label}`);
                    this.ctrlLatched = false;
                }
                else if (this.altLatched) {
                    this.onKeyPress(`Alt+${label}`);
                    this.altLatched = false;
                }
                else {
                    action();
                }
            });
        }, Button);
        Button.pop();
    }
    LatchButton(label: string, latched: boolean, toggle: () => void, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel(label);
            Button.height(44);
            Button.constraintSize({ minWidth: 44 });
            Button.borderRadius(8);
            Button.backgroundColor(latched ? { "id": 50331714, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" } : { "id": 50331717, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Button.fontColor(latched ? { "id": 50331707, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" } : { "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Button.fontSize(14);
            Button.fontWeight(FontWeight.Medium);
            Button.onClick(() => {
                toggle();
            });
        }, Button);
        Button.pop();
    }
    private async handlePaste() {
        // Read from the system clipboard using @ohos.pasteboard
        try {
            const systemPasteboard = pasteboard.getSystemPasteboard();
            const pasteData = await systemPasteboard.getData();
            const text = pasteData.getPrimaryText();
            if (text) {
                if (this.ctrlLatched) {
                    this.onKeyPress(`Ctrl+${text}`);
                    this.ctrlLatched = false;
                }
                else if (this.altLatched) {
                    this.onKeyPress(`Alt+${text}`);
                    this.altLatched = false;
                }
                else {
                    this.onKeyPress(text);
                }
            }
        }
        catch (e) {
            console.warn('Paste failed: ' + (e as Error).message);
        }
    }
    rerender() {
        this.updateDirtyElements();
    }
}
