import {
  findChatCreatorId,
  findChatMemberRole,
  findChatMembership,
} from '../../repositories/chats/chatsCommonRepository.js';

const normalizeRole = (role) => (role || '').toString().toLowerCase();

export const getChatCreatorId = async (db, chatId) => {
  const r = await findChatCreatorId(db, chatId);
  return r.rows.length ? r.rows[0].created_by?.toString() : null;
};

export const getMemberRole = async (db, chatId, userId) => {
  const r = await findChatMemberRole(db, chatId, userId);
  if (!r.rows.length) return null;
  return normalizeRole(r.rows[0].role);
};

export const isOwnerOrAdmin = async (db, chatId, userId) => {
  const role = await getMemberRole(db, chatId, userId);
  if (role === 'owner' || role === 'admin') return true;
  const creatorId = await getChatCreatorId(db, chatId);
  return creatorId && creatorId.toString() === userId.toString();
};

export const isOwner = async (db, chatId, userId) => {
  const role = await getMemberRole(db, chatId, userId);
  if (role === 'owner') return true;
  const creatorId = await getChatCreatorId(db, chatId);
  return creatorId && creatorId.toString() === userId.toString();
};

export const ensureChatMember = async (db, chatId, userId) => {
  const r = await findChatMembership(db, chatId, userId);
  return r.rows.length > 0;
};
