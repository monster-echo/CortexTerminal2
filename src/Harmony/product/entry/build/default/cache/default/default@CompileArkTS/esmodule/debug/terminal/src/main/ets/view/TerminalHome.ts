if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface TerminalHome_Params {
    recentSessions?: SessionInfo[];
    isLoading?: boolean;
    onlineWorkers?: number;
    offlineWorkers?: number;
    pageStack?: NavPathStack;
    apiClient?: RestApiClient;
}
import { RestApiClient } from "@bundle:top.rwecho.cortexterminal/entry@terminal/ets/service/RestApiClient";
import { SessionCreateRequest } from "@bundle:top.rwecho.cortexterminal/entry@terminal/ets/model/SessionModels";
import type { SessionInfo } from "@bundle:top.rwecho.cortexterminal/entry@terminal/ets/model/SessionModels";
export class TerminalHome extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__recentSessions = new ObservedPropertyObjectPU([], this, "recentSessions");
        this.__isLoading = new ObservedPropertySimplePU(false, this, "isLoading");
        this.__onlineWorkers = new ObservedPropertySimplePU(0, this, "onlineWorkers");
        this.__offlineWorkers = new ObservedPropertySimplePU(0, this, "offlineWorkers");
        this.__pageStack = this.initializeConsume('pageStack', "pageStack");
        this.apiClient = new RestApiClient();
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: TerminalHome_Params) {
        if (params.recentSessions !== undefined) {
            this.recentSessions = params.recentSessions;
        }
        if (params.isLoading !== undefined) {
            this.isLoading = params.isLoading;
        }
        if (params.onlineWorkers !== undefined) {
            this.onlineWorkers = params.onlineWorkers;
        }
        if (params.offlineWorkers !== undefined) {
            this.offlineWorkers = params.offlineWorkers;
        }
        if (params.apiClient !== undefined) {
            this.apiClient = params.apiClient;
        }
    }
    updateStateVars(params: TerminalHome_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__recentSessions.purgeDependencyOnElmtId(rmElmtId);
        this.__isLoading.purgeDependencyOnElmtId(rmElmtId);
        this.__onlineWorkers.purgeDependencyOnElmtId(rmElmtId);
        this.__offlineWorkers.purgeDependencyOnElmtId(rmElmtId);
        this.__pageStack.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__recentSessions.aboutToBeDeleted();
        this.__isLoading.aboutToBeDeleted();
        this.__onlineWorkers.aboutToBeDeleted();
        this.__offlineWorkers.aboutToBeDeleted();
        this.__pageStack.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __recentSessions: ObservedPropertyObjectPU<SessionInfo[]>;
    get recentSessions() {
        return this.__recentSessions.get();
    }
    set recentSessions(newValue: SessionInfo[]) {
        this.__recentSessions.set(newValue);
    }
    private __isLoading: ObservedPropertySimplePU<boolean>;
    get isLoading() {
        return this.__isLoading.get();
    }
    set isLoading(newValue: boolean) {
        this.__isLoading.set(newValue);
    }
    private __onlineWorkers: ObservedPropertySimplePU<number>;
    get onlineWorkers() {
        return this.__onlineWorkers.get();
    }
    set onlineWorkers(newValue: number) {
        this.__onlineWorkers.set(newValue);
    }
    private __offlineWorkers: ObservedPropertySimplePU<number>;
    get offlineWorkers() {
        return this.__offlineWorkers.get();
    }
    set offlineWorkers(newValue: number) {
        this.__offlineWorkers.set(newValue);
    }
    private __pageStack: ObservedPropertyAbstractPU<NavPathStack>;
    get pageStack() {
        return this.__pageStack.get();
    }
    set pageStack(newValue: NavPathStack) {
        this.__pageStack.set(newValue);
    }
    private apiClient: RestApiClient;
    aboutToAppear() {
        this.loadData();
    }
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
            Column.height('100%');
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
            Column.create();
            Column.alignItems(HorizontalAlign.Start);
            Column.layoutWeight(1);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 50331648, "type": 10003, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.fontSize(24);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Your terminal sessions');
            Text.fontSize(14);
            Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.margin({ top: 4 });
        }, Text);
        Text.pop();
        Column.pop();
        // Header
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Worker availability summary strip
            Row.create();
            // Worker availability summary strip
            Row.width('calc(100% - 40vp)');
            // Worker availability summary strip
            Row.margin({ top: 8 });
            // Worker availability summary strip
            Row.padding(12);
            // Worker availability summary strip
            Row.borderRadius(12);
            // Worker availability summary strip
            Row.backgroundColor({ "id": 50331716, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Circle.create();
            Circle.width(8);
            Circle.height(8);
            Circle.fill({ "id": 50331719, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Circle);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`${this.onlineWorkers} Online`);
            Text.fontSize(13);
            Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.margin({ left: 6 });
        }, Text);
        Text.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.margin({ left: 16 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Circle.create();
            Circle.width(8);
            Circle.height(8);
            Circle.fill({ "id": 50331711, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Circle);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`${this.offlineWorkers} Offline`);
            Text.fontSize(13);
            Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.margin({ left: 6 });
        }, Text);
        Text.pop();
        Row.pop();
        // Worker availability summary strip
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // Recent session card
            if (this.recentSessions.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create();
                        Column.width('calc(100% - 40vp)');
                        Column.margin({ top: 20 });
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('Recent Session');
                        Text.fontSize(14);
                        Text.fontWeight(FontWeight.Medium);
                        Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        Text.width('100%');
                        Text.margin({ bottom: 12 });
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = _item => {
                            const session = _item;
                            this.SessionCard.bind(this)(session);
                        };
                        this.forEachUpdateFunction(elmtId, this.recentSessions.slice(0, 3), forEachItemGenFunction, (session: SessionInfo) => session.id, false, false);
                    }, ForEach);
                    ForEach.pop();
                    Column.pop();
                });
            }
            // Loading indicator
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // Loading indicator
            if (this.isLoading) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        LoadingProgress.create();
                        LoadingProgress.width(32);
                        LoadingProgress.height(32);
                        LoadingProgress.color({ "id": 50331713, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        LoadingProgress.margin({ top: 40 });
                    }, LoadingProgress);
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
            if (!this.isLoading && this.recentSessions.length === 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create();
                        Column.width('100%');
                        Column.alignItems(HorizontalAlign.Center);
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('No active sessions');
                        Text.fontSize(16);
                        Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        Text.margin({ top: 40 });
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('Start a new terminal session to begin');
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
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // New Terminal primary action button
            Button.createWithLabel('New Terminal');
            // New Terminal primary action button
            Button.width('calc(100% - 40vp)');
            // New Terminal primary action button
            Button.height(52);
            // New Terminal primary action button
            Button.borderRadius(14);
            // New Terminal primary action button
            Button.backgroundColor({ "id": 50331714, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            // New Terminal primary action button
            Button.fontColor({ "id": 50331707, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            // New Terminal primary action button
            Button.fontSize(16);
            // New Terminal primary action button
            Button.fontWeight(FontWeight.Medium);
            // New Terminal primary action button
            Button.margin({ top: 16 });
            // New Terminal primary action button
            Button.onClick(() => {
                this.createNewSession();
            });
        }, Button);
        // New Terminal primary action button
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Choose Worker secondary action
            Button.createWithLabel('Choose Worker');
            // Choose Worker secondary action
            Button.width('calc(100% - 40vp)');
            // Choose Worker secondary action
            Button.height(48);
            // Choose Worker secondary action
            Button.borderRadius(14);
            // Choose Worker secondary action
            Button.backgroundColor(Color.Transparent);
            // Choose Worker secondary action
            Button.fontColor({ "id": 50331713, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            // Choose Worker secondary action
            Button.fontSize(15);
            // Choose Worker secondary action
            Button.fontWeight(FontWeight.Medium);
            // Choose Worker secondary action
            Button.borderWidth(1);
            // Choose Worker secondary action
            Button.borderColor({ "id": 50331711, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            // Choose Worker secondary action
            Button.margin({ top: 8, bottom: 20 });
            // Choose Worker secondary action
            Button.onClick(() => {
                AppStorage.setOrCreate('navigateTo', 'Workers');
            });
        }, Button);
        // Choose Worker secondary action
        Button.pop();
        Column.pop();
        Scroll.pop();
    }
    SessionCard(session: SessionInfo, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
            Row.padding(14);
            Row.borderRadius(12);
            Row.backgroundColor({ "id": 50331716, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Row.margin({ bottom: 8 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Status chip
            Row.create();
            // Status chip
            Row.padding({ left: 8, right: 8, top: 4, bottom: 4 });
            // Status chip
            Row.borderRadius(8);
            // Status chip
            Row.backgroundColor({ "id": 50331716, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Circle.create();
            Circle.width(8);
            Circle.height(8);
            Circle.fill(this.getStatusColor(session.status));
        }, Circle);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(session.status);
            Text.fontSize(11);
            Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.margin({ left: 6 });
        }, Text);
        Text.pop();
        // Status chip
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Session info
            Column.create();
            // Session info
            Column.alignItems(HorizontalAlign.End);
            // Session info
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
            Text.create(this.formatTime(session.updatedAt));
            Text.fontSize(12);
            Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.margin({ top: 2 });
        }, Text);
        Text.pop();
        // Session info
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Resume button
            Button.createWithLabel('Resume');
            // Resume button
            Button.height(32);
            // Resume button
            Button.borderRadius(8);
            // Resume button
            Button.backgroundColor({ "id": 50331714, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            // Resume button
            Button.fontColor({ "id": 50331707, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            // Resume button
            Button.fontSize(13);
            // Resume button
            Button.margin({ left: 12 });
            // Resume button
            Button.onClick(() => {
                AppStorage.setOrCreate('navSessionId', session.id);
                AppStorage.setOrCreate('navSessionName', session.name || 'Terminal');
                this.pageStack.pushPath({ name: 'TerminalSession' });
            });
        }, Button);
        // Resume button
        Button.pop();
        Row.pop();
    }
    private getStatusColor(status: string): ResourceColor {
        switch (status.toLowerCase()) {
            case 'live':
            case 'connected':
                return { "id": 50331719, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" };
            case 'reconnecting':
            case 'connecting':
                return '#FFC107';
            case 'expired':
                return { "id": 50331704, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" };
            default:
                return { "id": 50331711, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" };
        }
    }
    private formatTime(dateStr: string): string {
        if (!dateStr) {
            return '';
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
            return `${Math.floor(diffMins / 1440)}d ago`;
        }
    }
    private async loadData() {
        this.isLoading = true;
        try {
            const sessions = await this.apiClient.listSessions();
            this.recentSessions = sessions;
            const workers = await this.apiClient.listWorkers();
            this.onlineWorkers = workers.filter(w => w.status === 'online').length;
            this.offlineWorkers = workers.filter(w => w.status !== 'online').length;
        }
        catch (e) {
            console.warn('Failed to load terminal home data: ' + (e as Error).message);
        }
        finally {
            this.isLoading = false;
        }
    }
    private async createNewSession() {
        this.isLoading = true;
        try {
            const request = new SessionCreateRequest();
            request.name = `Terminal ${new Date().toLocaleTimeString()}`;
            const session = await this.apiClient.createSession(request);
            AppStorage.setOrCreate('navSessionId', session.id);
            AppStorage.setOrCreate('navSessionName', session.name);
            this.pageStack.pushPath({ name: 'TerminalSession' });
        }
        catch (e) {
            console.error('Failed to create session: ' + (e as Error).message);
        }
        finally {
            this.isLoading = false;
        }
    }
    rerender() {
        this.updateDirtyElements();
    }
}
