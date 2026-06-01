export class HttpError extends Error {
  readonly statusCode: number;

  constructor(message: string, statusCode: number) {
    super(message);
    this.statusCode = statusCode;
  }
}

export class TimeoutError extends Error {
  constructor(message?: string) {
    super(message ?? 'Request timed out');
  }
}

export class HubException extends Error {
  constructor(message?: string) {
    super(message ?? 'Hub error');
  }
}

export class InternalServerError extends HttpError {
  constructor(message: string) {
    super(message, 500);
  }
}
