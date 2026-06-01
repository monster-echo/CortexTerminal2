export class InvocationRequest {
  invocationId: string = '';
  resolve: (value: Object | null) => void = (_v) => {};
  reject: (reason: Error) => void = (_e) => {};
}

export class StreamManager {
  private pending: Map<string, InvocationRequest> = new Map();
  private nextId: number = 0;

  generateInvocationId(): string {
    this.nextId++;
    return `${this.nextId}`;
  }

  addInvocation(invocationId: string, resolve: (value: Object | null) => void,
    reject: (reason: Error) => void): void {
    const request = new InvocationRequest();
    request.invocationId = invocationId;
    request.resolve = resolve;
    request.reject = reject;
    this.pending.set(invocationId, request);
  }

  getInvocation(invocationId: string): InvocationRequest | undefined {
    return this.pending.get(invocationId);
  }

  removeInvocation(invocationId: string): InvocationRequest | undefined {
    const request = this.pending.get(invocationId);
    if (request !== undefined) {
      this.pending.delete(invocationId);
    }
    return request;
  }

  rejectAll(reason: Error): void {
    this.pending.forEach((request: InvocationRequest) => {
      request.reject(reason);
    });
    this.pending.clear();
  }

  get pendingCount(): number {
    return this.pending.size;
  }
}
