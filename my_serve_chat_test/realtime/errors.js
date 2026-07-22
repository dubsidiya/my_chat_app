export class RealtimeUnavailableError extends Error {
  constructor(message = 'realtime_unavailable', options) {
    super(message, options);
    this.name = 'RealtimeUnavailableError';
    this.code = 'realtime_unavailable';
  }
}

export function isRealtimeUnavailable(error) {
  return (
    error instanceof RealtimeUnavailableError ||
    error?.code === 'realtime_unavailable'
  );
}
