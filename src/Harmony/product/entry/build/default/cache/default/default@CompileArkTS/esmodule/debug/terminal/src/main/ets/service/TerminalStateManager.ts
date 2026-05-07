import { TerminalState } from "@bundle:top.rwecho.cortexterminal/entry@terminal/ets/model/TerminalState";
/**
 * Callback type for state change notifications.
 */
type OnStateChangedCallback = (state: TerminalState) => void;
/**
 * State machine for terminal session lifecycle.
 * Tracks the current connection state and validates transitions.
 */
export class TerminalStateManager {
    private get storedState(): string { return AppStorage.get<string>('terminalState') || TerminalState[TerminalState.Disconnected]; }
    private set storedState(value: string) { AppStorage.setOrCreate('terminalState', value); }
    // Current state
    private state: TerminalState = TerminalState.Disconnected;
    // Callback for UI state changes
    onStateChanged: OnStateChangedCallback | null = null;
    /**
     * Get the current terminal state.
     */
    getState(): TerminalState {
        return this.state;
    }
    /**
     * Set the terminal state. Validates the transition before applying.
     * @param newState The new state to transition to
     */
    setState(newState: TerminalState): void {
        if (!this.isValidTransition(this.state, newState)) {
            console.warn(`Invalid state transition: ${TerminalState[this.state]} -> ${TerminalState[newState]}`);
            return;
        }
        const oldState = this.state;
        this.state = newState;
        // Persist to AppStorage for cross-component access
        this.storedState = TerminalState[newState];
        // Notify listeners
        if (this.onStateChanged) {
            this.onStateChanged(newState);
        }
        console.info(`Terminal state: ${TerminalState[oldState]} -> ${TerminalState[newState]}`);
    }
    /**
     * Check if the terminal is in an active (connected) state.
     */
    isActive(): boolean {
        return this.state === TerminalState.Live ||
            this.state === TerminalState.Replaying ||
            this.state === TerminalState.Connecting ||
            this.state === TerminalState.Reconnecting;
    }
    /**
     * Check if the terminal is in a terminal (non-recoverable) state.
     */
    isTerminal(): boolean {
        return this.state === TerminalState.Expired ||
            this.state === TerminalState.Exited ||
            this.state === TerminalState.Error;
    }
    /**
     * Reset to disconnected state.
     */
    reset(): void {
        this.state = TerminalState.Disconnected;
        this.storedState = TerminalState[TerminalState.Disconnected];
        if (this.onStateChanged) {
            this.onStateChanged(TerminalState.Disconnected);
        }
    }
    /**
     * Validate that a state transition is allowed.
     */
    private isValidTransition(from: TerminalState, to: TerminalState): boolean {
        // All transitions to Error are valid
        if (to === TerminalState.Error) {
            return true;
        }
        // Valid transition map
        const validTransitions = new Map<TerminalState, Set<TerminalState>>();
        validTransitions.set(TerminalState.Disconnected, new Set<TerminalState>([
            TerminalState.Connecting
        ]));
        validTransitions.set(TerminalState.Connecting, new Set<TerminalState>([
            TerminalState.Live,
            TerminalState.Replaying,
            TerminalState.Reconnecting,
            TerminalState.Disconnected,
            TerminalState.Error
        ]));
        validTransitions.set(TerminalState.Replaying, new Set<TerminalState>([
            TerminalState.Live,
            TerminalState.Reconnecting,
            TerminalState.Error
        ]));
        validTransitions.set(TerminalState.Live, new Set<TerminalState>([
            TerminalState.Reconnecting,
            TerminalState.Detached,
            TerminalState.Expired,
            TerminalState.Exited,
            TerminalState.Disconnected,
            TerminalState.Error
        ]));
        validTransitions.set(TerminalState.Reconnecting, new Set<TerminalState>([
            TerminalState.Live,
            TerminalState.Replaying,
            TerminalState.Disconnected,
            TerminalState.Error
        ]));
        validTransitions.set(TerminalState.Detached, new Set<TerminalState>([
            TerminalState.Connecting,
            TerminalState.Disconnected
        ]));
        validTransitions.set(TerminalState.Expired, new Set<TerminalState>([
            TerminalState.Disconnected
        ]));
        validTransitions.set(TerminalState.Exited, new Set<TerminalState>([
            TerminalState.Disconnected
        ]));
        validTransitions.set(TerminalState.Error, new Set<TerminalState>([
            TerminalState.Connecting,
            TerminalState.Disconnected
        ]));
        const allowed = validTransitions.get(from);
        if (!allowed) {
            return false;
        }
        return allowed.has(to);
    }
}
