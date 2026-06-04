/// Преподаватель для фильтра «Все отчёты» (бухгалтерия).
class ReportAuthorOption {
  final int id;
  final String label;

  const ReportAuthorOption({required this.id, required this.label});

  factory ReportAuthorOption.fromJson(Map<String, dynamic> json) {
    final idRaw = json['id'];
    final id = idRaw is int
        ? idRaw
        : idRaw is num
            ? idRaw.toInt()
            : int.tryParse(idRaw?.toString() ?? '');
    if (id == null) {
      throw const FormatException('Invalid report author id');
    }
    final label = (json['label'] ?? json['display_name'] ?? json['email'] ?? '')
        .toString()
        .trim();
    return ReportAuthorOption(
      id: id,
      label: label.isNotEmpty ? label : '#$id',
    );
  }
}
