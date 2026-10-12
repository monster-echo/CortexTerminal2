/**
 * @file P2pTransfer.ets
 * @brief P2P 打洞传输客户端侧（规格 §1、§4、§5）。
 *
 * 流程：绑定 UDP socket → 该 socket 上 STUN Binding → 循环 POST
 * `/api/transfers/{tid}/punch`（role=client，2s 间隔，Authorization JWT +
 * X-Corterm-Transfer-Token）拿 peerEndpoint → 50ms 互发探包（"PT"+12B txid，
 * 收到任意 txid 的 14B "PT" 包即打通）→ 可靠流上发精简 HTTP/1.1
 * PUT/GET /transfer/{id}?token=。
 *
 * 与 FilesService 的接入：发起传输时并行 startPreparation()，LAN 尝试后等待
 * 最多 6s；p2p 打通则上传/下载，任何失败静默落到下一端点（规格允许的唯一回落）。
 */
import { socket } from '@kit.NetworkKit'
import connection from '@ohos.net.connection'
import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { StunClient, P2pRandom, StunMappedAddress } from './StunClient'
import { P2pCrypto } from './P2pCrypto'
import { ReliableStream } from './ReliableStream'

const PROBE_PREFIX: string = 'PT'
const PROBE_LENGTH: number = 14
const PUNCH_INTERVAL_MS: number = 2000
const PUNCH_WINDOW_MS: number = 60000
const PROBE_INTERVAL_MS: number = 50
const PUNCH_TO_PROBE_TIMEOUT_MS: number = 10000
const STUN_SERVER: string = 'stun.l.google.com'
const STUN_PORT: number = 19302
const HTTP_TIMEOUT_MS: number = 600000

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(resolve, ms)
  })
}

function utf8Bytes(value: string): Uint8Array {
  const encoder = new util.TextEncoder()
  return encoder.encodeInto(value)
}

/** 探包准备就绪：对端地址。 */
class PunchPeer {
  address: string = ''
  port: number = 0
}

/**
 * UDP socket 包装：探包/STUN 收包与打通后的加密流收包共用一个 socket，
 * 通过 datagram 前缀路由（14B "PT" = 探包，其余 = 加密流）。
 */
export class UdpSocketBox {
  private udp: socket.UDPSocket = socket.constructUDPSocketInstance()
  private bound: boolean = false
  private pendingReceivers: ((data: ArrayBuffer) => void)[] = []
  /** 打通后由 P2pChannel 注入的流分发回调；探包优先短路。 */
  onDatagram: (data: ArrayBuffer) => void = (_data: ArrayBuffer) => {}

  async bind(): Promise<void> {
    const address: socket.NetAddress = {
      address: '0.0.0.0',
      port: 0,
      family: 1
    }
    await this.udp.bind(address)
    this.bound = true
    this.udp.on('message', (value: socket.SocketMessageInfo) => {
      const data = value.message as ArrayBuffer
      if (this.pendingReceivers.length > 0) {
        const receiver = this.pendingReceivers.shift()
        if (receiver !== undefined) {
          receiver(data)
        }
        return
      }
      this.onDatagram(data)
    })
  }

  async sendTo(data: ArrayBuffer, address: string, port: number): Promise<void> {
    if (!this.bound) {
      throw new Error('UDP socket not bound')
    }
    const target: socket.NetAddress = {
      address: address,
      port: port,
      family: 1
    }
    const sendOptions: socket.UDPSendOptions = {
      data: data,
      address: target
    }
    await this.udp.send(sendOptions)
  }

  /** 阻塞等一个包（STUN 用）；超时 reject。 */
  receiveOnce(timeoutMs: number): Promise<ArrayBuffer> {
    return new Promise<ArrayBuffer>((resolve, reject) => {
      const timerId = setTimeout(() => {
        const idx = this.pendingReceivers.indexOf(receiver)
        if (idx >= 0) {
          this.pendingReceivers.splice(idx, 1)
        }
        reject(new Error('UDP receive timed out'))
      }, timeoutMs)
      const receiver = (data: ArrayBuffer) => {
        clearTimeout(timerId)
        resolve(data)
      }
      this.pendingReceivers.push(receiver)
    })
  }

