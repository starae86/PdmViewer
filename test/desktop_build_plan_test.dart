import 'package:flutter_test/flutter_test.dart';

import '../tooling/build_desktop.dart';

void main() {
  test(
    'Windows resolves native architecture and preserves default output paths',
    () {
      for (final arch in ['x64', 'arm64']) {
        final plan = createDesktopBuildPlan(
          platform: 'windows',
          arch: 'native',
          hostArch: arch,
        );
        expect(plan.arch, arch);
        expect(plan.output, 'build/windows/$arch/runner/Release');
        expect(plan.arguments, ['build', 'windows', '--release']);
        expect(plan.environment, isEmpty);
        expect(() => plan.validateHost('windows', arch), returnsNormally);
        expect(() => plan.validateHost('macos', arch), throwsArgumentError);
        expect(
          () => plan.validateHost('windows', arch == 'x64' ? 'arm64' : 'x64'),
          throwsArgumentError,
        );
      }
    },
  );

  test('macOS uses explicit Xcode architecture settings for each target', () {
    for (final entry in {
      'x64': 'x86_64',
      'arm64': 'arm64',
      'universal': 'x86_64 arm64',
    }.entries) {
      final plan = createDesktopBuildPlan(
        platform: 'macos',
        arch: entry.key,
        hostArch: 'arm64',
      );
      expect(plan.environment['FLUTTER_XCODE_ARCHS'], entry.value);
      expect(plan.environment['FLUTTER_XCODE_ONLY_ACTIVE_ARCH'], 'NO');
      expect(plan.environment['FLUTTER_XCODE_EXCLUDED_ARCHS'], '');
      expect(plan.output, 'build/macos/Build/Products/Release/PdmViewer.app');
      expect(() => plan.validateHost('macos', 'x64'), returnsNormally);
      expect(() => plan.validateHost('macos', 'arm64'), returnsNormally);
      expect(() => plan.validateHost('windows', 'arm64'), throwsArgumentError);
    }
  });

  test('rejects unsupported targets instead of mislabeling builds', () {
    for (final platform in ['windows', 'macos']) {
      for (final arch in ['x86', 'ia32', 'arm', 'invalid']) {
        expect(
          () => createDesktopBuildPlan(
            platform: platform,
            arch: arch,
            hostArch: 'x64',
          ),
          throwsArgumentError,
        );
      }
    }
    expect(
      () => createDesktopBuildPlan(
        platform: 'windows',
        arch: 'universal',
        hostArch: 'x64',
      ),
      throwsArgumentError,
    );
    expect(
      () => createDesktopBuildPlan(
        platform: 'linux',
        arch: 'x64',
        hostArch: 'x64',
      ),
      throwsArgumentError,
    );
  });
}
