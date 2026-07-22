export const REGISTER_CONNECTION_LUA = `
local existing = redis.call('GET', KEYS[1])
if existing then
  local lease = cjson.decode(existing)
  if tostring(lease.userId) ~= ARGV[1] then
    return 0
  end
end
redis.call('SET', KEYS[1], ARGV[2], 'PX', ARGV[3])
return 1
`;

export const CREATE_DM_CALL_LUA = `
local function clearStaleDmBusy(key)
  local raw = redis.call('GET', key)
  if not raw then return end
  local busy = cjson.decode(raw)
  if busy.kind == 'dm' and busy.callHash then
    if redis.call('EXISTS', ARGV[10] .. tostring(busy.callHash)) == 0 then
      redis.call('DEL', key)
    end
  end
end
clearStaleDmBusy(KEYS[3])
clearStaleDmBusy(KEYS[4])

if redis.call('EXISTS', KEYS[1]) == 1 or redis.call('EXISTS', KEYS[2]) == 1 then
  return cjson.encode({ok=false, code='call_id_exists'})
end
if redis.call('EXISTS', KEYS[3]) == 1 then
  return cjson.encode({ok=false, code='caller_busy'})
end
if redis.call('EXISTS', KEYS[4]) == 1 then
  return cjson.encode({ok=false, code='callee_busy'})
end

local call = cjson.decode(ARGV[1])
local redisTime = redis.call('TIME')
local now = tonumber(redisTime[1]) * 1000 + math.floor(tonumber(redisTime[2]) / 1000)
call.createdAt = now
call.updatedAt = now
call.expiresAt = now + tonumber(ARGV[11])
local conn = redis.call('GET', KEYS[6])
if not conn then
  return cjson.encode({ok=false, code='connection_not_registered'})
end
local lease = cjson.decode(conn)
if tostring(lease.userId) ~= tostring(call.callerId) then
  return cjson.encode({ok=false, code='connection_not_registered'})
end
call.media[tostring(call.callerId)] = {
  connId=ARGV[6],
  connHash=ARGV[7],
  fence=1,
  checkAt=now + tonumber(ARGV[8])
}

local encoded = cjson.encode(call)
redis.call('SET', KEYS[1], encoded, 'PX', ARGV[4])
redis.call('SET', KEYS[3], ARGV[2], 'PX', ARGV[5])
redis.call('SET', KEYS[4], ARGV[3], 'PX', ARGV[5])
redis.call('ZADD', KEYS[5], call.expiresAt, ARGV[9])
return cjson.encode({ok=true, call=call})
`;

export const CREATE_LIVEKIT_GROUP_CALL_LUA = `
if redis.call('EXISTS', KEYS[1]) == 1 or redis.call('EXISTS', KEYS[2]) == 1 then
  return cjson.encode({ok=false, code='call_id_exists'})
end
if redis.call('EXISTS', KEYS[4]) == 1 then
  local chatBusy = cjson.decode(redis.call('GET', KEYS[4]))
  return cjson.encode({
    ok=false,
    code='chat_call_active',
    activeCallId=chatBusy.ownerId
  })
end

local call = cjson.decode(ARGV[1])
local redisTime = redis.call('TIME')
local now = tonumber(redisTime[1]) * 1000 + math.floor(tonumber(redisTime[2]) / 1000)
local admitted = {}
for index, uid in ipairs(call.participantOrder) do
  local busyKey = KEYS[5 + index]
  local isBusy = redis.call('EXISTS', busyKey) == 1
  if isBusy and tostring(uid) == tostring(call.hostId) then
    return cjson.encode({ok=false, code='busy', busyUserId=tostring(uid)})
  end
  if not isBusy then
    call.participants[tostring(uid)].invitedAt = now
    if tostring(uid) == tostring(call.hostId) then
      call.participants[tostring(uid)].joinedAt = now
    end
    table.insert(admitted, tostring(uid))
  else
    call.participants[tostring(uid)] = nil
  end
end
call.participantOrder = admitted
call.createdAt = now
call.updatedAt = now
call.ringingExpiresAt = now + tonumber(ARGV[5])
call.expiresAt = now + tonumber(ARGV[6])

local callTtl = tonumber(ARGV[2])
local busyTtl = tonumber(ARGV[3])
local callHash = ARGV[7]
redis.call('SET', KEYS[1], cjson.encode(call), 'PX', callTtl)
redis.call('SET', KEYS[3], tostring(call.callId), 'PX', callTtl)
redis.call('SET', KEYS[4], cjson.encode({
  kind='livekit_group',
  ownerId=tostring(call.callId),
  instanceId=ARGV[4],
  groupHash=callHash
}), 'PX', busyTtl)
for index, uid in ipairs(admitted) do
  redis.call('SET', KEYS[5 + index], cjson.encode({
    kind='livekit_group',
    ownerId=tostring(call.callId),
    instanceId=ARGV[4],
    groupHash=callHash
  }), 'PX', busyTtl)
end
redis.call('ZADD', KEYS[5], call.ringingExpiresAt, callHash)
return cjson.encode({ok=true, call=call})
`;