  async close(): Promise<void> {
    if (this.bound) {
      this.udp.off('message')
      await this.udp.close()
      this.bound = false
    }
  }
}

/** 打通后的加密可靠流通道。 */
export class P2pChannel {
  readonly socketBox: UdpSocketBox
  readonly stream: ReliableStream
  readonly remoteAddress: string
  readonly remotePort: number
  private readonly keyBytes: Uint8Array
  private sendCounter: number = 0

  constructor(socketBox: UdpSocketBox, stream: ReliableStream, keyBytes: Uint8Array,
    remoteAddress: string, remotePort: number) {
    this.socketBox = socketBox
    this.stream = stream
    this.keyBytes = keyBytes
    this.remoteAddress = remoteAddress
    this.remotePort = remotePort
    stream.onSendFrame = (frameBytes: ArrayBuffer) => {
      this.encryptAndSend(frameBytes)
    }
  }

  private encryptAndSend(plain: ArrayBuffer): void {
    const counter = this.sendCounter
    this.sendCounter++
    const key = this.keyBytes
    const box = this.socketBox
    const addr = this.remoteAddress
    const port = this.remotePort
    P2pCrypto.sealPacket(key, counter, new Uint8Array(plain)).then((packet: ArrayBuffer) => {
      return box.sendTo(packet, addr, port)
    }).catch((e: Object) => {
      // 异步发送失败无法同步上抛（调用点已在 await 之外）；后续 RTO 会重传，
      // 通道级故障由传输超时体现，不静默吞日志。
      console.error(`[P2pTransfer] send failed: ${(e as Error).message}`)
    })
  }

  async close(): Promise<void> {
    this.stream.stop()
    await this.socketBox.close()
  }
}

/** p2p 并行准备句柄：ready 在打通后 resolve，失败/超时 reject。 */
export class P2pPreparation {
  readonly ready: Promise<P2pChannel>
  private readonly cancelHook: () => void
  private cancelled: boolean = false

  constructor(ready: Promise<P2pChannel>, cancel: () => void) {
    this.ready = ready
    this.cancelHook = cancel
  }

  cancel(): void {
    this.cancelled = true
    this.cancelHook()
  }

  isCancelled(): boolean {
    return this.cancelled
  }
}

export class P2pTransfer {
  static readonly READY_WAIT_MS: number = 6000

  /**
   * 并行启动 p2p 准备（规格 §1）：绑定 → STUN → punch 循环 → 探包。
   * 任何一步失败都会让 ready reject（由协商层静默回落下一端点）。
   */
  static startPreparation(transferId: string, relayToken: string): P2pPreparation {
    const box = new UdpSocketBox()
    let cancelled = false
    const cancel = () => {
      cancelled = true
      box.close().catch((_e: Object) => {})
    }
    const ready = P2pTransfer.prepareAsync(transferId, relayToken, box, () => cancelled)
    return new P2pPreparation(ready, cancel)
  }

  /**
   * Worker 常驻锚点版预打洞：worker online 时其锚点已向 gateway rendezvous 常驻
   * 注册（key=workerId）并缓存 NAT 映射端点，这里注册后第一次 POST 即可拿到
   * worker 端点，探包 <1s 打通——无需等对端从零 STUN/注册。信封（transferId +
   * relayToken）经 HTTPS+JWT 顺路带给 worker，通道密钥两端仍各自
   * deriveKey(relayToken, transferId)，UDP 面无明文密钥。
   */
  static startPreparationForWorker(workerId: string, transferId: string, relayToken: string): P2pPreparation {
    const box = new UdpSocketBox()
    let cancelled = false
    const cancel = () => {
      cancelled = true
      box.close().catch((_e: Object) => {})
    }
    const ready = P2pTransfer.prepareWorkerAsync(workerId, transferId, relayToken, box, () => cancelled)
    return new P2pPreparation(ready, cancel)
  }

