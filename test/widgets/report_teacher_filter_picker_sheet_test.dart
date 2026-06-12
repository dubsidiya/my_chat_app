import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/models/report_author_option.dart';
import 'package:my_chat_app/widgets/report_teacher_filter_picker_sheet.dart';

void main() {
  const teachers = [
    ReportAuthorOption(id: 1, label: 'Иванов Иван'),
    ReportAuthorOption(id: 2, label: 'Петрова Мария'),
    ReportAuthorOption(id: 3, label: 'Сидоров Алексей'),
  ];

  Future<void> openPickerSheet(
    WidgetTester tester, {
    int? selectedId,
    required void Function(BuildContext context) onReady,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            onReady(context);
            return Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  showModalBottomSheet<ReportTeacherFilterOption>(
                    context: context,
                    builder: (_) => ReportTeacherFilterPickerSheet(
                      teachers: teachers,
                      selectedId: selectedId,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows all teachers and search field', (tester) async {
    await openPickerSheet(tester, onReady: (_) {});
    expect(find.text('Поиск преподавателя'), findsOneWidget);
    expect(find.text('Все преподаватели'), findsOneWidget);
    expect(find.text('Иванов Иван'), findsOneWidget);
    expect(find.text('Петрова Мария'), findsOneWidget);
  });

  testWidgets('filters list when typing', (tester) async {
    await openPickerSheet(tester, onReady: (_) {});
    await tester.enterText(find.byType(TextField), 'мар');
    await tester.pump();
    expect(find.text('Петрова Мария'), findsOneWidget);
    expect(find.text('Иванов Иван'), findsNothing);
    expect(find.text('Преподаватели не найдены'), findsNothing);
  });

  testWidgets('shows empty state for unknown query', (tester) async {
    await openPickerSheet(tester, onReady: (_) {});
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('Преподаватели не найдены'), findsOneWidget);
  });

  testWidgets('returns selected teacher', (tester) async {
    ReportTeacherFilterOption? result;
    late BuildContext hostContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            hostContext = context;
            return Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await showModalBottomSheet<ReportTeacherFilterOption>(
                    context: hostContext,
                    builder: (_) => const ReportTeacherFilterPickerSheet(
                      teachers: teachers,
                      selectedId: null,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Петрова Мария'));
    await tester.pumpAndSettle();
    expect(result?.id, 2);
    expect(result?.label, 'Петрова Мария');
  });

  testWidgets('returns all option', (tester) async {
    ReportTeacherFilterOption? result;
    late BuildContext hostContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            hostContext = context;
            return Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await showModalBottomSheet<ReportTeacherFilterOption>(
                    context: hostContext,
                    builder: (_) => const ReportTeacherFilterPickerSheet(
                      teachers: teachers,
                      selectedId: 1,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Все преподаватели'));
    await tester.pumpAndSettle();
    expect(result, ReportTeacherFilterOption.all);
  });
}
