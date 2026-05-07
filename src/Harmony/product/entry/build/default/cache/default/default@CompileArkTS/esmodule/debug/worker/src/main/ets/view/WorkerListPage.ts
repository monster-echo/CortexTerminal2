if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface WorkerListPage_Params {
    workers?: WorkerInfo[];
    isLoading?: boolean;
    errorMessage?: string;
    pageStack?: NavPathStack;
    gatewayUrl?: string;
    authToken?: string;
}
import http from "@ohos:net.http";
import { WorkerInfo } from "@bundle:top.rwecho.cortexterminal/entry@worker/ets/model/WorkerModels";
export class WorkerListPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__workers = new ObservedPropertyObjectPU([], this, "workers");
        this.__isLoading = new ObservedPropertySimplePU(false, this, "isLoading");
        this.__errorMessage = new ObservedPropertySimplePU('', this, "errorMessage");
        this.__pageStack = this.initializeConsume('pageStack', "pageStack");
        this.__gatewayUrl = this.createStorageLink('gatewayUrl', '', "gatewayUrl");
        this.__authToken = this.createStorageLink('authToken', '', "authToken");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: WorkerListPage_Params) {
        if (params.workers !== undefined) {
            this.workers = params.workers;
        }
        if (params.isLoading !== undefined) {
            this.isLoading = params.isLoading;
        }
        if (params.errorMessage !== undefined) {
            this.errorMessage = params.errorMessage;
        }
    }
    updateStateVars(params: WorkerListPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__workers.purgeDependencyOnElmtId(rmElmtId);
        this.__isLoading.purgeDependencyOnElmtId(rmElmtId);
        this.__errorMessage.purgeDependencyOnElmtId(rmElmtId);
        this.__pageStack.purgeDependencyOnElmtId(rmElmtId);
        this.__gatewayUrl.purgeDependencyOnElmtId(rmElmtId);
        this.__authToken.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__workers.aboutToBeDeleted();
        this.__isLoading.aboutToBeDeleted();
        this.__errorMessage.aboutToBeDeleted();
        this.__pageStack.aboutToBeDeleted();
        this.__gatewayUrl.aboutToBeDeleted();
        this.__authToken.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __workers: ObservedPropertyObjectPU<WorkerInfo[]>;
    get workers() {
        return this.__workers.get();
    }
    set workers(newValue: WorkerInfo[]) {
        this.__workers.set(newValue);
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
    private __pageStack: ObservedPropertyAbstractPU<NavPathStack>;
    get pageStack() {
        return this.__pageStack.get();
    }
    set pageStack(newValue: NavPathStack) {
        this.__pageStack.set(newValue);
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
    aboutToAppear() {
        this.loadWorkers();
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.width('100%');
            Column.height('100%');
            Column.backgroundColor({ "id": 50331715, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Header
            Row.create();
            // Header
            Row.width('100%');
            // Header
            Row.padding({ left: 20, right: 20, top: 16, bottom: 16 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Workers');
            Text.fontSize(24);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.layoutWeight(1);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`${this.workers.filter(w => w.status === 'online').length} online`);
            Text.fontSize(14);
            Text.fontColor({ "id": 50331719, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Text);
        Text.pop();
        // Header
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // Loading state
            if (this.isLoading) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create();
                        Column.width('100%');
                        Column.alignItems(HorizontalAlign.Center);
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        LoadingProgress.create();
                        LoadingProgress.width(40);
                        LoadingProgress.height(40);
                        LoadingProgress.color({ "id": 50331713, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        LoadingProgress.margin({ top: 60 });
                    }, LoadingProgress);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('Loading workers...');
                        Text.fontSize(14);
                        Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        Text.margin({ top: 12 });
                    }, Text);
                    Text.pop();
                    Column.pop();
                });
            }
            // Error state
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // Error state
            if (this.errorMessage.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create();
                        Column.width('100%');
                        Column.alignItems(HorizontalAlign.Center);
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.errorMessage);
                        Text.fontSize(14);
                        Text.fontColor({ "id": 50331704, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        Text.margin({ top: 40 });
                        Text.padding({ left: 20, right: 20 });
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Button.createWithLabel('Retry');
                        Button.margin({ top: 12 });
                        Button.onClick(() => {
                            this.loadWorkers();
                        });
                    }, Button);
                    Button.pop();
                    Column.pop();
                });
            }
            // Worker grid
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // Worker grid
            if (!this.isLoading && this.workers.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Scroll.create();
                        Scroll.layoutWeight(1);
                    }, Scroll);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Flex.create({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start });
                        Flex.width('100%');
                        Flex.padding({ left: 16, right: 16 });
                    }, Flex);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = _item => {
                            const worker = _item;
                            this.WorkerCard.bind(this)(worker);
                        };
                        this.forEachUpdateFunction(elmtId, this.workers, forEachItemGenFunction, (worker: WorkerInfo) => worker.id, false, false);
                    }, ForEach);
                    ForEach.pop();
                    Flex.pop();
                    Scroll.pop();
                });
            }
            // Empty state
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // Empty state
            if (!this.isLoading && this.workers.length === 0 && this.errorMessage.length === 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create();
                        Column.width('100%');
                        Column.alignItems(HorizontalAlign.Center);
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('No workers found');
                        Text.fontSize(16);
                        Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        Text.margin({ top: 60 });
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('Activate a worker to get started');
                        Text.fontSize(14);
                        Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        Text.margin({ top: 8 });
                    }, Text);
                    Text.pop();
                    Column.pop();
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
    WorkerCard(worker: WorkerInfo, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.width('calc(50% - 12vp)');
            Column.padding(14);
            Column.borderRadius(12);
            Column.backgroundColor({ "id": 50331716, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Column.margin({ left: 4, right: 4, top: 4, bottom: 4 });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Worker header with status indicator
            Row.create();
            // Worker header with status indicator
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(worker.name || worker.hostname || 'Unknown Worker');
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.layoutWeight(1);
            Text.maxLines(1);
            Text.textOverflow({ overflow: TextOverflow.Ellipsis });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Status badge
            Row.create();
            // Status badge
            Row.padding({ left: 8, right: 8, top: 4, bottom: 4 });
            // Status badge
            Row.borderRadius(8);
            // Status badge
            Row.backgroundColor({ "id": 50331716, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Circle.create();
            Circle.width(8);
            Circle.height(8);
            Circle.fill(worker.status === 'online' ? { "id": 50331719, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" } : { "id": 50331711, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Circle);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(worker.status);
            Text.fontSize(12);
            Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.margin({ left: 4 });
        }, Text);
        Text.pop();
        // Status badge
        Row.pop();
        // Worker header with status indicator
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Worker details
            Row.create();
            // Worker details
            Row.width('100%');
            // Worker details
            Row.justifyContent(FlexAlign.SpaceBetween);
            // Worker details
            Row.margin({ top: 8 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(worker.os || 'Unknown OS');
            Text.fontSize(13);
            Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`${worker.activeSessions}/${worker.maxSessions} sessions`);
            Text.fontSize(13);
            Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Text);
        Text.pop();
        // Worker details
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Action button
            Button.createWithLabel(worker.status === 'online' ? 'Connect' : 'View');
            // Action button
            Button.width('100%');
            // Action button
            Button.height(36);
            // Action button
            Button.borderRadius(8);
            // Action button
            Button.backgroundColor(worker.status === 'online' ? { "id": 50331714, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" } : { "id": 50331717, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            // Action button
            Button.fontColor(worker.status === 'online' ? { "id": 50331707, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" } : { "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            // Action button
            Button.fontSize(14);
            // Action button
            Button.margin({ top: 12 });
            // Action button
            Button.onClick(() => {
                AppStorage.setOrCreate('navWorkerId', worker.id);
                AppStorage.setOrCreate('navWorkerName', worker.name || worker.hostname || 'Worker');
                this.pageStack.pushPath({ name: 'WorkerDetail' });
            });
        }, Button);
        // Action button
        Button.pop();
        Column.pop();
    }
    private async loadWorkers() {
        this.isLoading = true;
        this.errorMessage = '';
        const baseUrl = this.gatewayUrl || 'https://gateway.ct.rwecho.top';
        const url = `${baseUrl}/api/workers`;
        try {
            const httpRequest = http.createHttp();
            const headers: Record<string, string> = { 'Accept': 'application/json' };
            if (this.authToken.length > 0) {
                headers['Authorization'] = `Bearer ${this.authToken}`;
            }
            const response = await httpRequest.request(url, {
                method: http.RequestMethod.GET,
                header: headers,
                expectDataType: http.HttpDataType.OBJECT,
                connectTimeout: 15000,
                readTimeout: 15000
            });
            if (response.responseCode === 200) {
                const result = response.result as Record<string, Object[]>;
                const workerList = result['workers'] ?? [];
                this.workers = workerList.map((w: Object) => {
                    const data = w as Record<string, Object>;
                    const worker = new WorkerInfo();
                    worker.id = (data['id'] as string) ?? '';
                    worker.name = (data['name'] as string) ?? '';
                    worker.hostname = (data['hostname'] as string) ?? '';
                    worker.status = (data['status'] as string) ?? 'offline';
                    worker.os = (data['os'] as string) ?? '';
                    worker.activeSessions = (data['activeSessions'] as number) ?? 0;
                    worker.maxSessions = (data['maxSessions'] as number) ?? 1;
                    return worker;
                });
            }
            else {
                this.errorMessage = `Failed to load workers (${response.responseCode})`;
            }
            httpRequest.destroy();
        }
        catch (e) {
            this.errorMessage = (e as Error).message || 'Network error';
        }
        finally {
            this.isLoading = false;
        }
    }
    rerender() {
        this.updateDirtyElements();
    }
}
