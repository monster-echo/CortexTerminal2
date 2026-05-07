if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface ActivateWorkerPage_Params {
    activationCode?: string;
    isLoading?: boolean;
    errorMessage?: string;
    successMessage?: string;
    authService?: AuthService;
}
import { AuthService } from "@bundle:top.rwecho.cortexterminal/entry@auth/ets/service/AuthService";
export class ActivateWorkerPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__activationCode = new ObservedPropertySimplePU('', this, "activationCode");
        this.__isLoading = new ObservedPropertySimplePU(false, this, "isLoading");
        this.__errorMessage = new ObservedPropertySimplePU('', this, "errorMessage");
        this.__successMessage = new ObservedPropertySimplePU('', this, "successMessage");
        this.authService = new AuthService();
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: ActivateWorkerPage_Params) {
        if (params.activationCode !== undefined) {
            this.activationCode = params.activationCode;
        }
        if (params.isLoading !== undefined) {
            this.isLoading = params.isLoading;
        }
        if (params.errorMessage !== undefined) {
            this.errorMessage = params.errorMessage;
        }
        if (params.successMessage !== undefined) {
            this.successMessage = params.successMessage;
        }
        if (params.authService !== undefined) {
            this.authService = params.authService;
        }
    }
    updateStateVars(params: ActivateWorkerPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__activationCode.purgeDependencyOnElmtId(rmElmtId);
        this.__isLoading.purgeDependencyOnElmtId(rmElmtId);
        this.__errorMessage.purgeDependencyOnElmtId(rmElmtId);
        this.__successMessage.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__activationCode.aboutToBeDeleted();
        this.__isLoading.aboutToBeDeleted();
        this.__errorMessage.aboutToBeDeleted();
        this.__successMessage.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __activationCode: ObservedPropertySimplePU<string>;
    get activationCode() {
        return this.__activationCode.get();
    }
    set activationCode(newValue: string) {
        this.__activationCode.set(newValue);
    }
    private __isLoading: ObservedPropertySimplePU<boolean>;
    get isLoading() {
        return this.__isLoading.get();
    }
    set isLoading(newValue: boolean) {
        this.__isLoading.set(newValue);
    }
    private __errorMessage: ObservedPropertySimplePU<string>;
    get errorMessage() {
        return this.__errorMessage.get();
    }
    set errorMessage(newValue: string) {
        this.__errorMessage.set(newValue);
    }
    private __successMessage: ObservedPropertySimplePU<string>;
    get successMessage() {
        return this.__successMessage.get();
    }
    set successMessage(newValue: string) {
        this.__successMessage.set(newValue);
    }
    private authService: AuthService;
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.width('100%');
            Scroll.height('100%');
            Scroll.backgroundColor({ "id": 50331715, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.width('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Header
            Column.create();
            // Header
            Column.width('100%');
            // Header
            Column.alignItems(HorizontalAlign.Center);
            // Header
            Column.padding({ left: 24, right: 24 });
            // Header
            Column.margin({ top: 40 });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Activate Worker');
            Text.fontSize(24);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.margin({ bottom: 8 });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Enter the activation code from your worker machine');
            Text.fontSize(14);
            Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.textAlign(TextAlign.Center);
            Text.margin({ bottom: 32 });
        }, Text);
        Text.pop();
        // Header
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Activation code input
            Column.create();
            // Activation code input
            Column.width('100%');
            // Activation code input
            Column.padding({ left: 24, right: 24 });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Activation Code');
            Text.fontSize(14);
            Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.width('100%');
            Text.margin({ bottom: 8 });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TextInput.create({ placeholder: 'Enter activation code', text: this.activationCode });
            TextInput.width('100%');
            TextInput.height(48);
            TextInput.borderRadius(12);
            TextInput.backgroundColor({ "id": 50331716, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            TextInput.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            TextInput.onChange((value: string) => {
                this.activationCode = value;
                this.errorMessage = '';
                this.successMessage = '';
            });
        }, TextInput);
        // Activation code input
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // Error message
            if (this.errorMessage.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.errorMessage);
                        Text.fontSize(13);
                        Text.fontColor({ "id": 50331704, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        Text.width('100%');
                        Text.padding({ left: 24, right: 24 });
                        Text.margin({ top: 12 });
                    }, Text);
                    Text.pop();
                });
            }
            // Success message
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // Success message
            if (this.successMessage.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.successMessage);
                        Text.fontSize(13);
                        Text.fontColor({ "id": 50331719, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        Text.width('100%');
                        Text.padding({ left: 24, right: 24 });
                        Text.margin({ top: 12 });
                    }, Text);
                    Text.pop();
                });
            }
            // Activate button
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Activate button
            Button.createWithLabel('Activate');
            // Activate button
            Button.width('calc(100% - 48vp)');
            // Activate button
            Button.height(48);
            // Activate button
            Button.margin({ top: 24 });
            // Activate button
            Button.borderRadius(12);
            // Activate button
            Button.backgroundColor({ "id": 50331714, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            // Activate button
            Button.fontColor({ "id": 50331707, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            // Activate button
            Button.fontSize(16);
            // Activate button
            Button.fontWeight(FontWeight.Medium);
            // Activate button
            Button.enabled(!this.isLoading && this.activationCode.length > 0);
            // Activate button
            Button.onClick(() => {
                this.activate();
            });
        }, Button);
        // Activate button
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Skip for now
            Text.create('Skip for now');
            // Skip for now
            Text.fontSize(14);
            // Skip for now
            Text.fontColor({ "id": 50331713, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            // Skip for now
            Text.margin({ top: 16 });
            // Skip for now
            Text.onClick(() => {
                this.authService.completeAuth();
            });
        }, Text);
        // Skip for now
        Text.pop();
        Column.pop();
        Scroll.pop();
    }
    private activate() {
        if (this.activationCode.length === 0 || this.isLoading) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = '';
        this.successMessage = '';
        this.authService.activateWorker(this.activationCode).then(() => {
            this.isLoading = false;
            this.successMessage = 'Worker activated successfully!';
            // Navigate to terminal home after a brief delay
            setTimeout(() => {
                this.authService.completeAuth();
            }, 1000);
        }).catch((err: Error) => {
            this.errorMessage = err.message || 'Activation failed';
            this.isLoading = false;
        });
    }
    rerender() {
        this.updateDirtyElements();
    }
}
