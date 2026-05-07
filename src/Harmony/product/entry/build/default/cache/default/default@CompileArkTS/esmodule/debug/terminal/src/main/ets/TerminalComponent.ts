if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface TerminalComponent_Params {
}
import { TerminalHome } from "@bundle:top.rwecho.cortexterminal/entry@terminal/ets/view/TerminalHome";
export class TerminalComponent extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: TerminalComponent_Params) {
    }
    updateStateVars(params: TerminalComponent_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
    }
    aboutToBeDeleted() {
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            NavDestination.create(() => {
                {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        if (isInitialRender) {
                            let componentCall = new TerminalHome(this, {}, undefined, elmtId, () => { }, { page: "feature/terminal/src/main/ets/TerminalComponent.ets", line: 18, col: 7 });
                            ViewPU.create(componentCall);
                            let paramsLambda = () => {
                                return {};
                            };
                            componentCall.paramsGenerator_ = paramsLambda;
                        }
                        else {
                            this.updateStateVarsOfChildByElmtId(elmtId, {});
                        }
                    }, { name: "TerminalHome" });
                }
            }, { moduleName: "entry", pagePath: "feature/terminal/src/main/ets/TerminalComponent" });
            NavDestination.hideTitleBar(true);
            NavDestination.backgroundColor({ "id": 50331715, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, NavDestination);
        NavDestination.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
