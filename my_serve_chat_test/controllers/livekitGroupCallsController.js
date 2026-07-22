import crypto from 'node:crypto';

import {
  getLiveKitGroupCallCoordinator,
} from '../services/calls/livekitGroupCallCoordinator.js';
import { safeParticipantName } from '../services/calls/livekitProvider.js';

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function errorBody(code) {
  return { error: code };
}

export function createIssueLiveKitGroupTokenHandler({
  coordinator = getLiveKitGroupCallCoordinator(),
} = {}) {
  return async function issueLiveKitGroupToken(req, res, next) {
    res.setHeader('Cache-Control', 'no-store');
    const callId = String(req.params.callId || '').trim();
    if (!UUID_PATTERN.test(callId)) {
      return res.status(404).json(errorBody('call_not_found'));
    }
    if (!coordinator.config.enabled || !coordinator.provider) {
      return res.status(503).json(errorBody('livekit_unavailable'));
    }

    try {
      let call =
        await coordinator.runtime.registry.getLiveKitGroupCall(callId);
      if (!call) {
        const expired =
          await coordinator.runtime.registry.getLiveKitGroupCallRecord(
            callId
          );
        if (expired && Number(expired.expiresAt) <= Date.now()) {
          return res.status(410).json(errorBody('call_expired'));
        }
        const ended =
          await coordinator.runtime.registry.getLiveKitGroupCallTombstone(
            callId
          );
        return res
          .status(ended ? 410 : 404)
          .json(errorBody(ended ? 'call_ended' : 'call_not_found'));
      }
      if (
        call.kind !== 'livekit_group' ||
        ['ended', 'ending'].includes(call.state)
      ) {
        return res.status(410).json(errorBody('call_ended'));
      }
      const userId = String(req.userId);
      if (!(await coordinator.isCurrentMember(call.chatId, userId))) {
        return res.status(403).json(errorBody('not_a_member'));
      }
      const participant = call.participants?.[userId];
      if (
        !participant ||
        !['joined', 'disconnected'].includes(participant.state)
      ) {
        return res.status(403).json(errorBody('call_invite_not_accepted'));
      }
      if (participant.answerTokenHash) {
        const answerTicket =
          typeof req.body?.answer_ticket === 'string'
            ? req.body.answer_ticket.trim()
            : '';
        if (answerTicket.length < 32 || answerTicket.length > 256) {
          return res.status(403).json(errorBody('answered_elsewhere'));
        }
        const suppliedHash = crypto
          .createHash('sha256')
          .update(answerTicket)
          .digest();
        const expectedHash = Buffer.from(
          String(participant.answerTokenHash),
          'base64url'
        );
        if (
          suppliedHash.length !== expectedHash.length ||
          !crypto.timingSafeEqual(suppliedHash, expectedHash)
        ) {
          return res.status(403).json(errorBody('answered_elsewhere'));
        }
      }
      const user = await coordinator.pool.query(
        `SELECT COALESCE(NULLIF(TRIM(display_name), ''), email) AS label
           FROM users
          WHERE id = $1`,
        [userId]
      );
      if (user.rows.length === 0) {
        return res.status(403).json(errorBody('not_a_member'));
      }
      const participantName = safeParticipantName(user.rows[0].label);
      const token = await coordinator.provider.issueParticipantToken({
        roomName: call.roomName,
        userId,
        participantName,
        ttlSeconds: coordinator.config.tokenTtlSeconds,
      });
      return res.status(200).json({
        server_url: coordinator.config.url || 'wss://fake.livekit.invalid',
        participant_token: token,
        room_name: call.roomName,
        participant_name: participantName,
        call_id: call.callId,
        expires_at: new Date(
          Date.now() + coordinator.config.tokenTtlSeconds * 1000
        ).toISOString(),
      });
    } catch (error) {
      return next(error);
    }
  };
}

export function createLiveKitWebhookHandler({
  coordinator = getLiveKitGroupCallCoordinator(),
} = {}) {
  return async function liveKitWebhook(req, res) {
    res.setHeader('Cache-Control', 'no-store');
    if (
      !coordinator.config.enabled ||
      !coordinator.config.webhookEnabled ||
      !coordinator.provider
    ) {
      return res.status(404).json(errorBody('not_found'));
    }
    if (!req.is('application/webhook+json')) {
      return res.status(415).json(errorBody('unsupported_content_type'));
    }
    if (!Buffer.isBuffer(req.body)) {
      return res.status(400).json(errorBody('raw_body_required'));
    }
    let event;
    try {
      event = await coordinator.provider.verifyWebhook(
        req.body,
        String(req.headers.authorization || '')
      );
    } catch {
      return res.status(401).json(errorBody('invalid_webhook_signature'));
    }
    try {
      const result = await coordinator.handleWebhook(event);
      return res.status(200).json(result);
    } catch {
      return res.status(503).json(errorBody('webhook_reconciliation_failed'));
    }
  };
}

export const issueLiveKitGroupToken =
  createIssueLiveKitGroupTokenHandler();