  private static async prepareWorkerAsync(workerId: string, transferId: string, relayToken: string,
    box: UdpSocketBox, isCancelled: () => boolean): Promise<P2pChannel> {
    try {
      await box.bind()
      const mapped = await P2pTransfer.stunDiscover(box)
      const deadline = Date.now() + PUNCH_WINDOW_MS
      let peer: PunchPeer | null = null
      while (peer === null && Date.now() < deadline && !isCancelled()) {
        peer = await P2pTransfer.punchOnceForWorker(workerId, transferId, relayToken, mapped)
        if (peer === null) {
          await sleep(PUNCH_INTERVAL_MS)
        }
      }
      if (peer === null) {
        throw new Error('P2P punch window expired without worker anchor endpoint')
      }
      await P2pTransfer.probeUntilOpen(box, peer)
      const stream = new ReliableStream()
      const keyBytes = await P2pCrypto.deriveKey(relayToken, transferId)
      const channel = new P2pChannel(box, stream, keyBytes, peer.address, peer.port)
      box.onDatagram = (data: ArrayBuffer) => {
        P2pCrypto.openPacket(keyBytes, data).then((plain: ArrayBuffer) => {
          stream.handleFrame(plain)
        }).catch((_e: Object) => {})
      }
      return channel
    } catch (e) {
      await box.close()
      throw new Error((e as Error).message)
    }
  }

  private static async prepareAsync(transferId: string, relayToken: string,
    box: UdpSocketBox, isCancelled: () => boolean): Promise<P2pChannel> {
    try {
      await box.bind()
      const mapped = await P2pTransfer.stunDiscover(box)
      const deadline = Date.now() + PUNCH_WINDOW_MS
      let peer: PunchPeer | null = null
      while (peer === null && Date.now() < deadline && !isCancelled()) {
        peer = await P2pTransfer.punchOnce(transferId, relayToken, mapped)
        if (peer === null) {
          await sleep(PUNCH_INTERVAL_MS)
        }
      }
      if (peer === null) {
        throw new Error('P2P punch window expired without peer endpoint')
      }
      await P2pTransfer.probeUntilOpen(box, peer)
      const stream = new ReliableStream()
      const keyBytes = await P2pCrypto.deriveKey(relayToken, transferId)
      const channel = new P2pChannel(box, stream, keyBytes, peer.address, peer.port)
      box.onDatagram = (data: ArrayBuffer) => {
        P2pCrypto.openPacket(keyBytes, data).then((plain: ArrayBuffer) => {
          stream.handleFrame(plain)
        }).catch((_e: Object) => {
          // 规格 §3.2：解密失败（tag 校验不过）→ 丢弃该包
        })
      }
      return channel
    } catch (e) {
      await box.close()
      throw new Error((e as Error).message)
    }
  }

  /** STUN Binding 必须复用打洞 socket（否则 NAT 映射端口不一致，打洞必失败）。 */
  private static async stunDiscover(box: UdpSocketBox): Promise<StunMappedAddress> {
    const resolved = await connection.getAddressesByName(STUN_SERVER)
    if (resolved.length === 0) {
      throw new Error(`cannot resolve STUN server ${STUN_SERVER}`)
    }
    const server = resolved[0]
    const txid = P2pRandom.txid()
    const request = StunClient.buildBindingRequest(txid)
    const pending = box.receiveOnce(3000)
    await box.sendTo(request, server.address, STUN_PORT)
    const response = await pending
    return StunClient.parseXorMappedAddress(response, txid)
  }

