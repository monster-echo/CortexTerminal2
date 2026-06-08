/**
 * HapticUtils — lightweight haptic feedback wrapper.
 *
 * Three effect levels using @kit.SensorServiceKit vibrator.
 * All calls are fire-and-forget with try-catch; some devices
 * may not support preset haptic effects.
 */
import { vibrator } from '@kit.SensorServiceKit'

export function lightHaptic(): void {
  try {
    vibrator.startVibration(
      { type: 'preset', effectId: 'haptic.effect.soft' },
      { usage: 'touch' }
    )
  } catch (_e) {
    // Haptic not supported on this device
  }
}

export function clickHaptic(): void {
  try {
    vibrator.startVibration(
      { type: 'preset', effectId: 'haptic.effect.sharp' },
      { usage: 'touch' }
    )
  } catch (_e) {
    // Haptic not supported on this device
  }
}

export function heavyHaptic(): void {
  try {
    vibrator.startVibration(
      { type: 'preset', effectId: 'haptic.effect.hard' },
      { usage: 'touch' }
    )
  } catch (_e) {
    // Haptic not supported on this device
  }
}
