/**
 * @file DynamicsRouter.ets
 * @brief Dynamic router core — manages NavPathStack, lazy module import, and interceptor checks.
 *
 * Usage:
 *   DynamicsRouter.routerInit(config, context)          // in EntryAbility.onCreate
 *   DynamicsRouter.pushUri('auth/Login', param)          // navigate with interceptor check
 *   DynamicsRouter.navPathStack                          // bind to Navigation
 */
import { Interceptor } from '../interceptor/Interceptor'
import { AppRouterInfo } from '../model/AppRouterInfo'
import { RouterLoader } from '../util/RouterLoader'

interface RouterInitConfig {
  libPrefix: string
  mapPath: string
}

type BuilderFunction = (param: ESObject) => void

interface WrappedBuilderRef {
  builder: BuilderFunction
}

@Component
struct EmptyBuilder {
  build() {
    Column() {}
  }
}

export class DynamicsRouter {
  private static TAG = '[DynamicsRouter]'
  static navPathStack: NavPathStack = new NavPathStack()
  private static builderMap: Record<string, WrappedBuilderRef> = {}
  private static appRouterStack: string[] = []
  private static initialized: boolean = false

  static async routerInit(config: RouterInitConfig, context: Context): Promise<void> {
    if (DynamicsRouter.initialized) {
      return
    }
    DynamicsRouter.initialized = true
    await RouterLoader.load(context, config.mapPath)
    console.info(`${DynamicsRouter.TAG} Router initialized`)
  }

  static registerBuilder(name: string, wrappedBuilder: WrappedBuilderRef): void {
    DynamicsRouter.builderMap[name] = wrappedBuilder
  }

  static getBuilder(name: string): WrappedBuilderRef {
    const builder = DynamicsRouter.builderMap[name]
    if (!builder) {
      console.warn(`${DynamicsRouter.TAG} No builder registered for: ${name}`)
      return DynamicsRouter.emptyBuilder()
    }
    return builder
  }

  static pushUri(name: string, param?: Object): void {
    if (Interceptor.interceptor(name)) {
      return
    }
    DynamicsRouter.appRouterStack.push(name)
    DynamicsRouter.navPathStack.pushPath({ name: name, param: param })
  }

  static replaceUri(name: string, param?: Object): void {
    if (Interceptor.interceptor(name)) {
      return
    }
    DynamicsRouter.navPathStack.replacePath({ name: name, param: param })
  }

  static popAppRouter(): void {
    if (DynamicsRouter.appRouterStack.length > 0) {
      DynamicsRouter.appRouterStack.pop()
    }
    DynamicsRouter.navPathStack.pop()
  }

  static clear(): void {
    DynamicsRouter.appRouterStack = []
    DynamicsRouter.navPathStack.clear()
  }

  static getStack(): string[] {
    return DynamicsRouter.appRouterStack
  }

  private static emptyBuilder(): WrappedBuilderRef {
    const emptyWrap: WrappedBuilderRef = {
      builder: (_param: ESObject) => {}
    }
    return emptyWrap
  }
}
