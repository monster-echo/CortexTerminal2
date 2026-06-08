/**
 * @file Interceptor.ets
 * @brief Route interceptor chain-of-responsibility framework.
 *
 * Usage:
 *   1. Implement InterceptorExecute
 *   2. Register via Interceptor.registerInterceptorPage(instance)
 *   3. DynamicsRouter.pushUri() calls Interceptor.interceptor() before navigation
 */

export interface InterceptorExecute {
  executeFunction(appUri: string): boolean
}

export class Interceptor {
  private static list: Array<InterceptorExecute> = []

  static registerInterceptorPage(interceptorFnc: InterceptorExecute): void {
    Interceptor.list.push(interceptorFnc)
  }

  static interceptor(appUri: string): boolean {
    for (let i = 0; i < Interceptor.list.length; i++) {
      if (Interceptor.list[i].executeFunction(appUri)) {
        return true
      }
    }
    return false
  }
}