export const MUTATE_DM_CALL_LUA = `
local raw = redis.call('GET', KEYS[1])
if not raw then
  return cjson.encode({ok=false, code='call_not_found'})
end
local call = cjson.decode(raw)
local op = ARGV[1]
local redisTime = redis.call('TIME')
local now = tonumber(redisTime[1]) * 1000 + math.floor(tonumber(redisTime[2]) / 1000)
local uid = ARGV[3]
local connId = ARGV[4]
local connHash = ARGV[5]
local mediaType = ARGV[6]
local reason = ARGV[7]
local acceptedTtl = tonumber(ARGV[8])
local callKeyTtl = tonumber(ARGV[9])
local busyTtl = tonumber(ARGV[10])
local tombstoneTtl = tonumber(ARGV[11])
local connLease = tonumber(ARGV[12])
local callHash = ARGV[13]
local connPrefix = ARGV[14]

local function result(ok, code, extra)
  local out = extra or {}
  out.ok = ok
  if code then out.code = code end
  return cjson.encode(out)
end

local function isParticipant()
  return tostring(call.callerId) == uid or tostring(call.calleeId) == uid
end

local function connectionBelongsToUser(key)
  local connRaw = redis.call('GET', key)
  if not connRaw then return false end
  local conn = cjson.decode(connRaw)
  return tostring(conn.userId) == uid
end

local function bindMedia()
  if connId == '' or connHash == '' or not connectionBelongsToUser(KEYS[6]) then
    return false, 'connection_not_registered', false, 0
  end
  local current = call.media[uid]
  if current and tostring(current.connId) == connId then
    current.checkAt = now + connLease
    call.disconnectDeadline[uid] = nil
    return true, nil, false, tonumber(current.fence) or 1
  end
  if current and current.connHash then
    local oldKey = connPrefix .. tostring(current.connHash)
    local oldRaw = redis.call('GET', oldKey)
    if oldRaw then
      local oldLease = cjson.decode(oldRaw)
      if tostring(oldLease.userId) == uid then
        return false, 'media_owned_elsewhere', false, tonumber(current.fence) or 1
      end
    end
  end
  local fence = current and ((tonumber(current.fence) or 0) + 1) or 1
  call.media[uid] = {
    connId=connId,
    connHash=connHash,
    fence=fence,
    checkAt=now + connLease
  }
  call.disconnectDeadline[uid] = nil
  return true, nil, true, fence
end

local function busyOwnedBy(key)
  local busyRaw = redis.call('GET', key)
  if not busyRaw then return false end
  local busy = cjson.decode(busyRaw)
  return busy.kind == 'dm' and tostring(busy.ownerId) == tostring(call.callId)
end

local function nextDue()
  local due = tonumber(call.expiresAt)
  for _, deadline in pairs(call.disconnectDeadline) do
    local value = tonumber(deadline)
    if value and value < due then due = value end
  end
  for _, binding in pairs(call.media) do
    local value = tonumber(binding.checkAt)
    if value and value < due then due = value end
  end
  return due
end

if tonumber(call.expiresAt) <= now then
  return result(false, 'call_expired')
end

if not isParticipant() then
  return result(false, 'forbidden')
end

if op == 'accept' then
  if tostring(call.calleeId) ~= uid then
    return result(false, 'only_callee_can_accept')
  end
  if call.state ~= 'ringing' then
    local ok, code, changed, fence = bindMedia()
    if not ok then return result(false, code) end
    if changed then
      call.expiresAt = now + acceptedTtl
      call.updatedAt = now
      call.revision = (tonumber(call.revision) or 0) + 1
      redis.call('SET', KEYS[1], cjson.encode(call), 'PX', callKeyTtl)
      if busyOwnedBy(KEYS[3]) then redis.call('PEXPIRE', KEYS[3], busyTtl) end
      if busyOwnedBy(KEYS[4]) then redis.call('PEXPIRE', KEYS[4], busyTtl) end
      redis.call('ZADD', KEYS[5], nextDue(), callHash)
    end
    return result(true, nil, {
      call=call,
      alreadyAccepted=true,
      resumed=changed,
      fence=fence
    })
  end
  local ok, code, changed, fence = bindMedia()
  if not ok then return result(false, code) end
  call.state = 'accepted'
  call.disconnectDeadline = {}
  call.expiresAt = now + acceptedTtl
  call.updatedAt = now
  call.revision = (tonumber(call.revision) or 0) + 1
  redis.call('SET', KEYS[1], cjson.encode(call), 'PX', callKeyTtl)
  if busyOwnedBy(KEYS[3]) then redis.call('PEXPIRE', KEYS[3], busyTtl) end
  if busyOwnedBy(KEYS[4]) then redis.call('PEXPIRE', KEYS[4], busyTtl) end
  redis.call('ZADD', KEYS[5], nextDue(), callHash)
  return result(true, nil, {call=call, resumed=changed, fence=fence})
end

if op == 'resume' then
  local changed = false
  local fence = 0
  if call.state == 'accepted' then
    local ok, code, didChange, newFence = bindMedia()
    if not ok then return result(false, code, {call=call}) end
    changed = didChange
    fence = newFence
    call.expiresAt = now + acceptedTtl
    call.updatedAt = now
    call.revision = (tonumber(call.revision) or 0) + 1
  end
  redis.call('SET', KEYS[1], cjson.encode(call), 'PX', callKeyTtl)
  if busyOwnedBy(KEYS[3]) then redis.call('PEXPIRE', KEYS[3], busyTtl) end
  if busyOwnedBy(KEYS[4]) then redis.call('PEXPIRE', KEYS[4], busyTtl) end
  redis.call('ZADD', KEYS[5], nextDue(), callHash)
  return result(true, nil, {call=call, resumed=changed, fence=fence})
end

if op == 'media' then
  if call.state ~= 'accepted' then
    return result(false, 'call_not_accepted')
  end
  local ok, code, _, fence = bindMedia()
  if not ok then return result(false, code) end
  if mediaType == 'audio' or mediaType == 'video' then
    call.mediaType = mediaType
  end
  call.expiresAt = now + acceptedTtl
  call.updatedAt = now
  call.revision = (tonumber(call.revision) or 0) + 1
  redis.call('SET', KEYS[1], cjson.encode(call), 'PX', callKeyTtl)
  if busyOwnedBy(KEYS[3]) then redis.call('PEXPIRE', KEYS[3], busyTtl) end
  if busyOwnedBy(KEYS[4]) then redis.call('PEXPIRE', KEYS[4], busyTtl) end
  redis.call('ZADD', KEYS[5], nextDue(), callHash)
  return result(true, nil, {call=call, fence=fence})
end

if op == 'terminate' or op == 'reject' then
  if op == 'reject' and call.state ~= 'ringing' then
    return result(false, 'call_already_accepted')
  end
  if call.state == 'accepted' then
    local binding = call.media[uid]
    if binding and tostring(binding.connId) ~= connId and binding.connHash then
      local oldRaw = redis.call('GET', connPrefix .. tostring(binding.connHash))
      if oldRaw then
        local oldLease = cjson.decode(oldRaw)
        if tostring(oldLease.userId) == uid then
          return result(false, 'media_owned_elsewhere')
        end
      end
    end
  end
  call.state = 'ended'
  call.reason = reason
  call.endedAt = now
  call.updatedAt = now
  call.revision = (tonumber(call.revision) or 0) + 1
  redis.call('DEL', KEYS[1])
  if busyOwnedBy(KEYS[3]) then redis.call('DEL', KEYS[3]) end
  if busyOwnedBy(KEYS[4]) then redis.call('DEL', KEYS[4]) end
  redis.call('SET', KEYS[2], cjson.encode(call), 'PX', tombstoneTtl)
  redis.call('ZREM', KEYS[5], callHash)
  return result(true, nil, {call=call})
end

return result(false, 'unsupported_operation')
`;

