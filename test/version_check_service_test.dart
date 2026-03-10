import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/services/version_check_service.dart';

void main() {
  group('VersionCheckService.compareVersions', () {
    test('равные версии', () {
      expect(VersionCheckService.compareVersions('1.0.0', '1.0.0'), 0);
      expect(VersionCheckService.compareVersions('2.10.3', '2.10.3'), 0);
    });

    test('первая меньше второй', () {
      expect(VersionCheckService.compareVersions('1.0.0', '1.0.1'), lessThan(0));
      expect(VersionCheckService.compareVersions('1.0.9', '1.1.0'), lessThan(0));
      expect(VersionCheckService.compareVersions('0.9.9', '1.0.0'), lessThan(0));
    });

    test('первая больше второй', () {
      expect(VersionCheckService.compareVersions('1.0.1', '1.0.0'), greaterThan(0));
      expect(VersionCheckService.compareVersions('1.1.0', '1.0.9'), greaterThan(0));
      expect(VersionCheckService.compareVersions('2.0.0', '1.9.9'), greaterThan(0));
    });

    test('формат с build number (1.0.0+1) игнорируется', () {
      expect(VersionCheckService.compareVersions('1.0.0+1', '1.0.0'), 0);
      expect(VersionCheckService.compareVersions('1.0.0+10', '1.0.0+2'), 0);
    });

    test('неполные версии дополняются нулями', () {
      expect(VersionCheckService.compareVersions('1', '1.0.0'), 0);
      expect(VersionCheckService.compareVersions('1.1', '1.1.0'), 0);
      expect(VersionCheckService.compareVersions('2', '1.9.9'), greaterThan(0));
    });

    test('пустые строки трактуются как 0.0.0', () {
      expect(VersionCheckService.compareVersions('', ''), 0);
      expect(VersionCheckService.compareVersions('', '1.0.0'), lessThan(0));
      expect(VersionCheckService.compareVersions('1.0.0', ''), greaterThan(0));
    });

    test('нечисловые части считаются нулём', () {
      expect(VersionCheckService.compareVersions('1.x.0', '1.0.0'), 0);
    });
  });
}
