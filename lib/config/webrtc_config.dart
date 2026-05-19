/// Default ICE servers when /calls/ice-servers is unavailable.
class WebRtcConfig {
  WebRtcConfig._();

  static const List<Map<String, dynamic>> defaultIceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];
}
