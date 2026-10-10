/**
 * @file P2pCrypto.ets
 * @brief P2P 数据面加密：HKDF-SHA256 会话密钥 + AES-256-GCM 包封（规格 §3）。
 *
 * 会话密钥：key = HKDF-SHA256(ikm = RelayToken 原文, salt = transferId, info = "corterm-p2p-v1", L=32)。
 * HKDF 手写实现（cryptoFramework Mac('SHA256') 提供 HMAC 原语，extract+expand 逐块），
 * 与 Worker/Dart 端保持字节级一致。AES-256-GCM 用 cipher + GcmParamsSpec（Api 12+）。
 *
 * UDP 包格式：[1B version=0x01][12B nonce][ciphertext+16B tag]
 * nonce = 4B 随机（每连接一次）+ 8B 大端计数器（每方向独立从 0 递增）；AAD = 空。
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { util } from '@kit.ArkTS'
import { P2pRandom } from './StunClient'

const PACKET_VERSION: number = 0x01
const NONCE_LENGTH: number = 12
const TAG_LENGTH: number = 16
const HKDF_HASH_LENGTH: number = 32
const HKDF_INFO: string = 'corterm-p2p-v1'

function utf8(value: string): Uint8Array {
  const encoder = new util.TextEncoder()
  return encoder.encodeInto(value)
}

async function hmacSha256(keyBytes: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const gen = cryptoFramework.createSymKeyGenerator('HMACSHA256')
  const key = await gen.convertKey({ data: keyBytes })
  const mac = cryptoFramework.createMac('SHA256')
  await mac.init(key)
  await mac.update({ data: data })
  const out = await mac.doFinal()
  return out.data
}

export class P2pCrypto {
  /** RFC 5869 extract：PRK = HMAC-SHA256(salt, IKM)。 */
  static async hkdfExtract(salt: Uint8Array, ikm: Uint8Array): Promise<Uint8Array> {
    return hmacSha256(salt, ikm)
  }

  /** RFC 5869 expand：逐块 T = HMAC(PRK, T(i-1) | info | counter)。 */
  static async hkdfExpand(prk: Uint8Array, info: Uint8Array, length: number): Promise<Uint8Array> {
    const blocks = Math.ceil(length / HKDF_HASH_LENGTH)
    const out = new Uint8Array(blocks * HKDF_HASH_LENGTH)
    let prev = new Uint8Array(0)
    for (let i = 1; i <= blocks; i++) {
      const input = new Uint8Array(prev.length + info.length + 1)
      input.set(prev, 0)
      input.set(info, prev.length)
      input[input.length - 1] = i
      prev = await hmacSha256(prk, input)
      out.set(prev, (i - 1) * HKDF_HASH_LENGTH)
    }
    return out.slice(0, length)
  }

  /** 规格 §3.1：从 RelayToken + transferId 派生 32B AES-256 会话密钥。 */
  static async deriveKey(relayToken: string, transferId: string): Promise<Uint8Array> {
    const prk = await P2pCrypto.hkdfExtract(utf8(transferId), utf8(relayToken))
    return P2pCrypto.hkdfExpand(prk, utf8(HKDF_INFO), 32)
  }

  /** AES-256-GCM 加密，返回 ciphertext+16B tag（AAD 为空）。 */
  static async aesGcmEncrypt(keyBytes: Uint8Array, nonce: Uint8Array, plain: Uint8Array): Promise<Uint8Array> {
    if (nonce.length !== NONCE_LENGTH) {
      throw new Error('GCM nonce must be 12 bytes')
    }
    const gen = cryptoFramework.createSymKeyGenerator('AES256')
    const key = await gen.convertKey({ data: keyBytes })
    const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding')
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, key, P2pCrypto.gcmParams(nonce, new Uint8Array(0)))
    const out = await cipher.doFinal({ data: plain })
    return out.data
  }

  /** AES-256-GCM 解密（tag 附在密文尾部）；校验失败抛出（调用方按规格丢弃该包）。 */
  static async aesGcmDecrypt(keyBytes: Uint8Array, nonce: Uint8Array, cipherWithTag: Uint8Array): Promise<Uint8Array> {
    if (cipherWithTag.length <= TAG_LENGTH) {
      throw new Error('GCM ciphertext too short')
    }
    const gen = cryptoFramework.createSymKeyGenerator('AES256')
    const key = await gen.convertKey({ data: keyBytes })
    const tag = cipherWithTag.slice(cipherWithTag.length - TAG_LENGTH)
    const body = cipherWithTag.slice(0, cipherWithTag.length - TAG_LENGTH)
    const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding')
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, key, P2pCrypto.gcmParams(nonce, tag))
    const out = await cipher.doFinal({ data: body })
    return out.data
  }

  private static gcmParams(nonce: Uint8Array, tag: Uint8Array): cryptoFramework.GcmParamsSpec {
    const params: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec',
      iv: { data: nonce },
      aad: { data: new Uint8Array(0) },
      authTag: { data: tag }
    }
    return params
  }

  /** 封 UDP 包：[1B version][12B nonce][ciphertext+tag]。 */
  static async sealPacket(keyBytes: Uint8Array, counter: number, plain: Uint8Array): Promise<ArrayBuffer> {
    const nonce = new Uint8Array(NONCE_LENGTH)
    nonce.set(P2pRandom.bytes(4), 0)
    const view = new DataView(nonce.buffer)
    view.setUint32(4, Math.floor(counter / 0x100000000), false)
    view.setUint32(8, counter >>> 0, false)
    const cipher = await P2pCrypto.aesGcmEncrypt(keyBytes, nonce, plain)
    const packet = new Uint8Array(1 + NONCE_LENGTH + cipher.length)
    packet[0] = PACKET_VERSION
    packet.set(nonce, 1)
    packet.set(cipher, 1 + NONCE_LENGTH)
    return packet.buffer as ArrayBuffer
  }

  /** 拆 UDP 包并解密；格式/版本/解密失败抛出，由分发层丢弃。 */
  static async openPacket(keyBytes: Uint8Array, packet: ArrayBuffer): Promise<ArrayBuffer> {
    if (packet.byteLength < 1 + NONCE_LENGTH + TAG_LENGTH + 1) {
      throw new Error('P2P packet too short')
    }
    const bytes = new Uint8Array(packet)
    if (bytes[0] !== PACKET_VERSION) {
      throw new Error(`unknown P2P packet version 0x${bytes[0].toString(16)}`)
    }
    const nonce = bytes.slice(1, 1 + NONCE_LENGTH)
    const cipher = bytes.slice(1 + NONCE_LENGTH)
    const plain = await P2pCrypto.aesGcmDecrypt(keyBytes, nonce, cipher)
    return plain.buffer.slice(plain.byteOffset, plain.byteOffset + plain.byteLength) as ArrayBuffer
  }
}