  /** 一次 /punch：失败（网络错）返回 null 继续轮询；非网络错误上抛。 */
  private static async punchOnce(transferId: string, relayToken: string,
    mapped: StunMappedAddress): Promise<PunchPeer | null> {
    const gatewayUrl = AppStorage.get<string>('gatewayUrl') as string
    const url = `${gatewayUrl}/api/transfers/${encodeURIComponent(transferId)}/punch`
    const body: Record<string, string> = {
      'role': 'client',
      'endpoint': `${mapped.ip}:${mapped.port}`
    }
    const header: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': `Bearer ${AppStorage.get<string>('authToken') || ''}`,
      'X-Corterm-Transfer-Token': relayToken
    }
    return P2pTransfer.punchPost(url, header, body)
  }

  /** Worker 锚点端点的一次 punch：JWT 鉴权，信封随请求体送达 worker（经 gateway）。 */
  private static async punchOnceForWorker(workerId: string, transferId: string, relayToken: string,
    mapped: StunMappedAddress): Promise<PunchPeer | null> {
    const gatewayUrl = AppStorage.get<string>('gatewayUrl') as string
    const url = `${gatewayUrl}/api/p2p/workers/${encodeURIComponent(workerId)}/punch`
    const body: Record<string, string> = {
      'role': 'client',
      'endpoint': `${mapped.ip}:${mapped.port}`,
      'transferId': transferId,
      'relayToken': relayToken
    }
    const header: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': `Bearer ${AppStorage.get<string>('authToken') || ''}`
    }
    return new Promise<PunchPeer | null>((resolve, reject) => {
      const httpRequest = http.createHttp()
      httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: header,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.OBJECT,
        connectTimeout: 5000,
        readTimeout: 5000
      }, (err, data) => {
        try {
          if (err) {
            resolve(null)
            return
          }
          if (data.responseCode !== 200) {
            reject(new Error(`punch failed (${data.responseCode})`))
            return
          }
          const record = data.result as Record<string, Object>
          // worker 锚点不在线（旧版 worker / 断连）：p2p 已无对象可打，
          // 立即放弃让协商链落到 Relay，而不是空转 60s 打洞窗口。
          const anchorOnline = (record['anchorOnline'] as boolean) ?? false
          if (!anchorOnline) {
            reject(new Error('P2P anchor offline'))
            return
          }
          const readyFlag = (record['ready'] as boolean) ?? false
          if (!readyFlag) {
            resolve(null)
            return
          }
          const peerEndpoint = (record['peerEndpoint'] as string) ?? ''
          if (peerEndpoint.length === 0) {
            reject(new Error('punch ready but peerEndpoint is empty'))
            return
          }
          const sep = peerEndpoint.lastIndexOf(':')
          if (sep <= 0) {
            reject(new Error(`bad peerEndpoint: ${peerEndpoint}`))
            return
          }
          const peer = new PunchPeer()
          peer.address = peerEndpoint.substring(0, sep)
          peer.port = Number.parseInt(peerEndpoint.substring(sep + 1))
          resolve(peer)
        } finally {
          httpRequest.destroy()
        }
      })
    })
  }

  /** punch HTTP 公共骨架：网络抖动返回 null 继续窗口；非 200 上抛。 */
  private static punchPost(url: string, header: Record<string, string>,
    body: Record<string, string>): Promise<PunchPeer | null> {
    return new Promise<PunchPeer | null>((resolve, reject) => {
      const httpRequest = http.createHttp()
      httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: header,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.OBJECT,
        connectTimeout: 5000,
        readTimeout: 5000
      }, (err, data) => {
        try {
          if (err) {
            resolve(null) // 网络抖动：继续 punch 窗口
            return
          }
          if (data.responseCode !== 200) {
            reject(new Error(`punch failed (${data.responseCode})`))
            return
          }
          const record = data.result as Record<string, Object>
          const readyFlag = (record['ready'] as boolean) ?? false
          if (!readyFlag) {
            resolve(null)
            return
          }
          const peerEndpoint = (record['peerEndpoint'] as string) ?? ''
          if (peerEndpoint.length === 0) {
            reject(new Error('punch ready but peerEndpoint is empty'))
            return
          }
          const sep = peerEndpoint.lastIndexOf(':')
          if (sep <= 0) {
            reject(new Error(`bad peerEndpoint: ${peerEndpoint}`))
            return
          }
          const peer = new PunchPeer()
          peer.address = peerEndpoint.substring(0, sep)
          peer.port = Number.parseInt(peerEndpoint.substring(sep + 1))
          resolve(peer)
        } finally {
          httpRequest.destroy()
        }
      })
    })
  }

  /** 50ms 探包直到收到对端任意 txid 的 14B "PT" 包（窗口 10s）。 */
  private static async probeUntilOpen(box: UdpSocketBox, peer: PunchPeer): Promise<void> {
    const txid = P2pRandom.txid()
    const probe = new ArrayBuffer(PROBE_LENGTH)
    const probeBytes = new Uint8Array(probe)
    const prefix = utf8Bytes(PROBE_PREFIX)
    probeBytes.set(prefix, 0)
    probeBytes.set(txid, 2)
    let opened = false
    const onDatagram = (data: ArrayBuffer) => {
      if (data.byteLength === PROBE_LENGTH) {
        const bytes = new Uint8Array(data)
        if (bytes[0] === prefix[0] && bytes[1] === prefix[1]) {
          opened = true
        }
      }
    }
    box.onDatagram = onDatagram
    const deadline = Date.now() + PUNCH_TO_PROBE_TIMEOUT_MS
    while (!opened && Date.now() < deadline) {
      await box.sendTo(probe, peer.address, peer.port)
      await sleep(PROBE_INTERVAL_MS)
    }
    if (!opened) {
      throw new Error('P2P probe window timed out')
    }
  }

  // ── HTTP over 可靠流（规格 §4） ─────────────────────────────────

  /** 上传：PUT /transfer/{id}?token= + body，200 即成功。 */
  static async uploadP2p(channel: P2pChannel, transferId: string, relayToken: string,
    bytes: ArrayBuffer): Promise<void> {
    const head = `PUT /transfer/${encodeURIComponent(transferId)}?token=${encodeURIComponent(relayToken)} HTTP/1.1\r\n` +
      'Host: p2p\r\n' +
      'Content-Type: application/octet-stream\r\n' +
      `Content-Length: ${bytes.byteLength}\r\n\r\n`
    channel.stream.write(utf8Bytes(head).buffer as ArrayBuffer)
    channel.stream.write(bytes)
    channel.stream.finish()
    const status = await P2pTransfer.readResponseStatus(channel.stream)
    if (status < 200 || status >= 300) {
      throw new Error(`P2P upload failed (${status})`)
    }
  }

  /**
   * 下载：GET /transfer/{id}?token=，按 Content-Length 流式回调 onChunk 写文件。
   * onChunk 的对齐用法见 FilesService.downloadViaEndpoints（fs.openSync + writeSync）。
   */
  static async downloadP2p(channel: P2pChannel, transferId: string, relayToken: string,
    onChunk: (chunk: ArrayBuffer) => void): Promise<void> {
    const head = `GET /transfer/${encodeURIComponent(transferId)}?token=${encodeURIComponent(relayToken)} HTTP/1.1\r\n` +
      'Host: p2p\r\n\r\n'
    channel.stream.write(utf8Bytes(head).buffer as ArrayBuffer)
    channel.stream.finish()

    const reader = new P2pStreamReader(channel.stream)
    const status = await reader.readStatus(HTTP_TIMEOUT_MS)
    if (status !== 200) {
      throw new Error(`P2P download failed (${status})`)
    }
    const contentLength = await reader.readContentLength(HTTP_TIMEOUT_MS)
    let received = 0
    const deadline = Date.now() + HTTP_TIMEOUT_MS
    while (received < contentLength && Date.now() < deadline) {
      const chunk = reader.takeBody()
      if (chunk !== null) {
        received += chunk.byteLength
        onChunk(chunk)
        continue
      }
      if (channel.stream.isEof() && received < contentLength) {
        throw new Error(`P2P download truncated (${received}/${contentLength})`)
      }
      await sleep(10)
    }
    if (received < contentLength) {
      throw new Error('P2P download timed out')
    }
  }

  /** 上传响应无 body：只等状态行。 */
  private static async readResponseStatus(stream: ReliableStream): Promise<number> {
    const reader = new P2pStreamReader(stream)
    return reader.readStatus(HTTP_TIMEOUT_MS)
  }
}

