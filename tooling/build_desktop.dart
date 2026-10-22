import 'dart:ffi';
import 'dart:io';

const _usage = '''
Build PdmViewer in Flutter's default output directory.

  dart run tooling/build_desktop.dart [options]

  --platform=windows|macos  Defaults to the current platform.
  --arch=native|x64|arm64|universal
                          Defaults to native on Windows, universal on macOS.
  --dry-run               Print the build plan without running Flutter.
  --help                  Show this help.

Windows: use a Flutter/Dart SDK matching the target architecture.
macOS: x64 = Intel, arm64 = Apple Silicon, universal = both.
32-bit x86 and ARM are not supported.
''';

class DesktopBuildPlan {
  const DesktopBuildPlan({
    required this.platform,
    required this.arch,
    required this.environment,
    required this.output,
  });

  final String platform;
  final String arch;
  final Map<String, String> environment;
  final String output;

  List<String> get arguments => ['build', platform, '--release'];

  void validateHost(String hostPlatform, String hostArch) {
    if (platform != hostPlatform) {
      throw ArgumentError(
        'Build $platform on a $platform host, not $hostPlatform.',
      );
    }
    if (platform == 'windows' && arch != hostArch) {
      throw ArgumentError(
        'Windows target $arch requires a matching Flutter/Dart SDK. '
        'The current Dart runtime is $hostArch. '
        'For ARM64 use Windows on ARM and a native ARM64 Flutter SDK; '
        'an emulated x64 SDK builds x64, not ARM64.',
      );
    }
  }
}

DesktopBuildPlan createDesktopBuildPlan({
  required String platform,
  required String arch,
  required String hostArch,
}) {
  if (!['windows', 'macos'].contains(platform)) {
    throw ArgumentError(
      'Supported platforms: windows, macos. Linux is not configured in this project.',
    );
  }
  if (arch == 'x86' || arch == 'ia32' || arch == 'arm') {
    throw ArgumentError('32-bit $arch is not supported. Use x64 or arm64.');
  }
  final resolvedArch = arch == 'native' ? hostArch : arch;
  if (!['x64', 'arm64', 'universal'].contains(resolvedArch)) {
    throw ArgumentError('Unsupported architecture: $resolvedArch');
  }
  if (platform == 'windows') {
    if (resolvedArch == 'universal') {
      throw ArgumentError('Windows needs separate x64 and arm64 builds.');
    }
    return DesktopBuildPlan(
      platform: platform,
      arch: resolvedArch,
      environment: const {},
      output: 'build/windows/$resolvedArch/runner/Release',
    );
  }
  return DesktopBuildPlan(
    platform: platform,
    arch: resolvedArch,
    environment: {
      // Flutter forwards FLUTTER_XCODE_* variables to xcodebuild settings.
      'FLUTTER_XCODE_ARCHS': switch (resolvedArch) {
        'x64' => 'x86_64',
        'arm64' => 'arm64',
        _ => 'x86_64 arm64',
      },
      'FLUTTER_XCODE_ONLY_ACTIVE_ARCH': 'NO',
      'FLUTTER_XCODE_EXCLUDED_ARCHS': '',
    },
    output: 'build/macos/Build/Products/Release/PdmViewer.app',
  );
}

