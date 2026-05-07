if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface WorkerDetailPage_Params {
    workerId?: string;
    workerName?: string;
    worker?: WorkerInfo | null;
    sessions?: WorkerSessionInfo[];
    isLoading?: boolean;
    errorMessage?: string;
    pageStack?: NavPathStack;
    gatewayUrl?: string;
    authToken?: string;
}
import http from "@ohos:net.http";
import { WorkerInfo, WorkerSessionInfo } from "@bundle:top.rwecho.cortexterminal/entry@worker/ets/model/WorkerModels";
export class WorkerDetailPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__workerId = this.createStorageLink('navWorkerId', '', "workerId");
        this.__workerName = this.createStorageLink('navWorkerName', 'Worker', "workerName");
        this.__worker = new ObservedPropertyObjectPU(null, this, "worker");
        this.__sessions = new ObservedPropertyObjectPU([], this, "sessions");
        this.__isLoading = new ObservedPropertySimplePU(false, this, "isLoading");
        this.__errorMessage = new ObservedPropertySimplePU('', this, "errorMessage");
        this.__pageStack = this.initializeConsume('pageStack', "pageStack");
        this.__gatewayUrl = this.createStorageLink('gatewayUrl', '', "gatewayUrl");
        this.__authToken = this.createStorageLink('authToken', '', "authToken");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: WorkerDetailPage_Params) {
        if (params.worker !== undefined) {
            this.worker = params.worker;
        }
        if (params.sessions !== undefined) {
            this.sessions = params.sessions;
        }
        if (params.isLoading !== undefined) {
            this.isLoading = params.isLoading;
        }
        if (params.errorMessage !== undefined) {
            this.errorMessage = params.errorMessage;
        }
    }
    updateStateVars(params: WorkerDetailPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__workerId.purgeDependencyOnElmtId(rmElmtId);
        this.__workerName.purgeDependencyOnElmtId(rmElmtId);
        this.__worker.purgeDependencyOnElmtId(rmElmtId);
        this.__sessions.purgeDependencyOnElmtId(rmElmtId);
        this.__isLoading.purgeDependencyOnElmtId(rmElmtId);
        this.__errorMessage.purgeDependencyOnElmtId(rmElmtId);
        this.__pageStack.purgeDependencyOnElmtId(rmElmtId);
        this.__gatewayUrl.purgeDependencyOnElmtId(rmElmtId);
        this.__authToken.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__workerId.aboutToBeDeleted();
        this.__workerName.aboutToBeDeleted();
        this.__worker.aboutToBeDeleted();
        this.__sessions.aboutToBeDeleted();
        this.__isLoading.aboutToBeDeleted();
        this.__errorMessage.aboutToBeDeleted();
        this.__pageStack.aboutToBeDeleted();
        this.__gatewayUrl.aboutToBeDeleted();
        this.__authToken.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __workerId: ObservedPropertyAbstractPU<string>;
    get workerId() {
        return this.__workerId.get();
    }
    set workerId(newValue: string) {
        this.__workerId.set(newValue);
    }
    private __workerName: ObservedPropertyAbstractPU<string>;
    get workerName() {
        return this.__workerName.get();
    }
    set workerName(newValue: string) {
        this.__workerName.set(newValue);
    }
    private __worker: ObservedPropertyObjectPU<WorkerInfo | null>;
    get worker() {
        return this.__worker.get();
    }
    set worker(newValue: WorkerInfo | null) {
        this.__worker.set(newValue);
    }
    private __sessions: ObservedPropertyObjectPU<WorkerSessionInfo[]>;
    get sessions() {
        return this.__sessions.get();
    }
    set sessions(newValue: WorkerSessionInfo[]) {
        this.__sessions.set(newValue);
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
        this.loadWorkerDetail();
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
            Row.padding({ left: 8, right: 16, top: 8, bottom: 8 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithChild();
            Button.width(40);
            Button.height(40);
            Button.borderRadius(20);
            Button.backgroundColor(Color.Transparent);
        }, Button);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('<');
            Text.fontSize(20);
            Text.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Text);
        Text.pop();
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.workerName);
            Text.fontSize(20);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.layoutWeight(1);
            Text.margin({ left: 8 });
        }, Text);
        Text.pop();
        // Header
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.layoutWeight(1);
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.width('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.isLoading) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        LoadingProgress.create();
                        LoadingProgress.width(40);
                        LoadingProgress.height(40);
                        LoadingProgress.color({ "id": 50331713, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        LoadingProgress.margin({ top: 40 });
                    }, LoadingProgress);
                });
            }
            // Worker info card
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // Worker info card
            if (this.worker) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.WorkerInfoCard.bind(this)();
                });
            }
            // Active sessions section
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Active sessions section
            Column.create();
            // Active sessions section
            Column.width('calc(100% - 40vp)');
            // Active sessions section
            Column.margin({ top: 24 });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Sessions');
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.width('100%');
            Text.margin({ bottom: 12 });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.sessions.length === 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('No active sessions');
                        Text.fontSize(14);
                        Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = _item => {
                            const session = _item;
                            this.SessionCard.bind(this)(session);
                        };
                        this.forEachUpdateFunction(elmtId, this.sessions, forEachItemGenFunction, (session: WorkerSessionInfo) => session.id, false, false);
                    }, ForEach);
                    ForEach.pop();
                });
            }
        }, If);
        If.pop();
        // Active sessions section
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // New Session button
            if (this.worker && this.worker.status === 'online') {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Button.createWithLabel('New Session on this Worker');
                        Button.width('calc(100% - 40vp)');
                        Button.height(48);
                        Button.borderRadius(12);
                        Button.backgroundColor({ "id": 50331714, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        Button.fontColor({ "id": 50331707, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        Button.fontSize(16);
                        Button.fontWeight(FontWeight.Medium);
                        Button.margin({ top: 24 });
                        Button.onClick(() => {
                            this.createNewSession();
                        });
                    }, Button);
                    Button.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        Column.pop();
        Scroll.pop();
        Column.pop();
    }
    WorkerInfoCard(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.width('100%');
            Column.padding(16);
            Column.borderRadius(12);
            Column.backgroundColor({ "id": 50331716, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Status indicator
            Row.create();
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Circle.create();
            Circle.width(12);
            Circle.height(12);
            Circle.fill(this.worker!.status === 'online' ? { "id": 50331719, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" } : { "id": 50331711, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Circle);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.worker!.status === 'online' ? 'Online' : 'Offline');
            Text.fontSize(14);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor(this.worker!.status === 'online' ? { "id": 50331719, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" } : { "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.margin({ left: 8 });
        }, Text);
        Text.pop();
        // Status indicator
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Worker details grid
            Grid.create();
            // Worker details grid
            Grid.columnsTemplate('1fr 1fr');
            // Worker details grid
            Grid.rowsGap(12);
            // Worker details grid
            Grid.columnsGap(12);
            // Worker details grid
            Grid.width('100%');
            // Worker details grid
            Grid.margin({ top: 16 });
        }, Grid);
        {
            const itemCreation2 = (elmtId, isInitialRender) => {
                GridItem.create(() => { }, false);
            };
            const observedDeepRender = () => {
                this.observeComponentCreation2(itemCreation2, GridItem);
                this.StatItem.bind(this)('Hostname', this.worker!.hostname || '-');
                GridItem.pop();
            };
            observedDeepRender();
        }
        {
            const itemCreation2 = (elmtId, isInitialRender) => {
                GridItem.create(() => { }, false);
            };
            const observedDeepRender = () => {
                this.observeComponentCreation2(itemCreation2, GridItem);
                this.StatItem.bind(this)('OS', this.worker!.os || '-');
                GridItem.pop();
            };
            observedDeepRender();
        }
        {
            const itemCreation2 = (elmtId, isInitialRender) => {
                GridItem.create(() => { }, false);
            };
            const observedDeepRender = () => {
                this.observeComponentCreation2(itemCreation2, GridItem);
                this.StatItem.bind(this)('CPU', `${this.worker!.cpuUsage ?? 0}%`);
                GridItem.pop();
            };
            observedDeepRender();
        }
        {
            const itemCreation2 = (elmtId, isInitialRender) => {
                GridItem.create(() => { }, false);
            };
            const observedDeepRender = () => {
                this.observeComponentCreation2(itemCreation2, GridItem);
                this.StatItem.bind(this)('Memory', `${this.worker!.memoryUsage ?? 0}%`);
                GridItem.pop();
            };
            observedDeepRender();
        }
        // Worker details grid
        Grid.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // Last seen
            if (this.worker!.lastSeenAt.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(`Last seen: ${this.formatTime(this.worker!.lastSeenAt)}`);
                        Text.fontSize(12);
                        Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        Text.margin({ top: 12 });
                    }, Text);
                    Text.pop();
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
    StatItem(label: string, value: string, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(label);
            Text.fontSize(12);
            Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(value);
            Text.fontSize(14);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.margin({ top: 2 });
        }, Text);
        Text.pop();
        Column.pop();
    }
    SessionCard(session: WorkerSessionInfo, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
            Row.padding(12);
            Row.borderRadius(8);
            Row.backgroundColor({ "id": 50331717, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Row.margin({ bottom: 8 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.alignItems(HorizontalAlign.Start);
            Column.layoutWeight(1);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(session.name || `Session ${session.id.substring(0, 8)}`);
            Text.fontSize(14);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.maxLines(1);
            Text.textOverflow({ overflow: TextOverflow.Ellipsis });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(session.status);
            Text.fontSize(12);
            Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.margin({ top: 2 });
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('Resume');
            Button.height(32);
            Button.borderRadius(8);
            Button.backgroundColor({ "id": 50331714, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Button.fontColor({ "id": 50331707, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Button.fontSize(13);
            Button.onClick(() => {
                AppStorage.setOrCreate('navSessionId', session.id);
                AppStorage.setOrCreate('navSessionName', session.name || 'Terminal');
                this.pageStack.pushPath({ name: 'TerminalSession' });
            });
        }, Button);
        Button.pop();
        Row.pop();
    }
    private formatTime(dateStr: string): string {
        if (!dateStr) {
            return 'Never';
        }
        const date = new Date(dateStr);
        const now = new Date();
        const diffMs = now.getTime() - date.getTime();
        const diffMins = Math.floor(diffMs / 60000);
        if (diffMins < 1) {
            return 'Just now';
        }
        else if (diffMins < 60) {
            return `${diffMins}m ago`;
        }
        else if (diffMins < 1440) {
            return `${Math.floor(diffMins / 60)}h ago`;
        }
        else {
            return date.toLocaleDateString();
        }
    }
    private async loadWorkerDetail() {
        this.isLoading = true;
        const baseUrl = this.gatewayUrl || 'https://gateway.ct.rwecho.top';
        try {
            const httpRequest = http.createHttp();
            const headers: Record<string, string> = { 'Accept': 'application/json' };
            if (this.authToken.length > 0) {
                headers['Authorization'] = `Bearer ${this.authToken}`;
            }
            // Load worker info
            const response = await httpRequest.request(`${baseUrl}/api/workers/${this.workerId}`, {
                method: http.RequestMethod.GET,
                header: headers,
                expectDataType: http.HttpDataType.OBJECT,
                connectTimeout: 15000,
                readTimeout: 15000
            });
            if (response.responseCode === 200) {
                const data = response.result as Record<string, Object>;
                const worker = new WorkerInfo();
                worker.id = (data['id'] as string) ?? '';
                worker.name = (data['name'] as string) ?? '';
                worker.hostname = (data['hostname'] as string) ?? '';
                worker.status = (data['status'] as string) ?? 'offline';
                worker.os = (data['os'] as string) ?? '';
                worker.cpuUsage = (data['cpuUsage'] as number) ?? 0;
                worker.memoryUsage = (data['memoryUsage'] as number) ?? 0;
                worker.lastSeenAt = (data['lastSeenAt'] as string) ?? '';
                this.worker = worker;
            }
            httpRequest.destroy();
            // Load sessions
            const sessionsRequest = http.createHttp();
            const sessionsResponse = await sessionsRequest.request(`${baseUrl}/api/workers/${this.workerId}/sessions`, {
                method: http.RequestMethod.GET,
                header: headers,
                expectDataType: http.HttpDataType.OBJECT,
                connectTimeout: 15000,
                readTimeout: 15000
            });
            if (sessionsResponse.responseCode === 200) {
                const result = sessionsResponse.result as Record<string, Object[]>;
                const sessionList = result['sessions'] ?? [];
                this.sessions = sessionList.map((s: Object) => {
                    const d = s as Record<string, Object>;
                    const session = new WorkerSessionInfo();
                    session.id = (d['id'] as string) ?? '';
                    session.name = (d['name'] as string) ?? '';
                    session.status = (d['status'] as string) ?? '';
                    session.createdAt = (d['createdAt'] as string) ?? '';
                    return session;
                });
            }
            sessionsRequest.destroy();
        }
        catch (e) {
            this.errorMessage = (e as Error).message || 'Failed to load worker details';
        }
        finally {
            this.isLoading = false;
        }
    }
    private async createNewSession() {
        const baseUrl = this.gatewayUrl || 'https://gateway.ct.rwecho.top';
        try {
            const httpRequest = http.createHttp();
            const headers: Record<string, string> = {
                'Accept': 'application/json',
                'Content-Type': 'application/json'
            };
            if (this.authToken.length > 0) {
                headers['Authorization'] = `Bearer ${this.authToken}`;
            }
            const response = await httpRequest.request(`${baseUrl}/api/sessions`, {
                method: http.RequestMethod.POST,
                header: headers,
                extraData: JSON.stringify(new SessionCreateBody(this.workerId, `Terminal on ${this.workerName}`)),
                expectDataType: http.HttpDataType.OBJECT,
                connectTimeout: 15000,
                readTimeout: 15000
            });
            if (response.responseCode === 200 || response.responseCode === 201) {
                const data = response.result as Record<string, string>;
                const sessionId = data['id'] ?? '';
                const sessionName = data['name'] ?? 'Terminal';
                AppStorage.setOrCreate('navSessionId', sessionId);
                AppStorage.setOrCreate('navSessionName', sessionName);
                this.pageStack.pushPath({ name: 'TerminalSession' });
            }
            httpRequest.destroy();
        }
        catch (e) {
            console.error('Failed to create session: ' + (e as Error).message);
        }
    }
    rerender() {
        this.updateDirtyElements();
    }
}
/**
 * Request body for creating a session on a worker.
 */
class SessionCreateBody {
    workerId: string = '';
    name: string = '';
    constructor(workerId: string, name: string) {
        this.workerId = workerId;
        this.name = name;
    }
}
