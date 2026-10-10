/**
 * @file ReliableStream.ets
 * @brief P2P 可靠流（规格 §3.3）：ARQ over 已打通的 UDP 通道。
 *
 * 帧格式（GCM 明文 payload）：[1B type][4B seq 大端][2B len 大端][payload]
 * type: 0x00 DATA | 0x01 ACK | 0x02 FIN | 0x03 RST
 * 参数：窗口 32 包，RTO 300ms 指数退避（上限 2s），3 个冗余 ACK 快速重传。
 * DATA payload ≤ 1150B（MTU 1200 − 包头 13 − GCM 开销）。
 * ACK payload = [4B cumulativeAck][4B sackRunCount][n × (4B start, 4B end)]（closed-run）。
 * 对上层提供按序字节读取：onData 回调 + read()/waitForEof()。
 */

const FRAME_TYPE_DATA: number = 0x00
const FRAME_TYPE_ACK: number = 0x01
const FRAME_TYPE_FIN: number = 0x02
const FRAME_TYPE_RST: number = 0x03

const FRAME_HEADER_LENGTH: number = 7
const MAX_DATA_PAYLOAD: number = 1150
const SEND_WINDOW: number = 32
const INITIAL_RTO_MS: number = 300
const MAX_RTO_MS: number = 2000
const FAST_RETRANSMIT_DUP_ACKS: number = 3
const TICK_MS: number = 50

/** 解码后的流帧。 */
export class P2pFrame {
  type: number = 0
  seq: number = 0
  payload: ArrayBuffer = new ArrayBuffer(0)
}

/** 已发送未确认的 DATA 包。 */
class OutboundPacket {
  seq: number = 0
  payload: ArrayBuffer = new ArrayBuffer(0)
  sendTimeMs: number = 0
  everRetransmitted: boolean = false
}

export class ReliableStream {
  /** 发送原语：上层把明文帧加密后经 UDP 发出（P2pTransfer 注入）。 */
  onSendFrame: (frameBytes: ArrayBuffer) => void = (_frameBytes: ArrayBuffer) => {
    throw new Error('ReliableStream.onSendFrame not wired')
  }
  /** 按序到达的数据回调（下载流式写文件用）。 */
  onData: (chunk: ArrayBuffer) => void = (_chunk: ArrayBuffer) => {}
  /** 对端异常关闭（RST）。 */
  onReset: () => void = () => {}
  /** 已读入但未被 read() 消费的字节。 */
  private readBuffer: ArrayBuffer[] = []
  private readBufferLength: number = 0
  private eofReached: boolean = false
  private eofWaiters: (() => void)[] = []

  private sendNextSeq: number = 0
  private recvNextSeq: number = 0
  private unacked: OutboundPacket[] = []
  private outOfOrder: Map<number, ArrayBuffer> = new Map()
  private rtoMs: number = INITIAL_RTO_MS
  private dupAckCount: number = 0
  private lastAckedSeq: number = -1
  private timer: number = -1
  private closed: boolean = false

  constructor() {
    this.timer = setInterval(() => this.onTick(), TICK_MS)
  }

  // ── 发送侧 ────────────────────────────────────────────────────────

  /** 写入字节流：自动按 1150B 切 DATA 帧，受 32 包发送窗口约束排队。 */
  write(data: ArrayBuffer): void {
    if (this.closed) {
      throw new Error('ReliableStream is closed')
    }
    const bytes = new Uint8Array(data)
    for (let offset = 0; offset < bytes.length; offset += MAX_DATA_PAYLOAD) {
      const size = Math.min(MAX_DATA_PAYLOAD, bytes.length - offset)
      const packet = new OutboundPacket()
      packet.seq = this.sendNextSeq
      packet.payload = bytes.slice(offset, offset + size).buffer as ArrayBuffer
      this.sendNextSeq++
      this.unacked.push(packet)
    }
    this.pump()
  }

  /** 本端写完：发 FIN（对端读侧随后 EOF）。 */
  finish(): void {
    this.sendFrame(FRAME_TYPE_FIN, 0, new Uint8Array(0))
  }

