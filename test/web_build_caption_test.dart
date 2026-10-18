import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/widgets/web_build_caption.dart';

void main() {
  test('подпись собирает версию и дату сборки', () {
    expect(
      webBuildCaption(
        version: '1.0.0',
        buildNumber: '6',
        buildId: 'abc123420261018175400',
      ),
      'Версия 1.0.0+6\nСборка 18.10.2026 17:54 UTC · abc1234',
    );
  });

  test('без штампа остаётся только версия', () {
    expect(
      webBuildCaption(version: '1.0.0', buildNumber: '6', buildId: null),
      'Версия 1.0.0+6',
    );
    expect(
      webBuildCaption(
        version: '1.0.0',
        buildNumber: '6',
        buildId: 'FLUTTER_BUILD_ID',
      ),
      'Версия 1.0.0+6',
    );
  });
}
