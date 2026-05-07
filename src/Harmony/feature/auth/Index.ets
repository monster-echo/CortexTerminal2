/**
 * @file Index.ets
 * @brief Auth feature HAR export barrel
 *
 * Exports the main AuthComponent and registers it with the
 * navigation router using the wrapBuilder pattern.
 */
export { AuthComponent } from './src/main/ets/AuthComponent'
export { AuthService } from './src/main/ets/service/AuthService'
export type {
  PhoneSendCodeRequest,
  PhoneVerifyRequest,
  PhoneVerifyResponse,
  TokenData,
  UserInfo
} from './src/main/ets/model/AuthModels'
