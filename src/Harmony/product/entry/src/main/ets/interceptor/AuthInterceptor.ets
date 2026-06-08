/**
 * @file AuthInterceptor.ets
 * @brief Auth route guard — redirects unauthenticated users to login page.
 */
import { DynamicsRouter, Interceptor, InterceptorExecute } from 'routermodule'

export class AuthInterceptorExecute implements InterceptorExecute {
  executeFunction(appUri: string): boolean {
    if (appUri === 'auth/Login' || appUri === 'ActivateWorker') {
      return false
    }
    const isLoggedIn = AppStorage.get<boolean>('isLoggedIn') ?? false
    if (isLoggedIn) {
      return false
    }
    DynamicsRouter.pushUri('auth/Login')
    return true
  }
}
