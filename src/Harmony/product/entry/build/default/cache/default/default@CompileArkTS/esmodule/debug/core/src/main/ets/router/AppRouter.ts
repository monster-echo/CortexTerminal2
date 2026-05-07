/**
 * AppRouter - Centralised navigation singleton.
 *
 * Wraps a HarmonyOS NavPathStack and exposes simple
 * push / pop / clear helpers that any module can import
 * without coupling to a specific Navigation host.
 */
export class AppRouter {
    private static instance: NavPathStack | null = null;
    private constructor() {
        // Singleton - use static methods
    }
    /**
     * Get the shared NavPathStack instance.
     * Lazily creates it on first access.
     */
    static get stack(): NavPathStack {
        if (!AppRouter.instance) {
            AppRouter.instance = new NavPathStack();
        }
        return AppRouter.instance;
    }
    /**
     * Navigate to a named route with an optional parameter.
     *
     * @param name   - Target route name (must match a NavDestination name)
     * @param param  - Optional data to pass to the destination
     */
    static pushName(name: string, param?: Object): void {
        if (param !== undefined) {
            AppRouter.stack.pushPath({ name: name, param: param });
        }
        else {
            AppRouter.stack.pushPath({ name: name });
        }
    }
    /**
     * Go back to the previous page in the stack.
     */
    static pop(): void {
        AppRouter.stack.pop();
    }
    /**
     * Clear the entire navigation stack, returning to the root.
     */
    static clear(): void {
        AppRouter.stack.clear();
    }
}
