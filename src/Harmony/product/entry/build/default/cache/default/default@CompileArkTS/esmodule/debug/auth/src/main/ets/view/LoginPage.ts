if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface LoginPage_Params {
    phoneNumber?: string;
    verifyCode?: string;
    codeSent?: boolean;
    isLoading?: boolean;
    errorMessage?: string;
    countdown?: number;
    quickLoginAnonymousPhone?: string;
    huaweiLoginAvailable?: boolean;
    authService?: AuthService;
    countdownTimer?: number;
    huaweiButtonController?: loginComponentManager.LoginWithHuaweiIDButtonController;
}
import { AuthService } from "@bundle:top.rwecho.cortexterminal/entry@auth/ets/service/AuthService";
import authentication from "@hms:core.authentication";
import { loginComponentManager } from "@hms:core.account.LoginComponent";
import { LoginWithHuaweiIDButton } from "@hms:core.account.LoginComponent";
import type { BusinessError } from "@ohos:base";
import util from "@ohos:util";
export class LoginPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__phoneNumber = new ObservedPropertySimplePU('', this, "phoneNumber");
        this.__verifyCode = new ObservedPropertySimplePU('', this, "verifyCode");
        this.__codeSent = new ObservedPropertySimplePU(false, this, "codeSent");
        this.__isLoading = new ObservedPropertySimplePU(false, this, "isLoading");
        this.__errorMessage = new ObservedPropertySimplePU('', this, "errorMessage");
        this.__countdown = new ObservedPropertySimplePU(0, this, "countdown");
        this.__quickLoginAnonymousPhone = new ObservedPropertySimplePU('', this, "quickLoginAnonymousPhone");
        this.__huaweiLoginAvailable = new ObservedPropertySimplePU(false, this, "huaweiLoginAvailable");
        this.authService = new AuthService();
        this.countdownTimer = -1;
        this.huaweiButtonController = new loginComponentManager.LoginWithHuaweiIDButtonController()
            .setAgreementStatus(loginComponentManager.AgreementStatus.ACCEPTED)
            .onClickLoginWithHuaweiIDButton((error: BusinessError | undefined, response: loginComponentManager.HuaweiIDCredential) => {
            console.info(`Huawei login callback: error=${JSON.stringify(error)}, response=${JSON.stringify(response)}`);
            if (error) {
                console.error(`Huawei login failed: code=${error.code}, message=${error.message}`);
                if (error.code !== 1001502012 && error.code !== 1001502001) {
                    this.errorMessage = `Huawei login failed (${error.code})`;
                }
                return;
            }
            if (response) {
                const authCode = response.authorizationCode ?? '';
                const openID = response.openID ?? '';
                const unionID = response.unionID ?? '';
                console.info(`Huawei login: authCode=${authCode.substring(0, 10)}..., openID=${openID}, unionID=${unionID}`);
                if (authCode.length === 0) {
                    this.errorMessage = 'Failed to get authorization code';
                    return;
                }
                this.handleHuaweiLogin(authCode, unionID, openID);
            }
            else {
                console.warn('Huawei login: response is null, no action taken');
            }
        });
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: LoginPage_Params) {
        if (params.phoneNumber !== undefined) {
            this.phoneNumber = params.phoneNumber;
        }
        if (params.verifyCode !== undefined) {
            this.verifyCode = params.verifyCode;
        }
        if (params.codeSent !== undefined) {
            this.codeSent = params.codeSent;
        }
        if (params.isLoading !== undefined) {
            this.isLoading = params.isLoading;
        }
        if (params.errorMessage !== undefined) {
            this.errorMessage = params.errorMessage;
        }
        if (params.countdown !== undefined) {
            this.countdown = params.countdown;
        }
        if (params.quickLoginAnonymousPhone !== undefined) {
            this.quickLoginAnonymousPhone = params.quickLoginAnonymousPhone;
        }
        if (params.huaweiLoginAvailable !== undefined) {
            this.huaweiLoginAvailable = params.huaweiLoginAvailable;
        }
        if (params.authService !== undefined) {
            this.authService = params.authService;
        }
        if (params.countdownTimer !== undefined) {
            this.countdownTimer = params.countdownTimer;
        }
        if (params.huaweiButtonController !== undefined) {
            this.huaweiButtonController = params.huaweiButtonController;
        }
    }
    updateStateVars(params: LoginPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__phoneNumber.purgeDependencyOnElmtId(rmElmtId);
        this.__verifyCode.purgeDependencyOnElmtId(rmElmtId);
        this.__codeSent.purgeDependencyOnElmtId(rmElmtId);
        this.__isLoading.purgeDependencyOnElmtId(rmElmtId);
        this.__errorMessage.purgeDependencyOnElmtId(rmElmtId);
        this.__countdown.purgeDependencyOnElmtId(rmElmtId);
        this.__quickLoginAnonymousPhone.purgeDependencyOnElmtId(rmElmtId);
        this.__huaweiLoginAvailable.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__phoneNumber.aboutToBeDeleted();
        this.__verifyCode.aboutToBeDeleted();
        this.__codeSent.aboutToBeDeleted();
        this.__isLoading.aboutToBeDeleted();
        this.__errorMessage.aboutToBeDeleted();
        this.__countdown.aboutToBeDeleted();
        this.__quickLoginAnonymousPhone.aboutToBeDeleted();
        this.__huaweiLoginAvailable.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __phoneNumber: ObservedPropertySimplePU<string>;
    get phoneNumber() {
        return this.__phoneNumber.get();
    }
    set phoneNumber(newValue: string) {
        this.__phoneNumber.set(newValue);
    }
    private __verifyCode: ObservedPropertySimplePU<string>;
    get verifyCode() {
        return this.__verifyCode.get();
    }
    set verifyCode(newValue: string) {
        this.__verifyCode.set(newValue);
    }
    private __codeSent: ObservedPropertySimplePU<boolean>;
    get codeSent() {
        return this.__codeSent.get();
    }
    set codeSent(newValue: boolean) {
        this.__codeSent.set(newValue);
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
    private __countdown: ObservedPropertySimplePU<number>;
    get countdown() {
        return this.__countdown.get();
    }
    set countdown(newValue: number) {
        this.__countdown.set(newValue);
    }
    private __quickLoginAnonymousPhone: ObservedPropertySimplePU<string>;
    get quickLoginAnonymousPhone() {
        return this.__quickLoginAnonymousPhone.get();
    }
    set quickLoginAnonymousPhone(newValue: string) {
        this.__quickLoginAnonymousPhone.set(newValue);
    }
    private __huaweiLoginAvailable: ObservedPropertySimplePU<boolean>;
    get huaweiLoginAvailable() {
        return this.__huaweiLoginAvailable.get();
    }
    set huaweiLoginAvailable(newValue: boolean) {
        this.__huaweiLoginAvailable.set(newValue);
    }
    private authService: AuthService;
    private countdownTimer: number;
    // Huawei login button controller
    private huaweiButtonController: loginComponentManager.LoginWithHuaweiIDButtonController;
    aboutToAppear() {
        this.tryGetAnonymousPhone();
    }
    aboutToDisappear() {
        if (this.countdownTimer !== -1) {
            clearInterval(this.countdownTimer);
        }
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.width('100%');
            Column.height('100%');
            Column.backgroundColor({ "id": 50331715, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Logo and title
            Column.create();
            // Logo and title
            Column.width('100%');
            // Logo and title
            Column.alignItems(HorizontalAlign.Center);
            // Logo and title
            Column.margin({ top: 60 });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 50331648, "type": 10003, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.fontSize(28);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Connect to your terminal anywhere');
            Text.fontSize(14);
            Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.margin({ top: 8 });
        }, Text);
        Text.pop();
        // Logo and title
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // Huawei one-click login section
            if (true) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create();
                        Column.width('100%');
                        Column.alignItems(HorizontalAlign.Center);
                        Column.padding({ left: 24, right: 24 });
                        Column.margin({ top: 32 });
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(`Huawei Account: ${this.quickLoginAnonymousPhone}`);
                        Text.fontSize(14);
                        Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        Text.margin({ bottom: 16 });
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        __Common__.create();
                        __Common__.width('100%');
                        __Common__.height(48);
                        __Common__.constraintSize({ maxWidth: 400 });
                    }, __Common__);
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new LoginWithHuaweiIDButton(this, {
                                    params: {
                                        style: loginComponentManager.Style.BUTTON_RED,
                                        loginType: loginComponentManager.LoginType.QUICK_LOGIN,
                                        borderRadius: 24,
                                        supportDarkMode: true
                                    },
                                    controller: this.huaweiButtonController
                                }, undefined, elmtId, () => { }, { page: "feature/auth/src/main/ets/view/LoginPage.ets", line: 93, col: 11 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {
                                        params: {
                                            style: loginComponentManager.Style.BUTTON_RED,
                                            loginType: loginComponentManager.LoginType.QUICK_LOGIN,
                                            borderRadius: 24,
                                            supportDarkMode: true
                                        },
                                        controller: this.huaweiButtonController
                                    };
                                };
                                componentCall.paramsGenerator_ = paramsLambda;
                            }
                            else {
                                this.updateStateVarsOfChildByElmtId(elmtId, {});
                            }
                        }, { name: "LoginWithHuaweiIDButton" });
                    }
                    __Common__.pop();
                    Column.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        // Divider
                        Row.create();
                        // Divider
                        Row.width('calc(100% - 48vp)');
                        // Divider
                        Row.margin({ top: 24, bottom: 8 });
                    }, Row);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Divider.create();
                        Divider.layoutWeight(1);
                        Divider.color({ "id": 50331711, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                    }, Divider);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(' or ');
                        Text.fontSize(13);
                        Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Divider.create();
                        Divider.layoutWeight(1);
                        Divider.color({ "id": 50331711, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                    }, Divider);
                    // Divider
                    Row.pop();
                });
            }
            // Phone number input
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Phone number input
            Column.create();
            // Phone number input
            Column.width('100%');
            // Phone number input
            Column.padding({ left: 24, right: 24 });
            // Phone number input
            Column.margin({ top: 24 });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Phone Number');
            Text.fontSize(14);
            Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            Text.width('100%');
            Text.margin({ bottom: 8 });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TextInput.create({ placeholder: '13800138000', text: this.phoneNumber });
            TextInput.type(InputType.PhoneNumber);
            TextInput.maxLength(11);
            TextInput.width('100%');
            TextInput.height(48);
            TextInput.borderRadius(12);
            TextInput.backgroundColor({ "id": 50331716, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            TextInput.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            TextInput.placeholderColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            TextInput.onChange((value: string) => {
                this.phoneNumber = value;
                this.errorMessage = '';
            });
        }, TextInput);
        // Phone number input
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // Verification code input (shown after code sent)
            if (this.codeSent) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create();
                        Column.width('100%');
                        Column.padding({ left: 24, right: 24 });
                        Column.margin({ top: 16 });
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('Verification Code');
                        Text.fontSize(14);
                        Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        Text.width('100%');
                        Text.margin({ bottom: 8 });
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Row.create();
                        Row.width('100%');
                    }, Row);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        TextInput.create({ placeholder: '6-digit code', text: this.verifyCode });
                        TextInput.type(InputType.Number);
                        TextInput.maxLength(6);
                        TextInput.width('100%');
                        TextInput.height(48);
                        TextInput.borderRadius(12);
                        TextInput.backgroundColor({ "id": 50331716, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        TextInput.fontColor({ "id": 50331712, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        TextInput.placeholderColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        TextInput.onChange((value: string) => {
                            this.verifyCode = value;
                            this.errorMessage = '';
                        });
                    }, TextInput);
                    Row.pop();
                    Column.pop();
                });
            }
            // Error message
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
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
            // Primary action button
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Primary action button
            Button.createWithLabel(this.codeSent ? 'Verify & Login' : 'Send Verification Code');
            // Primary action button
            Button.width('calc(100% - 48vp)');
            // Primary action button
            Button.height(48);
            // Primary action button
            Button.margin({ top: 24 });
            // Primary action button
            Button.borderRadius(12);
            // Primary action button
            Button.backgroundColor({ "id": 50331714, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            // Primary action button
            Button.fontColor('#ffffff');
            // Primary action button
            Button.fontSize(16);
            // Primary action button
            Button.fontWeight(FontWeight.Medium);
            // Primary action button
            Button.enabled(!this.isLoading && this.phoneNumber.length === 11 &&
                (!this.codeSent || this.verifyCode.length >= 6));
            // Primary action button
            Button.onClick(() => {
                this.handlePrimaryAction();
            });
        }, Button);
        // Primary action button
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // Countdown / resend
            if (this.countdown > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(`Resend in ${this.countdown}s`);
                        Text.fontSize(13);
                        Text.fontColor({ "id": 50331709, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        Text.margin({ top: 12 });
                    }, Text);
                    Text.pop();
                });
            }
            else if (this.codeSent) {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('Resend Code');
                        Text.fontSize(13);
                        Text.fontColor({ "id": 50331713, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
                        Text.margin({ top: 12 });
                        Text.onClick(() => {
                            this.sendCode();
                        });
                    }, Text);
                    Text.pop();
                });
            }
            // Guest login
            else {
                this.ifElseBranchUpdateFunction(2, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Guest login
            Button.createWithLabel('Try as Guest');
            // Guest login
            Button.width('calc(100% - 48vp)');
            // Guest login
            Button.height(48);
            // Guest login
            Button.margin({ top: 24 });
            // Guest login
            Button.borderRadius(12);
            // Guest login
            Button.backgroundColor(Color.Transparent);
            // Guest login
            Button.fontColor({ "id": 50331713, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            // Guest login
            Button.fontSize(16);
            // Guest login
            Button.fontWeight(FontWeight.Medium);
            // Guest login
            Button.borderWidth(1);
            // Guest login
            Button.borderColor({ "id": 50331711, "type": 10001, params: [], "bundleName": "top.rwecho.cortexterminal", "moduleName": "entry" });
            // Guest login
            Button.enabled(!this.isLoading);
            // Guest login
            Button.onClick(() => {
                this.guestLogin();
            });
        }, Button);
        // Guest login
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
        }, Blank);
        Blank.pop();
        Column.pop();
    }
    /**
     * Try to silently get the masked phone number from Huawei Account Kit.
     * If available, show the one-click login button.
     */
    private async tryGetAnonymousPhone() {
        try {
            const huaweiIDProvider = new authentication.HuaweiIDProvider();
            const authRequest = huaweiIDProvider.createAuthorizationWithHuaweiIDRequest();
            authRequest.scopes = ['quickLoginAnonymousPhone'];
            authRequest.state = util.generateRandomUUID();
            authRequest.forceAuthorization = false;
            const controller = new authentication.AuthenticationController();
            const response: authentication.AuthorizationWithHuaweiIDResponse = await controller.executeRequest(authRequest);
            const anonymousPhone = response.data?.extraInfo?.quickLoginAnonymousPhone as string;
            if (anonymousPhone && anonymousPhone.length > 0) {
                this.quickLoginAnonymousPhone = anonymousPhone;
                console.info(`Huawei quick login available: ${anonymousPhone}`);
            }
            // Huawei account exists — show the button regardless of anonymous phone
            this.huaweiLoginAvailable = true;
        }
        catch (error) {
            const err = error as BusinessError;
            // Not logged in to Huawei or not supported — silently fall back to phone login
            console.info(`Huawei quick login not available: code=${err.code}`);
            this.huaweiLoginAvailable = false;
        }
    }
    /**
     * Handle Huawei one-click login by sending authCode to the gateway.
     */
    private async handleHuaweiLogin(authCode: string, unionID: string, openID: string) {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            await this.authService.loginWithHuaweiAuthCode(authCode, unionID, openID);
            this.isLoading = false;
            this.authService.completeAuth();
        }
        catch (err) {
            this.errorMessage = (err as Error).message || 'Huawei login failed';
            this.isLoading = false;
        }
    }
    private guestLogin() {
        if (this.isLoading) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = '';
        this.authService.loginAsGuest().then(() => {
            this.isLoading = false;
            this.authService.completeAuth();
        }).catch((err: Error) => {
            this.errorMessage = err.message || 'Guest login failed';
            this.isLoading = false;
        });
    }
    private handlePrimaryAction() {
        if (!this.codeSent) {
            this.sendCode();
        }
        else {
            this.verifyAndLogin();
        }
    }
    private sendCode() {
        if (this.phoneNumber.length !== 11 || this.isLoading) {
            if (this.phoneNumber.length !== 11) {
                this.errorMessage = 'Please enter an 11-digit phone number';
            }
            return;
        }
        this.isLoading = true;
        this.errorMessage = '';
        this.authService.sendVerificationCode(this.phoneNumber).then(() => {
            this.codeSent = true;
            this.isLoading = false;
            this.startCountdown();
        }).catch((err: Error) => {
            this.errorMessage = err.message || 'Failed to send verification code';
            this.isLoading = false;
        });
    }
    private verifyAndLogin() {
        if (this.verifyCode.length < 6 || this.isLoading) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = '';
        this.authService.login(this.phoneNumber, this.verifyCode).then(() => {
            this.isLoading = false;
            this.authService.completeAuth();
        }).catch((err: Error) => {
            this.errorMessage = err.message || 'Verification failed';
            this.isLoading = false;
        });
    }
    private startCountdown() {
        this.countdown = 60;
        this.countdownTimer = setInterval(() => {
            this.countdown--;
            if (this.countdown <= 0) {
                clearInterval(this.countdownTimer);
                this.countdownTimer = -1;
            }
        }, 1000) as number;
    }
    rerender() {
        this.updateDirtyElements();
    }
}
