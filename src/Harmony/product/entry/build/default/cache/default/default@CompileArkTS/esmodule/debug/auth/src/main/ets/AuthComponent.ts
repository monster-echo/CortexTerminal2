if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface AuthComponent_Params {
    authService?: AuthService;
}
import { LoginPage } from "@bundle:top.rwecho.cortexterminal/entry@auth/ets/view/LoginPage";
import { ActivateWorkerPage } from "@bundle:top.rwecho.cortexterminal/entry@auth/ets/view/ActivateWorkerPage";
import { AuthService } from "@bundle:top.rwecho.cortexterminal/entry@auth/ets/service/AuthService";
export class AuthComponent extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.authService = new AuthService();
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: AuthComponent_Params) {
        if (params.authService !== undefined) {
            this.authService = params.authService;
        }
    }
    updateStateVars(params: AuthComponent_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
    }
    aboutToBeDeleted() {
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private authService: AuthService;
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            NavDestination.create(() => {
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Column.create();
                    Column.width('100%');
                    Column.height('100%');
                }, Column);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    If.create();
                    if (!this.authService.isLoggedIn()) {
                        this.ifElseBranchUpdateFunction(0, () => {
                            {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    if (isInitialRender) {
                                        let componentCall = new LoginPage(this, {}, undefined, elmtId, () => { }, { page: "feature/auth/src/main/ets/AuthComponent.ets", line: 24, col: 11 });
                                        ViewPU.create(componentCall);
                                        let paramsLambda = () => {
                                            return {};
                                        };
                                        componentCall.paramsGenerator_ = paramsLambda;
                                    }
                                    else {
                                        this.updateStateVarsOfChildByElmtId(elmtId, {});
                                    }
                                }, { name: "LoginPage" });
                            }
                        });
                    }
                    else {
                        this.ifElseBranchUpdateFunction(1, () => {
                            {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    if (isInitialRender) {
                                        let componentCall = new ActivateWorkerPage(this, {}, undefined, elmtId, () => { }, { page: "feature/auth/src/main/ets/AuthComponent.ets", line: 26, col: 11 });
                                        ViewPU.create(componentCall);
                                        let paramsLambda = () => {
                                            return {};
                                        };
                                        componentCall.paramsGenerator_ = paramsLambda;
                                    }
                                    else {
                                        this.updateStateVarsOfChildByElmtId(elmtId, {});
                                    }
                                }, { name: "ActivateWorkerPage" });
                            }
                        });
                    }
                }, If);
                If.pop();
                Column.pop();
            }, { moduleName: "entry", pagePath: "feature/auth/src/main/ets/AuthComponent" });
            NavDestination.hideTitleBar(true);
            NavDestination.backgroundColor({ "id": 50331715, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, NavDestination);
        NavDestination.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