  /** 异常中止：发 RST 并停表。 */
  abort(): void {
    this.sendFrame(FRAME_TYPE_RST, 0, new Uint8Array(0))
    this.stop()
  }

  private pump(): void {
    while (this.unackedInFlight() < SEND_WINDOW) {
      const packet = this.nextUnsent()
      if (packet === null) {
        return
      }
      this.transmit(packet)
    }
  }

  private unackedInFlight(): number {
    let count = 0
    for (let i = 0; i < this.unacked.length; i++) {
      if (this.unacked[i].sendTimeMs > 0) {
        count++
      }
    }
    return count
  }

  private nextUnsent(): OutboundPacket | null {
    for (let i = 0; i < this.unacked.length; i++) {
      if (this.unacked[i].sendTimeMs === 0) {
        return this.unacked[i]
      }
    }
    return null
  }

  private transmit(packet: OutboundPacket): void {
    this.sendFrame(FRAME_TYPE_DATA, packet.seq, new Uint8Array(packet.payload))
    packet.sendTimeMs = Date.now()
    packet.everRetransmitted = true
  }

  private sendFrame(type: number, seq: number, payload: Uint8Array): void {
    if (payload.length > 0xFFFF) {
      throw new Error('frame payload too large')
    }
    const out = new ArrayBuffer(FRAME_HEADER_LENGTH + payload.length)
    const view = new DataView(out)
    view.setUint8(0, type)
    view.setUint32(1, seq, false)
    view.setUint16(5, payload.length, false)
    new Uint8Array(out).set(payload, FRAME_HEADER_LENGTH)
    this.onSendFrame(out)
  }

  // ── 接收侧 ────────────────────────────────────────────────────────

  /** 收到解密后的明文帧（P2pTransfer 分发）。 */
  handleFrame(frameBytes: ArrayBuffer): void {
    if (frameBytes.byteLength < FRAME_HEADER_LENGTH) {
      throw new Error('frame too short')
    }
    const view = new DataView(frameBytes)
    const type = view.getUint8(0)
    const seq = view.getUint32(1, false)
    const len = view.getUint16(5, false)
    if (frameBytes.byteLength < FRAME_HEADER_LENGTH + len) {
      throw new Error('frame length mismatch')
    }
    const payload = frameBytes.slice(FRAME_HEADER_LENGTH, FRAME_HEADER_LENGTH + len)
    if (type === FRAME_TYPE_DATA) {
      this.handleData(seq, payload)
    } else if (type === FRAME_TYPE_ACK) {
      this.handleAck(payload)
    } else if (type === FRAME_TYPE_FIN) {
      this.markEof()
    } else if (type === FRAME_TYPE_RST) {
      this.closed = true
      this.stop()
      this.onReset()
    }
  }

  private handleData(seq: number, payload: ArrayBuffer): void {
    this.sendFrame(FRAME_TYPE_ACK, 0, this.buildAckPayload(seq))
    if (seq === this.recvNextSeq) {
      this.deliverInOrder(seq, payload)
    } else if (seq > this.recvNextSeq) {
      if (!this.outOfOrder.has(seq)) {
        this.outOfOrder.set(seq, payload)
      }
    }
  }

  private deliverInOrder(seq: number, payload: ArrayBuffer): void {
    this.recvNextSeq = seq + 1
    this.readBuffer.push(payload)
    this.readBufferLength += payload.byteLength
    this.onData(payload)
    let next = this.outOfOrder.get(this.recvNextSeq)
    while (next !== undefined) {
      this.outOfOrder.delete(this.recvNextSeq)
      this.recvNextSeq++
      this.readBuffer.push(next)
      this.readBufferLength += next.byteLength
      this.onData(next)
      next = this.outOfOrder.get(this.recvNextSeq)
    }
  }

