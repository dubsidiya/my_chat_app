import {
  AccessToken,
  RoomServiceClient,
  TrackSource,
  WebhookReceiver,
} from 'livekit-server-sdk';

function httpServiceUrl(url) {
  return String(url)
    .replace(/^wss:/i, 'https:')
    .replace(/^ws:/i, 'http:');
}

export function liveKitIdentityForUser(userId) {
  const value = String(userId ?? '').trim();
  if (!/^\d{1,32}$/.test(value)) {
    throw new Error('invalid_livekit_user_identity');
  }
  return `u-${value}`;
}

export function userIdFromLiveKitIdentity(identity) {
  const match = String(identity || '').match(/^u-(\d{1,32})$/);
  return match?.[1] || null;
}

export function safeParticipantName(value) {
  const normalized = String(value || 'Участник')
    .replace(/[\u0000-\u001f\u007f]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return (normalized || 'Участник').slice(0, 80);
}

export class LiveKitRoomProvider {
  constructor(config) {
    this.config = config;
    this.rooms = new RoomServiceClient(
      httpServiceUrl(config.url),
      config.apiKey,
      config.apiSecret
    );
    this.webhooks = new WebhookReceiver(config.apiKey, config.apiSecret);
  }

  async createRoom({ roomName, maxParticipants, emptyTimeoutSeconds }) {
    return this.rooms.createRoom({
      name: roomName,
      maxParticipants,
      emptyTimeout: emptyTimeoutSeconds,
    });
  }

  async deleteRoom(roomName) {
    try {
      await this.rooms.deleteRoom(roomName);
      return true;
    } catch (error) {
      if (
        error?.status === 404 ||
        error?.statusCode === 404 ||
        error?.code === 'not_found'
      ) {
        return false;
      }
      throw error;
    }
  }

  async removeParticipant(roomName, identity) {
    try {
      await this.rooms.removeParticipant(roomName, identity);
      return true;
    } catch (error) {
      if (
        error?.status === 404 ||
        error?.statusCode === 404 ||
        error?.code === 'not_found'
      ) {
        return false;
      }
      throw error;
    }
  }

  async issueParticipantToken({
    roomName,
    userId,
    participantName,
    ttlSeconds,
  }) {
    const token = new AccessToken(this.config.apiKey, this.config.apiSecret, {
      identity: liveKitIdentityForUser(userId),
      name: safeParticipantName(participantName),
      ttl: `${ttlSeconds}s`,
    });
    token.addGrant({
      roomJoin: true,
      room: roomName,
      canSubscribe: true,
      canPublish: true,
      canPublishSources: [TrackSource.CAMERA, TrackSource.MICROPHONE],
      canPublishData: false,
      canUpdateOwnMetadata: false,
    });
    return token.toJwt();
  }

  async verifyWebhook(rawBody, authorization) {
    return this.webhooks.receive(rawBody, authorization);
  }
}

export class FakeLiveKitRoomProvider {
  constructor(config, { webhookAuthorization = 'Bearer fake-livekit' } = {}) {
    this.config = config;
    this.webhookAuthorization = webhookAuthorization;
    this.createdRooms = [];
    this.deletedRooms = [];
    this.removedParticipants = [];
    this.issuedTokens = [];
    this.failCreate = false;
  }

  async createRoom(input) {
    if (this.failCreate) throw new Error('fake_room_create_failed');
    this.createdRooms.push(structuredClone(input));
    return { name: input.roomName };
  }

  async deleteRoom(roomName) {
    this.deletedRooms.push(String(roomName));
    return true;
  }

  async removeParticipant(roomName, identity) {
    this.removedParticipants.push({ roomName, identity });
    return true;
  }

  async issueParticipantToken(input) {
    const grants = {
      roomJoin: true,
      room: input.roomName,
      canSubscribe: true,
      canPublish: true,
      canPublishSources: ['camera', 'microphone'],
      canPublishData: false,
      canUpdateOwnMetadata: false,
    };
    this.issuedTokens.push({ ...structuredClone(input), grants });
    return `fake-livekit-token.${input.roomName}.${input.userId}`;
  }

  async verifyWebhook(rawBody, authorization) {
    if (authorization !== this.webhookAuthorization) {
      throw new Error('invalid_webhook_signature');
    }
    return JSON.parse(Buffer.from(rawBody).toString('utf8'));
  }
}

export function createLiveKitRoomProvider(config) {
  if (!config.enabled) return null;
  return config.provider === 'fake'
    ? new FakeLiveKitRoomProvider(config)
    : new LiveKitRoomProvider(config);
}
