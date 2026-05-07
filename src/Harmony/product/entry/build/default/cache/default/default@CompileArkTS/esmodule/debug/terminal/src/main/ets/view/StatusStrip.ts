if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface StatusStrip_Params {
    currentState?: TerminalState;
}
import { TerminalState } from "@bundle:top.rwecho.cortexterminal/entry@terminal/ets/model/TerminalState";
export class StatusStrip extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__currentState = new SynchedPropertySimpleOneWayPU(params.currentState, this, "currentState");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: StatusStrip_Params) {
        if (params.currentState === undefined) {
            this.__currentState.set(TerminalState.Disconnected);
        }
    }
    updateStateVars(params: StatusStrip_Params) {
        this.__currentState.reset(params.currentState);
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__currentState.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__currentState.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __currentState: SynchedPropertySimpleOneWayPU<TerminalState>;
    get currentState() {
        return this.__currentState.get();
    }
    set currentState(newValue: TerminalState) {
        this.__currentState.set(newValue);
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
            Row.height(28);
            Row.padding({ left: 16, right: 16 });
            Row.backgroundColor(this.getBackgroundColor());
            Row.alignItems(VerticalAlign.Center);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // State indicator dot
            Row.create();
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Circle.create();
            Circle.width(8);
            Circle.height(8);
            Circle.fill(this.getIndicatorColor());
        }, Circle);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // Spinner for reconnecting state
            if (this.currentState === TerminalState.Reconnecting) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        LoadingProgress.create();
                        LoadingProgress.width(12);
                        LoadingProgress.height(12);
                        LoadingProgress.color(this.getIndicatorColor());
                        LoadingProgress.margin({ left: 4 });
                    }, LoadingProgress);
                });
            }
            else // State text
             {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        // State indicator dot
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // State text
            Text.create(this.getStateLabel());
            // State text
            Text.fontSize(12);
            // State text
            Text.fontColor(this.getTextColor());
            // State text
            Text.margin({ left: 8 });
        }, Text);
        // State text
        Text.pop();
        Row.pop();
    }
    private getStateLabel(): string {
        switch (this.currentState) {
            case TerminalState.Disconnected:
                return 'Disconnected';
            case TerminalState.Connecting:
                return 'Connecting...';
            case TerminalState.Replaying:
                return 'Replaying session...';
            case TerminalState.Live:
                return 'Connected';
            case TerminalState.Reconnecting:
                return 'Reconnecting...';
            case TerminalState.Detached:
                return 'Detached';
            case TerminalState.Expired:
                return 'Session Expired';
            case TerminalState.Exited:
                return 'Process Exited';
            case TerminalState.Error:
                return 'Connection Error';
            default:
                return 'Unknown';
        }
    }
    private getIndicatorColor(): ResourceColor {
        switch (this.currentState) {
            case TerminalState.Live:
                return { "id": 50331719, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" };
            case TerminalState.Connecting:
            case TerminalState.Reconnecting:
                return '#FFC107';
            case TerminalState.Replaying:
                return '#2196F3';
            case TerminalState.Detached:
            case TerminalState.Exited:
                return { "id": 50331711, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" };
            case TerminalState.Expired:
            case TerminalState.Error:
                return { "id": 50331704, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" };
            default:
                return { "id": 50331711, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" };
        }
    }
    private getTextColor(): ResourceColor {
        switch (this.currentState) {
            case TerminalState.Live:
                return { "id": 50331719, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" };
            case TerminalState.Expired:
            case TerminalState.Error:
                return { "id": 50331704, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" };
            default:
                return { "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" };
        }
    }
    private getBackgroundColor(): ResourceColor {
        switch (this.currentState) {
            case TerminalState.Expired:
            case TerminalState.Error:
                return '#1AFF4444';
            default:
                return { "id": 50331716, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" };
        }
    }
    rerender() {
        this.updateDirtyElements();
    }
}