  /** ACK payload：cumulativeAck = 下一个期望 seq；sack 记录乱序缓存之间的缺失区间（closed-run）。 */
  private buildAckPayload(_receivedSeq: number): Uint8Array {
    const seqs: number[] = []
    this.outOfOrder.forEach((_value: ArrayBuffer, key: number) => {
      seqs.push(key)
    })
    seqs.sort((a: number, b: number) => a - b)
    const runs: number[] = []
    let pointer = this.recvNextSeq
    for (let i = 0; i < seqs.length; i++) {
      if (seqs[i] > pointer) {
        runs.push(pointer)
        runs.push(seqs[i] - 1)
      }
      pointer = seqs[i] + 1
    }
    const out = new Uint8Array(8 + runs.length * 4)
    const view = new DataView(out.buffer)
    view.setUint32(0, this.recvNextSeq, false)
    view.setUint32(4, runs.length / 2, false)
    for (let i = 0; i < runs.length; i++) {
      view.setUint32(8 + i * 4, runs[i], false)
    }
    return out
  }

  private handleAck(payload: ArrayBuffer): void {
    if (payload.byteLength < 8) {
      throw new Error('ACK payload too short')
    }
    const view = new DataView(payload, 0, payload.byteLength)
    const cumulative = view.getUint32(0, false)
    let dropped = false
    while (this.unacked.length > 0 && this.unacked[0].seq < cumulative) {
      this.unacked.shift()
      dropped = true
    }
    if (cumulative > this.lastAckedSeq) {
      this.lastAckedSeq = cumulative
      this.dupAckCount = 0
      this.rtoMs = INITIAL_RTO_MS
    } else {
      this.dupAckCount++
    }
    // SACK：丢弃已被乱序确认覆盖的包
    const runCount = view.getUint32(4, false)
    for (let r = 0; r < runCount; r++) {
      const start = view.getUint32(8 + r * 8, false)
      const end = view.getUint32(12 + r * 8, false)
      this.unacked = this.unacked.filter((p: OutboundPacket) => !(p.seq >= start && p.seq <= end))
      dropped = true
    }
    if (dropped && this.dupAckCount < FAST_RETRANSMIT_DUP_ACKS) {
      this.pump()
    }
    if (this.dupAckCount >= FAST_RETRANSMIT_DUP_ACKS && this.unacked.length > 0) {
      this.transmit(this.unacked[0])
      this.dupAckCount = 0
    }
  }

  private onTick(): void {
    const now = Date.now()
    for (let i = 0; i < this.unacked.length; i++) {
      const packet = this.unacked[i]
      if (packet.sendTimeMs > 0 && now - packet.sendTimeMs >= this.rtoMs) {
        this.transmit(packet)
        this.rtoMs = Math.min(this.rtoMs * 2, MAX_RTO_MS)
      }
    }
  }

  // ── 读侧 ──────────────────────────────────────────────────────────

  /** 读取当前可用的按序字节；无数据返回 null。 */
  read(): ArrayBuffer | null {
    if (this.readBuffer.length === 0) {
      return null
    }
    if (this.readBuffer.length === 1) {
      const single = this.readBuffer[0]
      this.readBuffer = []
      this.readBufferLength = 0
      return single
    }
    const merged = new Uint8Array(this.readBufferLength)
    let offset = 0
    for (let i = 0; i < this.readBuffer.length; i++) {
      merged.set(new Uint8Array(this.readBuffer[i]), offset)
      offset += this.readBuffer[i].byteLength
    }
    this.readBuffer = []
    this.readBufferLength = 0
    return merged.buffer as ArrayBuffer
  }

  private markEof(): void {
    this.eofReached = true
    for (let i = 0; i < this.eofWaiters.length; i++) {
      this.eofWaiters[i]()
    }
    this.eofWaiters = []
  }

  /** 等待对端 FIN（读侧 EOF）。 */
  waitForEof(timeoutMs: number): Promise<void> {
    if (this.eofReached) {
      return Promise.resolve()
    }
    return new Promise<void>((resolve, reject) => {
      const timerId = setTimeout(() => {
        reject(new Error('timed out waiting for peer FIN'))
      }, timeoutMs)
      this.eofWaiters.push(() => {
        clearTimeout(timerId)
        resolve()
      })
    })
  }

  /** 正常收尾（收到 FIN 或传完后）：停重传定时器。 */
  stop(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer)
      this.timer = -1
    }
    this.closed = true
  }

  isEof(): boolean {
    return this.eofReached
  }
}