export const HEARTBEAT_CONNECTION_LUA = `
local connRaw = redis.call('GET', KEYS[1])
if not connRaw then return 0 end
local conn = cjson.decode(connRaw)
if tostring(conn.userId) ~= ARGV[1] then return 0 end
local redisTime = redis.call('TIME')
local now = tonumber(redisTime[1]) * 1000 + math.floor(tonumber(redisTime[2]) / 1000)
conn.instanceId = ARGV[2]
conn.expiresAt = now + tonumber(ARGV[4])
redis.call('SET', KEYS[1], cjson.encode(conn), 'PX', ARGV[4])

local busyRaw = redis.call('GET', KEYS[2])
if not busyRaw then return 1 end
local busy = cjson.decode(busyRaw)
if busy.kind ~= 'dm' then
  redis.call('PEXPIRE', KEYS[2], ARGV[5])
  return 1
end

local callRaw = redis.call('GET', KEYS[3])
if not callRaw then
  redis.call('DEL', KEYS[2])
  return 1
end
local call = cjson.decode(callRaw)
if tostring(call.callId) ~= tostring(busy.ownerId) then return 1 end
local binding = call.media[ARGV[1]]
if binding and tostring(binding.connId) == ARGV[6] then
  binding.checkAt = now + tonumber(ARGV[4])
  call.disconnectDeadline[ARGV[1]] = nil
  if call.state == 'accepted' then
    call.expiresAt = now + tonumber(ARGV[7])
  end
  redis.call('SET', KEYS[3], cjson.encode(call), 'PX', ARGV[8])
  redis.call('PEXPIRE', KEYS[2], ARGV[9])
  local due = tonumber(call.expiresAt)
  for _, deadline in pairs(call.disconnectDeadline) do
    local value = tonumber(deadline)
    if value and value < due then due = value end
  end
  for _, media in pairs(call.media) do
    local value = tonumber(media.checkAt)
    if value and value < due then due = value end
  end
  redis.call('ZADD', KEYS[4], due, ARGV[10])
end
return 1
`;