String _hostArch() => switch (Abi.current()) {
  Abi.windowsX64 || Abi.macosX64 => 'x64',
  Abi.windowsArm64 || Abi.macosArm64 => 'arm64',
  _ => 'unknown',
};

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.write(_usage);
    return;
  }
  try {
    final options = <String, String>{};
    var dryRun = false;
    for (final argument in args) {
      if (argument == '--dry-run') {
        dryRun = true;
        continue;
      }
      final match = RegExp(r'^--(platform|arch)=(.+)$').firstMatch(argument);
      if (match == null) {
        throw ArgumentError('Unknown option: $argument\n$_usage');
      }
      final key = match.group(1)!;
      if (options.containsKey(key)) {
        throw ArgumentError('Duplicate option: --$key');
      }
      options[key] = match.group(2)!;
    }
    final host = Platform.operatingSystem;
    final hostArch = _hostArch();
    final platform = options['platform'] ?? host;
    final plan = createDesktopBuildPlan(
      platform: platform,
      arch: options['arch'] ?? (platform == 'macos' ? 'universal' : 'native'),
      hostArch: hostArch,
    );
    final root = Directory.fromUri(Platform.script.resolve('../'));
    if (!File.fromUri(root.uri.resolve('pubspec.yaml')).existsSync()) {
      throw StateError('Cannot locate the project root.');
    }
    stdout.writeln('PdmViewer: ${plan.platform} / ${plan.arch} / release');
    stdout.writeln('Project: ${root.path}');
    for (final entry in plan.environment.entries) {
      stdout.writeln('${entry.key}=${entry.value}');
    }
    stdout.writeln('flutter ${plan.arguments.join(' ')}');
    stdout.writeln('Output: ${plan.output}');
    if (dryRun) {
      stdout.writeln(
        'Dry run only. No build performed; host and toolchain not validated.',
      );
      return;
    }
    plan.validateHost(host, hostArch);

    // Use the Flutter SDK owning this Dart runtime to keep Windows ABI detection consistent.
    final flutterBin = File(
      Platform.resolvedExecutable,
    ).parent.parent.parent.parent;
    final flutter = File.fromUri(
      flutterBin.uri.resolve(Platform.isWindows ? 'flutter.bat' : 'flutter'),
    );
    if (!flutter.existsSync()) {
      throw StateError(
        'Run this script with the Dart executable bundled in Flutter (Flutter bin on PATH).',
      );
    }
    final process = await Process.start(
      flutter.path,
      plan.arguments,
      workingDirectory: root.path,
      environment: plan.environment,
      runInShell: Platform.isWindows,
      mode: ProcessStartMode.inheritStdio,
    );
    final result = await process.exitCode;
    if (result != 0) {
      exitCode = result;
      return;
    }
    final output = Directory.fromUri(root.uri.resolve('${plan.output}/'));
    final executable = plan.platform == 'windows'
        ? File.fromUri(output.uri.resolve('PdmViewer.exe'))
        : File.fromUri(output.uri.resolve('Contents/MacOS/PdmViewer'));
    if (!executable.existsSync()) {
      throw StateError('Missing built executable: ${executable.path}');
    }
    if (plan.platform == 'macos') {
      final check = await Process.run('lipo', [
        '-verify_arch',
        ...plan.environment['FLUTTER_XCODE_ARCHS']!.split(' '),
        executable.path,
      ]);
      if (check.exitCode != 0) {
        throw StateError(
          'macOS executable architecture verification failed: ${check.stderr}',
        );
      }
    } else {
      final bytes = await executable.readAsBytes();
      if (bytes.length < 64 || bytes[0] != 0x4d || bytes[1] != 0x5a) {
        throw StateError('Invalid Windows executable.');
      }
      final offset =
          bytes[0x3c] |
          bytes[0x3d] << 8 |
          bytes[0x3e] << 16 |
          bytes[0x3f] << 24;
      if (offset < 0 ||
          offset + 6 > bytes.length ||
          bytes[offset] != 0x50 ||
          bytes[offset + 1] != 0x45 ||
          bytes[offset + 2] != 0 ||
          bytes[offset + 3] != 0) {
        throw StateError('Invalid Windows PE header.');
      }
      final machine = bytes[offset + 4] | bytes[offset + 5] << 8;
      if (machine != (plan.arch == 'arm64' ? 0xaa64 : 0x8664)) {
        throw StateError(
          'Built EXE does not match requested architecture ${plan.arch}.',
        );
      }
    }
    stdout.writeln(
      'Build and executable architecture check complete: ${output.path}',
    );
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
