if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface Index_Params {
    pageStack?: NavPathStack;
    authToken?: string;
    isLoggedIn?: boolean;
}
import { TerminalComponent } from "@bundle:top.rwecho.cortexterminal/entry@terminal/Index";
import { TerminalPage } from "@bundle:top.rwecho.cortexterminal/entry@terminal/Index";
import { AuthComponent } from "@bundle:top.rwecho.cortexterminal/entry@auth/Index";
import { WorkerComponent } from "@bundle:top.rwecho.cortexterminal/entry@worker/Index";
import { WorkerDetailPage } from "@bundle:top.rwecho.cortexterminal/entry@worker/Index";
import { SettingsComponent } from "@bundle:top.rwecho.cortexterminal/entry@settings/Index";
class Index extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__pageStack = new ObservedPropertyObjectPU(new NavPathStack(), this, "pageStack");
        this.addProvidedVar("pageStack", this.__pageStack, false);
        this.__authToken = this.createStorageLink('authToken', '', "authToken");
        this.__isLoggedIn = this.createStorageLink('isLoggedIn', false, "isLoggedIn");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: Index_Params) {
        if (params.pageStack !== undefined) {
            this.pageStack = params.pageStack;
        }
    }
    updateStateVars(params: Index_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__pageStack.purgeDependencyOnElmtId(rmElmtId);
        this.__authToken.purgeDependencyOnElmtId(rmElmtId);
        this.__isLoggedIn.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__pageStack.aboutToBeDeleted();
        this.__authToken.aboutToBeDeleted();
        this.__isLoggedIn.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __pageStack: ObservedPropertyObjectPU<NavPathStack>;
    get pageStack() {
        return this.__pageStack.get();
    }
    set pageStack(newValue: NavPathStack) {
        this.__pageStack.set(newValue);
    }
    private __authToken: ObservedPropertyAbstractPU<string>;
    get authToken() {
        return this.__authToken.get();
    }
    set authToken(newValue: string) {
        this.__authToken.set(newValue);
    }
    private __isLoggedIn: ObservedPropertyAbstractPU<boolean>;
    get isLoggedIn() {
        return this.__isLoggedIn.get();
    }
    set isLoggedIn(newValue: boolean) {
        this.__isLoggedIn.set(newValue);
    }
    aboutToAppear() {
        if (this.authToken && this.authToken.length > 0) {
            this.pageStack.replacePath({ name: 'TerminalHome' });
        }
        else {
            this.pageStack.replacePath({ name: 'Auth' });
        }
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Navigation.create(this.pageStack, { moduleName: "entry", pagePath: "product/entry/src/main/ets/pages/Index", isUserCreateStack: true });
            Navigation.navDestination({ builder: this.pageMap.bind(this) });
            Navigation.mode(NavigationMode.Stack);
            Navigation.hideTitleBar(true);
            Navigation.backgroundColor({ "id": 50331715, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Navigation);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.width('100%');
            Column.height('100%');
        }, Column);
        Column.pop();
        Navigation.pop();
    }
    pageMap(name: string, param: Object, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (name === 'TerminalHome') {
                this.ifElseBranchUpdateFunction(0, () => {
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new TerminalComponent(this, {}, undefined, elmtId, () => { }, { page: "product/entry/src/main/ets/pages/Index.ets", line: 45, col: 7 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {};
                                };
                                componentCall.paramsGenerator_ = paramsLambda;
                            }
                            else {
                                this.updateStateVarsOfChildByElmtId(elmtId, {});
                            }
                        }, { name: "TerminalComponent" });
                    }
                });
            }
            else if (name === 'TerminalSession') {
                this.ifElseBranchUpdateFunction(1, () => {
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new TerminalPage(this, {}, undefined, elmtId, () => { }, { page: "product/entry/src/main/ets/pages/Index.ets", line: 47, col: 7 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {};
                                };
                                componentCall.paramsGenerator_ = paramsLambda;
                            }
                            else {
                                this.updateStateVarsOfChildByElmtId(elmtId, {});
                            }
                        }, { name: "TerminalPage" });
                    }
                });
            }
            else if (name === 'Auth') {
                this.ifElseBranchUpdateFunction(2, () => {
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new AuthComponent(this, {}, undefined, elmtId, () => { }, { page: "product/entry/src/main/ets/pages/Index.ets", line: 49, col: 7 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {};
                                };
                                componentCall.paramsGenerator_ = paramsLambda;
                            }
                            else {
                                this.updateStateVarsOfChildByElmtId(elmtId, {});
                            }
                        }, { name: "AuthComponent" });
                    }
                });
            }
            else if (name === 'Workers') {
                this.ifElseBranchUpdateFunction(3, () => {
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new WorkerComponent(this, {}, undefined, elmtId, () => { }, { page: "product/entry/src/main/ets/pages/Index.ets", line: 51, col: 7 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {};
                                };
                                componentCall.paramsGenerator_ = paramsLambda;
                            }
                            else {
                                this.updateStateVarsOfChildByElmtId(elmtId, {});
                            }
                        }, { name: "WorkerComponent" });
                    }
                });
            }
            else if (name === 'WorkerDetail') {
                this.ifElseBranchUpdateFunction(4, () => {
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new WorkerDetailPage(this, {}, undefined, elmtId, () => { }, { page: "product/entry/src/main/ets/pages/Index.ets", line: 53, col: 7 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {};
                                };
                                componentCall.paramsGenerator_ = paramsLambda;
                            }
                            else {
                                this.updateStateVarsOfChildByElmtId(elmtId, {});
                            }
                        }, { name: "WorkerDetailPage" });
                    }
                });
            }
            else if (name === 'Settings') {
                this.ifElseBranchUpdateFunction(5, () => {
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new SettingsComponent(this, {}, undefined, elmtId, () => { }, { page: "product/entry/src/main/ets/pages/Index.ets", line: 55, col: 7 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {};
                                };
                                componentCall.paramsGenerator_ = paramsLambda;
                            }
                            else {
                                this.updateStateVarsOfChildByElmtId(elmtId, {});
                            }
                        }, { name: "SettingsComponent" });
                    }
                });
            }
            else {
                this.ifElseBranchUpdateFunction(6, () => {
                });
            }
        }, If);
        If.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
    static getEntryName(): string {
        return "Index";
    }
}
registerNamedRoute(() => new Index(undefined, {}), "", { bundleName: "top.rwecho.cortexterminal", moduleName: "entry", pagePath: "pages/Index", pageFullPath: "product/entry/src/main/ets/pages/Index", integratedHsp: "false", moduleType: "followWithHap" });