export const UNREGISTER_CONNECTION_LUA = `
local connRaw = redis.call('GET', KEYS[1])
if connRaw then
  local conn = cjson.decode(connRaw)
  if tostring(conn.userId) == ARGV[1] then redis.call('DEL', KEYS[1]) end
end
local callRaw = redis.call('GET', KEYS[3])
if not callRaw then return cjson.encode({wasMedia=false}) end
local call = cjson.decode(callRaw)
local busyRaw = redis.call('GET', KEYS[2])
if not busyRaw then return cjson.encode({wasMedia=false}) end
local busy = cjson.decode(busyRaw)
if busy.kind ~= 'dm' or tostring(busy.ownerId) ~= tostring(call.callId) then
  return cjson.encode({wasMedia=false})
end
local binding = call.media[ARGV[1]]
if not binding or tostring(binding.connId) ~= ARGV[2] then
  return cjson.encode({wasMedia=false, call=call})
end
local redisTime = redis.call('TIME')
local now = tonumber(redisTime[1]) * 1000 + math.floor(tonumber(redisTime[2]) / 1000)
local grace = call.state == 'accepted' and tonumber(ARGV[4]) or tonumber(ARGV[5])
call.disconnectDeadline[ARGV[1]] = now + grace
binding.checkAt = now + grace
call.updatedAt = now
call.revision = (tonumber(call.revision) or 0) + 1
redis.call('SET', KEYS[3], cjson.encode(call), 'PX', ARGV[6])
redis.call('ZADD', KEYS[4], now + grace, ARGV[7])
return cjson.encode({wasMedia=true, call=call})
`;

export const ACQUIRE_BUSY_LUA = `
local currentRaw = redis.call('GET', KEYS[1])
if currentRaw then
  local current = cjson.decode(currentRaw)
  if current.kind == ARGV[1] and tostring(current.ownerId) == ARGV[2] then
    redis.call('PEXPIRE', KEYS[1], ARGV[4])
    return cjson.encode({ok=true, acquired=false})
  end
  return cjson.encode({ok=false, code='busy'})
end
redis.call('SET', KEYS[1], ARGV[3], 'PX', ARGV[4])
return cjson.encode({ok=true, acquired=true})
`;

