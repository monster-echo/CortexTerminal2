if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface SettingsPage_Params {
    currentTheme?: string;
    currentLanguage?: string;
    gatewayUrl?: string;
    authToken?: string;
    editedGatewayUrl?: string;
    showGatewayEditor?: boolean;
    appVersion?: string;
    appBuild?: string;
}
export class SettingsPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__currentTheme = new ObservedPropertySimplePU('system', this, "currentTheme");
        this.__currentLanguage = new ObservedPropertySimplePU('en', this, "currentLanguage");
        this.__gatewayUrl = this.createStorageLink('gatewayUrl', '', "gatewayUrl");
        this.__authToken = this.createStorageLink('authToken', '', "authToken");
        this.__editedGatewayUrl = new ObservedPropertySimplePU('', this, "editedGatewayUrl");
        this.__showGatewayEditor = new ObservedPropertySimplePU(false, this, "showGatewayEditor");
        this.appVersion = '1.0.0';
        this.appBuild = '1';
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: SettingsPage_Params) {
        if (params.currentTheme !== undefined) {
            this.currentTheme = params.currentTheme;
        }
        if (params.currentLanguage !== undefined) {
            this.currentLanguage = params.currentLanguage;
        }
        if (params.editedGatewayUrl !== undefined) {
            this.editedGatewayUrl = params.editedGatewayUrl;
        }
        if (params.showGatewayEditor !== undefined) {
            this.showGatewayEditor = params.showGatewayEditor;
        }
        if (params.appVersion !== undefined) {
            this.appVersion = params.appVersion;
        }
        if (params.appBuild !== undefined) {
            this.appBuild = params.appBuild;
        }
    }
    updateStateVars(params: SettingsPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__currentTheme.purgeDependencyOnElmtId(rmElmtId);
        this.__currentLanguage.purgeDependencyOnElmtId(rmElmtId);
        this.__gatewayUrl.purgeDependencyOnElmtId(rmElmtId);
        this.__authToken.purgeDependencyOnElmtId(rmElmtId);
        this.__editedGatewayUrl.purgeDependencyOnElmtId(rmElmtId);
        this.__showGatewayEditor.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__currentTheme.aboutToBeDeleted();
        this.__currentLanguage.aboutToBeDeleted();
        this.__gatewayUrl.aboutToBeDeleted();
        this.__authToken.aboutToBeDeleted();
        this.__editedGatewayUrl.aboutToBeDeleted();
        this.__showGatewayEditor.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __currentTheme: ObservedPropertySimplePU<string>;
    get currentTheme() {
        return this.__currentTheme.get();
    }
    set currentTheme(newValue: string) {
        this.__currentTheme.set(newValue);
    }
    private __currentLanguage: ObservedPropertySimplePU<string>;
    get currentLanguage() {
        return this.__currentLanguage.get();
    }
    set currentLanguage(newValue: string) {
        this.__currentLanguage.set(newValue);
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
    private __editedGatewayUrl: ObservedPropertySimplePU<string>;
    get editedGatewayUrl() {
        return this.__editedGatewayUrl.get();
    }
    set editedGatewayUrl(newValue: string) {
        this.__editedGatewayUrl.set(newValue);
    }
    private __showGatewayEditor: ObservedPropertySimplePU<boolean>;
    get showGatewayEditor() {
        return this.__showGatewayEditor.get();
    }
    set showGatewayEditor(newValue: boolean) {
        this.__showGatewayEditor.set(newValue);
    }
    private appVersion: string;
    private appBuild: string;
    aboutToAppear() {
        this.editedGatewayUrl = this.gatewayUrl;
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
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Header
            Text.create('Settings');
            // Header
            Text.fontSize(24);
            // Header
            Text.fontWeight(FontWeight.Bold);
            // Header
            Text.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            // Header
            Text.width('100%');
            // Header
            Text.padding({ left: 20, top: 16, bottom: 16 });
        }, Text);
        // Header
        Text.pop();
        // Appearance section
        this.SectionHeader.bind(this)('Appearance');
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Theme selector
            Row.create();
            // Theme selector
            Row.width('calc(100% - 40vp)');
            // Theme selector
            Row.padding(14);
            // Theme selector
            Row.borderRadius(12);
            // Theme selector
            Row.backgroundColor({ "id": 50331716, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            // Theme selector
            Row.margin({ bottom: 8 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Theme');
            Text.fontSize(14);
            Text.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.layoutWeight(1);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
        }, Row);
        this.ThemeOption.bind(this)('Light', this.currentTheme === 'light');
        this.ThemeOption.bind(this)('Dark', this.currentTheme === 'dark');
        this.ThemeOption.bind(this)('System', this.currentTheme === 'system');
        Row.pop();
        // Theme selector
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Language selector
            Row.create();
            // Language selector
            Row.width('calc(100% - 40vp)');
            // Language selector
            Row.padding(14);
            // Language selector
            Row.borderRadius(12);
            // Language selector
            Row.backgroundColor({ "id": 50331716, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            // Language selector
            Row.margin({ bottom: 8 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Language');
            Text.fontSize(14);
            Text.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.layoutWeight(1);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
        }, Row);
        this.LanguageOption.bind(this)('English', 'en');
        this.LanguageOption.bind(this)('Chinese', 'zh');
        Row.pop();
        // Language selector
        Row.pop();
        // Connection section
        this.SectionHeader.bind(this)('Connection');
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Gateway URL
            Column.create();
            // Gateway URL
            Column.width('calc(100% - 40vp)');
            // Gateway URL
            Column.padding(14);
            // Gateway URL
            Column.borderRadius(12);
            // Gateway URL
            Column.backgroundColor({ "id": 50331716, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            // Gateway URL
            Column.margin({ bottom: 8 });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Gateway URL');
            Text.fontSize(14);
            Text.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.layoutWeight(1);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.showGatewayEditor ? 'Done' : 'Edit');
            Text.fontSize(14);
            Text.fontColor({ "id": 50331713, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.onClick(() => {
                if (this.showGatewayEditor) {
                    this.gatewayUrl = this.editedGatewayUrl;
                }
                this.showGatewayEditor = !this.showGatewayEditor;
            });
        }, Text);
        Text.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.gatewayUrl || 'https://gateway.ct.rwecho.top');
            Text.fontSize(13);
            Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.margin({ top: 4 });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.showGatewayEditor) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        TextInput.create({ text: this.editedGatewayUrl, placeholder: 'https://...' });
                        TextInput.width('100%');
                        TextInput.height(44);
                        TextInput.borderRadius(8);
                        TextInput.backgroundColor({ "id": 50331716, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        TextInput.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        TextInput.margin({ top: 8 });
                        TextInput.onChange((value: string) => {
                            this.editedGatewayUrl = value;
                        });
                    }, TextInput);
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        // Gateway URL
        Column.pop();
        // Account section
        this.SectionHeader.bind(this)('Account');
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Logout button
            Button.createWithLabel('Sign Out');
            // Logout button
            Button.width('calc(100% - 40vp)');
            // Logout button
            Button.height(48);
            // Logout button
            Button.borderRadius(12);
            // Logout button
            Button.backgroundColor({ "id": 50331704, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            // Logout button
            Button.fontColor(Color.White);
            // Logout button
            Button.fontSize(16);
            // Logout button
            Button.fontWeight(FontWeight.Medium);
            // Logout button
            Button.margin({ top: 8 });
            // Logout button
            Button.onClick(() => {
                this.authToken = '';
                AppStorage.setOrCreate('isLoggedIn', false);
            });
        }, Button);
        // Logout button
        Button.pop();
        // About section
        this.SectionHeader.bind(this)('About');
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Version info
            Column.create();
            // Version info
            Column.width('calc(100% - 40vp)');
            // Version info
            Column.padding(14);
            // Version info
            Column.borderRadius(12);
            // Version info
            Column.backgroundColor({ "id": 50331716, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            // Version info
            Column.margin({ bottom: 8 });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Version');
            Text.fontSize(14);
            Text.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.layoutWeight(1);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`${this.appVersion} (${this.appBuild})`);
            Text.fontSize(14);
            Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Text);
        Text.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
            Row.margin({ top: 4 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('CortexTerminal');
            Text.fontSize(12);
            Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.layoutWeight(1);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('HarmonyOS NEXT');
            Text.fontSize(12);
            Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Text);
        Text.pop();
        Row.pop();
        // Version info
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.height(40);
        }, Blank);
        Blank.pop();
        Column.pop();
        Scroll.pop();
    }
    SectionHeader(title: string, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(title);
            Text.fontSize(13);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor({ "id": 50331713, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.textCase(TextCase.UpperCase);
            Text.width('calc(100% - 40vp)');
            Text.margin({ top: 20, bottom: 8 });
        }, Text);
        Text.pop();
    }
    ThemeOption(label: string, selected: boolean, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(label);
            Text.fontSize(13);
            Text.fontWeight(selected ? FontWeight.Medium : FontWeight.Normal);
            Text.fontColor(selected ? { "id": 50331707, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" } : { "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.padding({ left: 12, right: 12, top: 6, bottom: 6 });
            Text.borderRadius(8);
            Text.backgroundColor(selected ? { "id": 50331714, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" } :
                Color.Transparent);
            Text.onClick(() => {
                this.currentTheme = label.toLowerCase();
                this.applyTheme(this.currentTheme);
            });
        }, Text);
        Text.pop();
    }
    LanguageOption(label: string, code: string, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(label);
            Text.fontSize(13);
            Text.fontWeight(this.currentLanguage === code ? FontWeight.Medium : FontWeight.Normal);
            Text.fontColor(this.currentLanguage === code ? { "id": 50331707, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" } : { "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.padding({ left: 12, right: 12, top: 6, bottom: 6 });
            Text.borderRadius(8);
            Text.backgroundColor(this.currentLanguage === code ? { "id": 50331714, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" } :
                Color.Transparent);
            Text.onClick(() => {
                this.currentLanguage = code;
                AppStorage.setOrCreate('language', code);
            });
        }, Text);
        Text.pop();
    }
    private applyTheme(theme: string) {
        AppStorage.setOrCreate('themeMode', theme);
        // The EntryAbility will pick up the change via Configuration
    }
    rerender() {
        this.updateDirtyElements();
    }
}
