class LinkPreview {
  final String url;
  final String title;
  final String? imageUrl;
  final String? siteName;
  final String fetchedAtIso;

  LinkPreview({
    required this.url,
    required this.title,
    this.imageUrl,
    this.siteName,
    required this.fetchedAtIso,
  });

  factory LinkPreview.fromJson(Map<String, dynamic> json) {
    return LinkPreview(
      url: (json['url'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      imageUrl: json['imageUrl']?.toString() ?? json['image_url']?.toString(),
      siteName: json['siteName']?.toString() ?? json['site_name']?.toString(),
      fetchedAtIso: (json['fetchedAtIso'] ?? json['fetched_at'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'title': title,
      'imageUrl': imageUrl,
      'siteName': siteName,
      'fetchedAtIso': fetchedAtIso,
    };
  }
}

