/**
 * @file StunClient.ets
 * @brief RFC 5389 STUN Binding request/response over an existing UDP socket.
 *
 * 只 UDP、只 IPv4（规格 §2）。编解码与 Worker `StunClient.cs` 对齐：
 * magic cookie 0x2112A442，大端，XOR-MAPPED-ADDRESS (0x0020)。
 * 关键点：必须复用打洞用的同一个 socket 做 Binding，否则 NAT 映射端口与探包端口不一致。
 */

const MAGIC_COOKIE: number = 0x2112A442
const BINDING_REQUEST_TYPE: number = 0x0001
const BINDING_RESPONSE_TYPE: number = 0x0101
const ATTR_XOR_MAPPED_ADDRESS: number = 0x0020
const HEADER_LENGTH: number = 20

/** STUN 解析结果：公网映射 ip:port。 */
export class StunMappedAddress {
  ip: string = ''
  port: number = 0
}

/** 传输层抽象：send/一次接收，便于单测注入假 socket。 */
export interface IUdpLike {
  send(data: ArrayBuffer): Promise<void>
  receive(timeoutMs: number): Promise<ArrayBuffer>
}

export class StunClient {
  static readonly DEFAULT_SERVER: string = 'stun.l.google.com'
  static readonly DEFAULT_PORT: number = 19302

  /** 构造 Binding Request：20B 头（type=0x0001, len=0, magic, 12B txid）。 */
  static buildBindingRequest(txid: Uint8Array): ArrayBuffer {
    if (txid.length !== 12) {
      throw new Error('STUN txid must be 12 bytes')
    }
    const out = new ArrayBuffer(HEADER_LENGTH)
    const view = new DataView(out)
    const bytes = new Uint8Array(out)
    view.setUint16(0, BINDING_REQUEST_TYPE, false)
    view.setUint16(2, 0, false)
    view.setUint32(4, MAGIC_COOKIE, false)
    for (let i = 0; i < 12; i++) {
      bytes[8 + i] = txid[i]
    }
    return out
  }

  /**
   * 解析 Binding Response 的 XOR-MAPPED-ADDRESS。
   * 校验：type=0x0101、magic cookie、txid 与请求一致。
   */
  static parseXorMappedAddress(response: ArrayBuffer, txid: Uint8Array): StunMappedAddress {
    if (response.byteLength < HEADER_LENGTH) {
      throw new Error('STUN response too short')
    }
    const view = new DataView(response)
    const bytes = new Uint8Array(response)
    const msgType = view.getUint16(0, false)
    if (msgType !== BINDING_RESPONSE_TYPE) {
      throw new Error(`unexpected STUN message type 0x${msgType.toString(16)}`)
    }
    if (view.getUint32(4, false) !== MAGIC_COOKIE) {
      throw new Error('STUN magic cookie mismatch')
    }
    for (let i = 0; i < 12; i++) {
      if (bytes[8 + i] !== txid[i]) {
        throw new Error('STUN txid mismatch')
      }
    }
    const msgLength = view.getUint16(2, false)
    let offset = HEADER_LENGTH
    const end = HEADER_LENGTH + msgLength
    while (offset + 4 <= end && offset + 4 <= response.byteLength) {
      const attrType = view.getUint16(offset, false)
      const attrLength = view.getUint16(offset + 2, false)
      if (attrType === ATTR_XOR_MAPPED_ADDRESS && attrLength >= 8) {
        const family = view.getUint8(offset + 5)
        if (family !== 0x01) {
          throw new Error('STUN: only IPv4 supported')
        }
        const result = new StunMappedAddress()
        result.port = (view.getUint16(offset + 6, false) ^ (MAGIC_COOKIE >>> 16)) & 0xFFFF
        const xored = view.getUint32(offset + 8, false) ^ MAGIC_COOKIE
        result.ip = `${(xored >>> 24) & 0xFF}.${(xored >>> 16) & 0xFF}.${(xored >>> 8) & 0xFF}.${xored & 0xFF}`
        return result
      }
      offset += 4 + attrLength + ((4 - (attrLength % 4)) % 4)
    }
    throw new Error('STUN response has no XOR-MAPPED-ADDRESS')
  }

  /** 在给定 socket 上做一次 Binding（供打洞准备调用；失败抛出由上层回落）。 */
  static async discover(socket: IUdpLike, server: string = StunClient.DEFAULT_SERVER,
    port: number = StunClient.DEFAULT_PORT, timeoutMs: number = 3000): Promise<StunMappedAddress> {
    if (server.length === 0) {
      throw new Error('STUN server is required')
    }
    const txid = P2pRandom.txid()
    const request = StunClient.buildBindingRequest(txid)
    const pending = socket.receive(timeoutMs)
    await socket.send(request)
    const response = await pending
    return StunClient.parseXorMappedAddress(response, txid)
  }
}

/** 小工具：加密/协议用的随机字节。 */
export class P2pRandom {
  static bytes(count: number): Uint8Array {
    const out = new Uint8Array(count)
    for (let i = 0; i < count; i++) {
      out[i] = Math.floor(Math.random() * 256) & 0xFF
    }
    return out
  }

  static txid(): Uint8Array {
    return P2pRandom.bytes(12)
  }
}
