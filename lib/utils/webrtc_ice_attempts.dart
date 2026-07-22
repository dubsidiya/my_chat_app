/// Порядок попыток iceServers для createPeerConnection.
///
/// Всегда сначала полный набор (со STUN+TURN с сервера), затем STUN-only,
/// затем дефолты. Раньше на Android предпочитали STUN-only — «живой» native PC
/// без TURN оставлял звонки без relay за NAT.
List<List<Map<String, dynamic>>> buildIceServerAttempts({
  required List<Map<String, dynamic>> full,
  required List<Map<String, dynamic>> stunOnly,
  required List<Map<String, dynamic>> defaults,
}) {
  final out = <List<Map<String, dynamic>>>[];
  if (full.isNotEmpty) out.add(full);
  if (stunOnly.isNotEmpty) out.add(stunOnly);
  if (defaults.isNotEmpty) out.add(defaults);
  if (out.isEmpty) out.add(defaults);
  return out;
}
