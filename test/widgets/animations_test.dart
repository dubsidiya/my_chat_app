import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/utils/page_routes.dart';
import 'package:my_chat_app/widgets/fade_scale_in.dart';
import 'package:my_chat_app/widgets/skeleton_placeholder.dart';

void main() {
  testWidgets('FadeScaleIn animates child', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FadeScaleIn(
            child: Text('test'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('test'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('test'), findsOneWidget);
  });

  testWidgets('SkeletonPlaceholder builds', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SkeletonPlaceholder(
            width: 100,
            height: 100,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(SkeletonPlaceholder), findsOneWidget);
  });

  testWidgets('slideAndFadeRoute returns route with page', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox.shrink()),
      ),
    );
    final context = tester.element(find.byType(MaterialApp));
    final route = slideAndFadeRoute<void>(
      page: const Scaffold(body: Text('page')),
    );
    expect(route, isA<PageRouteBuilder<void>>());
    final page = route.pageBuilder(
      context,
      const AlwaysStoppedAnimation(1.0),
      const AlwaysStoppedAnimation(0.0),
    );
    expect(page, isA<Scaffold>());
  });
}
