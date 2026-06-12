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

/// Пункт выбора преподавателя в фильтре «Все отчёты» (id == null — все).
class ReportTeacherFilterOption {
  final int? id;
  final String label;

  const ReportTeacherFilterOption({required this.id, required this.label});

  static const all = ReportTeacherFilterOption(
    id: null,
    label: 'Все преподаватели',
  );

  factory ReportTeacherFilterOption.fromAuthor(ReportAuthorOption author) {
    return ReportTeacherFilterOption(id: author.id, label: author.label);
  }
}

List<ReportTeacherFilterOption> filterReportTeachers(
  List<ReportAuthorOption> teachers,
  String query,
) {
  final q = query.trim().toLowerCase();
  final picks = <ReportTeacherFilterOption>[];
  if (q.isEmpty ||
      ReportTeacherFilterOption.all.label.toLowerCase().contains(q)) {
    picks.add(ReportTeacherFilterOption.all);
  }
  for (final teacher in teachers) {
    if (q.isEmpty || teacher.label.toLowerCase().contains(q)) {
      picks.add(ReportTeacherFilterOption.fromAuthor(teacher));
    }
  }
  return picks;
}