/** 从可靠流读精简 HTTP 响应：状态行 + 头部 + body 缓冲。 */
class P2pStreamReader {
  private readonly stream: ReliableStream
  private buffered: ArrayBuffer[] = []
  private headerText: string = ''
  private headerDone: boolean = false

  constructor(stream: ReliableStream) {
    this.stream = stream
  }

  async readStatus(timeoutMs: number): Promise<number> {
    await this.readHeaders(timeoutMs)
    const firstLine = this.headerText.split('\r\n')[0]
    const parts = firstLine.split(' ')
    if (parts.length < 2 || !parts[0].startsWith('HTTP/')) {
      throw new Error(`bad P2P HTTP response line: ${firstLine}`)
    }
    return Number.parseInt(parts[1])
  }

  async readContentLength(timeoutMs: number): Promise<number> {
    await this.readHeaders(timeoutMs)
    const lower = this.headerText.toLowerCase()
    const marker = 'content-length:'
    const idx = lower.indexOf(marker)
    if (idx < 0) {
      throw new Error('P2P HTTP response missing Content-Length')
    }
    const end = this.headerText.indexOf('\r\n', idx)
    const raw = this.headerText.substring(idx + marker.length, end).trim()
    return Number.parseInt(raw)
  }

  /** 头部之后已缓冲的 body（按当前可用量）；无则 null。 */
  takeBody(): ArrayBuffer | null {
    if (this.buffered.length === 0) {
      return null
    }
    if (this.buffered.length === 1) {
      const single = this.buffered[0]
      this.buffered = []
      return single
    }
    let total = 0
    for (let i = 0; i < this.buffered.length; i++) {
      total += this.buffered[i].byteLength
    }
    const merged = new Uint8Array(total)
    let offset = 0
    for (let i = 0; i < this.buffered.length; i++) {
      merged.set(new Uint8Array(this.buffered[i]), offset)
      offset += this.buffered[i].byteLength
    }
    this.buffered = []
    return merged.buffer as ArrayBuffer
  }

