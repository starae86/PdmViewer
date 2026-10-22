import 'dart:io';

import 'package:path/path.dart' as path;

import '../../domain/models/reverse_models.dart';

class JavaRuntimeResolver {
  Future<JavaRuntimeResolution> resolve({String? preferredJdkHome}) async {
    final candidates = <_JavaCandidate>[
      if ((preferredJdkHome ?? '').trim().isNotEmpty)
        _JavaCandidate.fromJdkHome(preferredJdkHome!.trim()),
      if ((Platform.environment['JAVA_HOME'] ?? '').trim().isNotEmpty)
        _JavaCandidate.fromJdkHome(Platform.environment['JAVA_HOME']!.trim()),
      const _JavaCandidate.fromCommand('java', 'javac'),
    ];

    JavaRuntimeResolutionException? lastError;
    for (final candidate in candidates) {
      try {
        return await _validateCandidate(candidate);
      } on JavaRuntimeResolutionException catch (error) {
        lastError = error;
      }
    }

    throw lastError ??
        const JavaRuntimeResolutionException(
          JavaRuntimeProblem.notFound,
          '未找到可用的 Java 运行时，请先配置 JDK 8+。',
        );
  }

  Future<JavaRuntimeResolution> validateJdkHome(String jdkHome) {
    return _validateCandidate(_JavaCandidate.fromJdkHome(jdkHome));
  }

  Future<JavaRuntimeResolution> _validateCandidate(_JavaCandidate candidate) async {
    final javaExecutable = candidate.javaExecutablePath;
    final javacExecutable = candidate.javacExecutablePath;

    if (!_commandLooksRunnable(javaExecutable) ||
        !_commandLooksRunnable(javacExecutable)) {
      throw const JavaRuntimeResolutionException(
        JavaRuntimeProblem.notFound,
        '未找到可用的 java/javac，可手动指定 JDK 8+ 目录。',
      );
    }

    final javaVersion = await _readVersion(javaExecutable, 'java');
    final javacVersion = await _readVersion(javacExecutable, 'javac');
    final major = _parseJavaMajorVersion(javaVersion);
    if (major == null) {
      throw JavaRuntimeResolutionException(
        JavaRuntimeProblem.notFound,
        '无法识别 Java 版本：$javaVersion',
      );
    }
    if (major < 8) {
      throw JavaRuntimeResolutionException(
        JavaRuntimeProblem.versionTooLow,
        '检测到 Java 版本为 $major，要求 JDK 8+。',
      );
    }

    final compilerMajor = _parseJavaMajorVersion(javacVersion);
    if (compilerMajor == null) {
      throw JavaRuntimeResolutionException(
        JavaRuntimeProblem.missingCompiler,
        '未检测到可用的 javac，当前目录不是完整 JDK。',
      );
    }

    return JavaRuntimeResolution(
      javaExecutablePath: javaExecutable,
      javacExecutablePath: javacExecutable,
      versionText: javaVersion,
      majorVersion: major,
      jdkHome: candidate.jdkHome,
    );
  }

  bool _commandLooksRunnable(String command) {
    if (command.trim().isEmpty) {
      return false;
    }
    if (!command.contains(path.separator)) {
      return true;
    }
    return File(command).existsSync();
  }

  Future<String> _readVersion(String executable, String displayName) async {
    try {
      final result = await Process.run(executable, const ['-version']);
      final raw = '${result.stderr}\n${result.stdout}'.trim();
      if (result.exitCode != 0 || raw.isEmpty) {
        throw JavaRuntimeResolutionException(
          JavaRuntimeProblem.notFound,
          '无法执行 $displayName -version。',
        );
      }
      return raw;
    } on ProcessException {
      throw const JavaRuntimeResolutionException(
        JavaRuntimeProblem.notFound,
        '未找到可用的 Java 运行时，请先配置 JDK 8+。',
      );
    }
  }

  int? _parseJavaMajorVersion(String versionOutput) {
    final match = RegExp(r'version\s+"([^"]+)"').firstMatch(versionOutput) ??
        RegExp(r'javac\s+([^\s]+)').firstMatch(versionOutput);
    final rawVersion = match?.group(1)?.trim();
    if (rawVersion == null || rawVersion.isEmpty) {
      return null;
    }
    final parts = rawVersion.split('.');
    if (parts.first == '1' && parts.length > 1) {
      return int.tryParse(parts[1]);
    }
    return int.tryParse(parts.first);
  }
}

class _JavaCandidate {
  const _JavaCandidate({
    required this.javaExecutablePath,
    required this.javacExecutablePath,
    this.jdkHome,
  });

  const _JavaCandidate.fromCommand(this.javaExecutablePath, this.javacExecutablePath)
      : jdkHome = null;

  factory _JavaCandidate.fromJdkHome(String jdkHome) {
    final binDirectory = path.join(jdkHome, 'bin');
    final suffix = Platform.isWindows ? '.exe' : '';
    return _JavaCandidate(
      javaExecutablePath: path.join(binDirectory, 'java$suffix'),
      javacExecutablePath: path.join(binDirectory, 'javac$suffix'),
      jdkHome: jdkHome,
    );
  }

  final String javaExecutablePath;
  final String javacExecutablePath;
  final String? jdkHome;
}
