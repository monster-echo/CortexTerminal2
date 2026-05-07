/**
 * @file NetworkMonitor.ets
 * @brief Network connectivity monitor using @ohos.net.connection
 *
 * Monitors network status changes and notifies listeners when
 * connectivity is gained or lost. Used by the terminal transport
 * layer to trigger reconnection attempts.
 */
import { connection } from '@kit.NetworkKit'

/**
 * Callback type for network state changes.
 */
type OnNetworkChangeCallback = (connected: boolean, type: string) => void

/**
 * Network connectivity monitor.
 * Uses @ohos.net.connection to detect network changes.
 */
export class NetworkMonitor {
  private networkAvailable: boolean = true
  private storedNetworkType: string = 'unknown'

  private netConnection: connection.NetConnection | null = null
  private listeners: OnNetworkChangeCallback[] = []

  /**
   * Start monitoring network connectivity.
   */
  start(): void {
    this.netConnection = connection.createNetConnection()

    // Register for default network availability
    this.netConnection.register(() => {
      console.info('NetworkMonitor: registered')
    })

    // Handle network available
    this.netConnection.on('netAvailable', (data: connection.NetHandle) => {
      console.info('NetworkMonitor: network available')
      this.networkAvailable = true
      this.notifyListeners(true, 'available')
    })

    // Handle network lost
    this.netConnection.on('netLost', (data: connection.NetHandle) => {
      console.info('NetworkMonitor: network lost')
      this.networkAvailable = false
      this.notifyListeners(false, 'lost')
    })

    // Handle network capabilities change
    this.netConnection.on('netCapabilitiesChange', (data: connection.NetCapabilityInfo) => {
      const caps = data.netCap
      let type = 'unknown'
      if (caps.bearerTypes.includes(connection.NetBearType.BEARER_CELLULAR)) {
        type = 'cellular'
      } else if (caps.bearerTypes.includes(connection.NetBearType.BEARER_WIFI)) {
        type = 'wifi'
      } else if (caps.bearerTypes.includes(connection.NetBearType.BEARER_ETHERNET)) {
        type = 'ethernet'
      }
      this.storedNetworkType = type
      this.notifyListeners(this.networkAvailable, type)
    })

    // Check initial state
    this.checkInitialState()
  }

  /**
   * Stop monitoring network connectivity.
   */
  stop(): void {
    if (this.netConnection) {
      this.netConnection.unregister(() => {
        console.info('NetworkMonitor: unregistered')
      })
      this.netConnection = null
    }
    this.listeners = []
  }

  /**
   * Check if network is currently available.
   */
  isAvailable(): boolean {
    return this.networkAvailable
  }

  /**
   * Get the current network type.
   */
  getNetworkType(): string {
    return this.storedNetworkType
  }

  /**
   * Register a listener for network state changes.
   * @param callback Function to call when network state changes
   */
  addListener(callback: OnNetworkChangeCallback): void {
    this.listeners.push(callback)
  }

  /**
   * Remove a previously registered listener.
   */
  removeListener(callback: OnNetworkChangeCallback): void {
    const index = this.listeners.indexOf(callback)
    if (index !== -1) {
      this.listeners.splice(index, 1)
    }
  }

  /**
   * Notify all registered listeners of a state change.
   */
  private notifyListeners(connected: boolean, type: string): void {
    for (const listener of this.listeners) {
      listener(connected, type)
    }
  }

  /**
   * Check the initial network state synchronously.
   */
  private checkInitialState(): void {
    try {
      const hasDefault = connection.hasDefaultNetSync()
      this.networkAvailable = hasDefault
      this.notifyListeners(hasDefault, this.storedNetworkType)
    } catch (e) {
      console.warn('Failed to check initial network state: ' + (e as Error).message)
    }
  }
}