  private async readHeaders(timeoutMs: number): Promise<void> {
    if (this.headerDone) {
      return
    }
    const decoder = new util.TextDecoder('utf-8')
    const deadline = Date.now() + timeoutMs
    const pending: ArrayBuffer[] = []
    while (Date.now() < deadline) {
      const chunk = this.stream.read()
      if (chunk !== null) {
        pending.push(chunk)
        const text = this.decodeAll(decoder, pending)
        const sep = text.indexOf('\r\n\r\n')
        if (sep >= 0) {
          this.headerText = text.substring(0, sep + 4)
          this.headerDone = true
          const headerBytes = utf8Bytes(text.substring(0, sep + 4)).length
          this.restoreBodyTail(pending, text.substring(sep + 4), headerBytes)
          return
        }
        continue
      }
      if (this.stream.isEof() && !this.headerDone) {
        throw new Error('P2P connection closed before HTTP response header')
      }
      await sleep(10)
    }
    throw new Error('timed out reading P2P HTTP response header')
  }

  private decodeAll(decoder: util.TextDecoder, chunks: ArrayBuffer[]): string {
    let text = ''
    for (let i = 0; i < chunks.length; i++) {
      text += decoder.decodeToString(new Uint8Array(chunks[i]))
    }
    return text
  }

  /** 头部尾部跨界情况：body 起点在最后一个 chunk 内时，按字节差切出剩余 body。 */
  private restoreBodyTail(chunks: ArrayBuffer[], tailText: string, headerBytes: number): void {
    if (tailText.length === 0) {
      return
    }
    let beforeHeader = 0
    for (let i = 0; i < chunks.length - 1; i++) {
      beforeHeader += chunks[i].byteLength
    }
    const last = chunks[chunks.length - 1]
    const headerInLast = headerBytes - beforeHeader
    const bodyBytes = new Uint8Array(last).slice(headerInLast)
    if (bodyBytes.length > 0) {
      this.buffered.push(bodyBytes.buffer as ArrayBuffer)
    }
  }
}