export const RELEASE_BUSY_LUA = `
local currentRaw = redis.call('GET', KEYS[1])
if not currentRaw then return 0 end
local current = cjson.decode(currentRaw)
if current.kind == ARGV[1] and tostring(current.ownerId) == ARGV[2] then
  redis.call('DEL', KEYS[1])
  return 1
end
return 0
`;

export const SWEEP_DM_CALL_LUA = `
local raw = redis.call('GET', KEYS[1])
if not raw then
  redis.call('ZREM', KEYS[5], ARGV[1])
  return cjson.encode({ok=true})
end
local call = cjson.decode(raw)
local redisTime = redis.call('TIME')
local now = tonumber(redisTime[1]) * 1000 + math.floor(tonumber(redisTime[2]) / 1000)
local acceptedGrace = tonumber(ARGV[3])
local ringingGrace = tonumber(ARGV[4])
local callKeyTtl = tonumber(ARGV[5])
local tombstoneTtl = tonumber(ARGV[6])
local reason = nil
local changed = false

local users = {tostring(call.callerId), tostring(call.calleeId)}
local connKeys = {KEYS[6], KEYS[7]}
local expectedConnHashes = {ARGV[7], ARGV[8]}
for index, uid in ipairs(users) do
  local binding = call.media[uid]
  if binding then
    if tostring(binding.connHash or '') ~= tostring(expectedConnHashes[index] or '') then
      redis.call('ZADD', KEYS[5], now, ARGV[1])
      return cjson.encode({ok=true, retry=true})
    end
    local alive = false
    local connRaw = redis.call('GET', connKeys[index])
    if connRaw then
      local conn = cjson.decode(connRaw)
      alive = tostring(conn.userId) == uid and tostring(conn.connId) == tostring(binding.connId)
    end
    if alive then
      if call.disconnectDeadline[uid] then
        call.disconnectDeadline[uid] = nil
        changed = true
      end
      local ttl = redis.call('PTTL', connKeys[index])
      if ttl and ttl > 0 then
        binding.checkAt = now + ttl
        changed = true
      end
    elseif not call.disconnectDeadline[uid] then
      local grace = call.state == 'accepted' and acceptedGrace or ringingGrace
      call.disconnectDeadline[uid] = now + grace
      binding.checkAt = now + grace
      changed = true
    end
  end
end

for _, deadline in pairs(call.disconnectDeadline) do
  if tonumber(deadline) <= now then reason = 'disconnected' end
end
if not reason and tonumber(call.expiresAt) <= now then
  reason = call.state == 'ringing' and 'ringing_timeout' or 'call_ttl'
end

local function busyOwnedBy(key)
  local busyRaw = redis.call('GET', key)
  if not busyRaw then return false end
  local busy = cjson.decode(busyRaw)
  return busy.kind == 'dm' and tostring(busy.ownerId) == tostring(call.callId)
end

if reason then
  call.state = 'ended'
  call.reason = reason
  call.endedAt = now
  call.updatedAt = now
  call.revision = (tonumber(call.revision) or 0) + 1
  redis.call('DEL', KEYS[1])
  if busyOwnedBy(KEYS[3]) then redis.call('DEL', KEYS[3]) end
  if busyOwnedBy(KEYS[4]) then redis.call('DEL', KEYS[4]) end
  redis.call('SET', KEYS[2], cjson.encode(call), 'PX', tombstoneTtl)
  redis.call('ZREM', KEYS[5], ARGV[1])
  return cjson.encode({ok=true, ended=call})
end

local due = tonumber(call.expiresAt)
for _, deadline in pairs(call.disconnectDeadline) do
  local value = tonumber(deadline)
  if value and value < due then due = value end
end
for _, binding in pairs(call.media) do
  local value = tonumber(binding.checkAt)
  if value and value < due then due = value end
end
if changed then redis.call('SET', KEYS[1], cjson.encode(call), 'PX', callKeyTtl) end
redis.call('ZADD', KEYS[5], due, ARGV[1])
return cjson.encode({ok=true})
`;
