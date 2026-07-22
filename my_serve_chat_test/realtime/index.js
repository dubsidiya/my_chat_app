import 'dotenv/config';
import { createRealtimeRuntime } from './runtime.js';

export const realtimeRuntime = createRealtimeRuntime();

export { loadRealtimeConfig } from './config.js';
export { RealtimeRuntime, createRealtimeRuntime } from './runtime.js';
export {
  MemoryCallRegistry,
  publicCallStatus,
  publicLiveKitGroupStatus,
} from './memoryCallRegistry.js';
export { RedisCallRegistry } from './redisCallRegistry.js';
export {
  RealtimeUnavailableError,
  isRealtimeUnavailable,
} from './errors.js';
