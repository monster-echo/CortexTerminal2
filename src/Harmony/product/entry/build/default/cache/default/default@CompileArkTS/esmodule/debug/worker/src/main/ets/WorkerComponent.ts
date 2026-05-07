if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface WorkerComponent_Params {
}
import { WorkerListPage } from "@bundle:top.rwecho.cortexterminal/entry@worker/ets/view/WorkerListPage";
export class WorkerComponent extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: WorkerComponent_Params) {
    }
    updateStateVars(params: WorkerComponent_Params) {
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
                            let componentCall = new WorkerListPage(this, {}, undefined, elmtId, () => { }, { page: "feature/worker/src/main/ets/WorkerComponent.ets", line: 19, col: 7 });
                            ViewPU.create(componentCall);
                            let paramsLambda = () => {
                                return {};
                            };
                            componentCall.paramsGenerator_ = paramsLambda;
                        }
                        else {
                            this.updateStateVarsOfChildByElmtId(elmtId, {});
                        }
                    }, { name: "WorkerListPage" });
                }
            }, { moduleName: "entry", pagePath: "feature/worker/src/main/ets/WorkerComponent" });
            NavDestination.hideTitleBar(true);
            NavDestination.backgroundColor({ "id": 50331715, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, NavDestination);
        NavDestination.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
