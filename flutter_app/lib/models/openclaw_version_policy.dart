import 'package:pub_semver/pub_semver.dart';

enum OpenClawReleaseChannel {
  stable,
  experimental,
  historical,
}

enum OpenClawNodeValidationStatus {
  verified,
  unsupported,
  unknown,
}

/// OpenClaw 版本通道固定策略，避免网络失败时改变默认稳定版本。
class OpenClawReleasePolicy {
  static const String minimumVisibleVersion = '2026.3.13';
  static const String stableVersion = '2026.3.23';
  static const String knownLatestVersion = '2026.7.1';
  static const String stableNodeRequirement = '>=22.16.0';

  static OpenClawReleaseChannel channelFor(
    String version, {
    String? experimentalVersion,
  }) {
    final normalized = version.trim();
    if (normalized == stableVersion) {
      return OpenClawReleaseChannel.stable;
    }
    final latest = experimentalVersion?.trim().isNotEmpty == true
        ? experimentalVersion!.trim()
        : knownLatestVersion;
    if (normalized == latest) {
      return OpenClawReleaseChannel.experimental;
    }
    return OpenClawReleaseChannel.historical;
  }

  static List<String> orderVersions(
    Iterable<String> versions, {
    String? experimentalVersion,
  }) {
    final normalized = versions
        .map((version) => version.trim())
        .where((version) => version.isNotEmpty)
        .toSet();
    normalized.add(stableVersion);

    final experimental = experimentalVersion?.trim();
    if (experimental != null && experimental.isNotEmpty) {
      normalized.add(experimental);
    }

    final historical = normalized
        .where(
          (version) => version != stableVersion && version != experimental,
        )
        .toList()
      ..sort((left, right) => compareVersions(right, left));

    return [
      stableVersion,
      if (experimental != null &&
          experimental.isNotEmpty &&
          experimental != stableVersion)
        experimental,
      ...historical,
    ];
  }

  static int compareVersions(String left, String right) {
    try {
      return _parseVersion(left).compareTo(_parseVersion(right));
    } on FormatException {
      return _fallbackVersionParts(left, right);
    }
  }

  static bool isPrerelease(String version) {
    try {
      return _parseVersion(version).isPreRelease;
    } on FormatException {
      final normalized = _normalizeVersion(version);
      return RegExp(r'^\d+(?:\.\d+){0,2}-[^+]+').hasMatch(normalized);
    }
  }

  /// 版本选择器默认隐藏预发布版本，仅在用户明确开启设置后显示。
  static bool isVisibleInPicker(
    String version, {
    required bool showPrereleases,
  }) {
    try {
      if (_parseVersion(version)
              .compareTo(_parseVersion(minimumVisibleVersion)) <
          0) {
        return false;
      }
    } on FormatException {
      return false;
    }
    return showPrereleases || !isPrerelease(version);
  }

  static Version _parseVersion(String value) {
    return Version.parse(_normalizeVersion(value));
  }

  static String _normalizeVersion(String value) {
    return value.trim().replaceFirst(RegExp(r'^[vV](?=\d)'), '');
  }

  static int _fallbackVersionParts(String left, String right) {
    final leftParts = RegExp(r'\d+')
        .allMatches(left)
        .map((match) => int.tryParse(match.group(0) ?? '0') ?? 0)
        .toList();
    final rightParts = RegExp(r'\d+')
        .allMatches(right)
        .map((match) => int.tryParse(match.group(0) ?? '0') ?? 0)
        .toList();
    final length = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var index = 0; index < length; index++) {
      final leftValue = index < leftParts.length ? leftParts[index] : 0;
      final rightValue = index < rightParts.length ? rightParts[index] : 0;
      final result = leftValue.compareTo(rightValue);
      if (result != 0) return result;
    }
    return left.trim().compareTo(right.trim());
  }
}

/// npm `engines.node` 范围。每个 `||` 分支内部为 AND 关系。
class NodeVersionRequirement {
  final List<_ComparatorSet> _alternatives;

  const NodeVersionRequirement._(this._alternatives);

  factory NodeVersionRequirement.parse(String? requirement) {
    final normalized = requirement?.trim() ?? '';
    if (normalized.isEmpty || normalized == '*') {
      return const NodeVersionRequirement._([_ComparatorSet([])]);
    }

    final alternatives = normalized
        .split('||')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .map(_ComparatorSet.parse)
        .toList(growable: false);
    if (alternatives.isEmpty) {
      throw FormatException(
          'Invalid Node.js version requirement: $requirement');
    }
    return NodeVersionRequirement._(alternatives);
  }

  bool allows(String version) {
    Version parsed;
    try {
      parsed = Version.parse(_normalizeVersion(version));
    } on FormatException {
      return false;
    }
    return _alternatives.any((alternative) => alternative.allows(parsed));
  }

  String? selectHighestAllowed(Iterable<String> validatedVersions) {
    final candidates = <({String text, Version version})>[];
    for (final candidate in validatedVersions) {
      final normalized = _normalizeVersion(candidate);
      try {
        final version = Version.parse(normalized);
        if (_alternatives.any((alternative) => alternative.allows(version))) {
          candidates.add((text: normalized, version: version));
        }
      } on FormatException {
        continue;
      }
    }
    candidates.sort((left, right) => right.version.compareTo(left.version));
    return candidates.isEmpty ? null : candidates.first.text;
  }

  static String _normalizeVersion(String value) {
    return value.trim().replaceFirst(RegExp(r'^[vV](?=\d)'), '');
  }
}

class _ComparatorSet {
  final List<_VersionComparator> comparators;

  const _ComparatorSet(this.comparators);

  factory _ComparatorSet.parse(String expression) {
    final hyphen = RegExp(
      r'^\s*([^\s]+)\s+-\s+([^\s]+)\s*$',
    ).firstMatch(expression);
    if (hyphen != null) {
      final lower = _PartialVersion.parse(hyphen.group(1)!);
      final upper = _PartialVersion.parse(hyphen.group(2)!);
      return _ComparatorSet([
        _VersionComparator(_ComparisonOperator.greaterOrEqual, lower.lower),
        if (upper.isComplete)
          _VersionComparator(_ComparisonOperator.lessOrEqual, upper.lower)
        else
          _VersionComparator(
            _ComparisonOperator.less,
            upper.upperExclusive!,
          ),
      ]);
    }

    final rawTokens = expression
        .replaceAll(',', ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
    final tokens = <String>[];
    for (var index = 0; index < rawTokens.length; index++) {
      final token = rawTokens[index];
      if (_standaloneOperators.contains(token) &&
          index + 1 < rawTokens.length) {
        tokens.add('$token${rawTokens[++index]}');
      } else {
        tokens.add(token);
      }
    }

    final comparators = <_VersionComparator>[];
    for (final token in tokens) {
      comparators.addAll(_comparatorsForToken(token));
    }
    return _ComparatorSet(comparators);
  }

  bool allows(Version version) {
    if (!comparators.every((comparator) => comparator.allows(version))) {
      return false;
    }
    if (!version.isPreRelease) {
      return true;
    }

    // npm 默认排除预发布版本，除非同一版本分支明确提到预发布下界。
    return comparators.any(
      (comparator) =>
          comparator.version.isPreRelease &&
          comparator.version.major == version.major &&
          comparator.version.minor == version.minor &&
          comparator.version.patch == version.patch,
    );
  }

  static const _standaloneOperators = {'>', '>=', '<', '<=', '=', '^', '~'};

  static List<_VersionComparator> _comparatorsForToken(String token) {
    if (token == '*' || token.toLowerCase() == 'x') {
      return const [];
    }

    final match = RegExp(r'^(>=|<=|>|<|=|\^|~)?(.+)$').firstMatch(token);
    if (match == null) {
      throw FormatException('Invalid version comparator: $token');
    }
    final operator = match.group(1) ?? '';
    final partial = _PartialVersion.parse(match.group(2)!);
    if (partial.precision == 0) {
      return const [];
    }

    switch (operator) {
      case '>=':
        return [
          _VersionComparator(_ComparisonOperator.greaterOrEqual, partial.lower),
        ];
      case '>':
        if (partial.isComplete) {
          return [
            _VersionComparator(_ComparisonOperator.greater, partial.lower),
          ];
        }
        return [
          _VersionComparator(
            _ComparisonOperator.greaterOrEqual,
            partial.upperExclusive!,
          ),
        ];
      case '<':
        return [
          _VersionComparator(_ComparisonOperator.less, partial.lower),
        ];
      case '<=':
        if (partial.isComplete) {
          return [
            _VersionComparator(_ComparisonOperator.lessOrEqual, partial.lower),
          ];
        }
        return [
          _VersionComparator(
            _ComparisonOperator.less,
            partial.upperExclusive!,
          ),
        ];
      case '^':
        return [
          _VersionComparator(_ComparisonOperator.greaterOrEqual, partial.lower),
          _VersionComparator(
            _ComparisonOperator.less,
            partial.caretUpperExclusive,
          ),
        ];
      case '~':
        return [
          _VersionComparator(_ComparisonOperator.greaterOrEqual, partial.lower),
          _VersionComparator(
            _ComparisonOperator.less,
            partial.tildeUpperExclusive,
          ),
        ];
      case '=':
      case '':
        if (!partial.isComplete) {
          return [
            _VersionComparator(
              _ComparisonOperator.greaterOrEqual,
              partial.lower,
            ),
            _VersionComparator(
              _ComparisonOperator.less,
              partial.upperExclusive!,
            ),
          ];
        }
        return [
          _VersionComparator(_ComparisonOperator.equal, partial.lower),
        ];
      default:
        throw FormatException('Unsupported version comparator: $token');
    }
  }
}

enum _ComparisonOperator {
  less,
  lessOrEqual,
  equal,
  greaterOrEqual,
  greater,
}

class _VersionComparator {
  final _ComparisonOperator operator;
  final Version version;

  const _VersionComparator(this.operator, this.version);

  bool allows(Version candidate) {
    final comparison = candidate.compareTo(version);
    return switch (operator) {
      _ComparisonOperator.less => comparison < 0,
      _ComparisonOperator.lessOrEqual => comparison <= 0,
      _ComparisonOperator.equal => comparison == 0,
      _ComparisonOperator.greaterOrEqual => comparison >= 0,
      _ComparisonOperator.greater => comparison > 0,
    };
  }
}

class _PartialVersion {
  final int? major;
  final int? minor;
  final int? patch;
  final int precision;
  final String? prerelease;
  final String? build;

  const _PartialVersion({
    required this.major,
    required this.minor,
    required this.patch,
    required this.precision,
    this.prerelease,
    this.build,
  });

  factory _PartialVersion.parse(String input) {
    var normalized = input.trim().replaceFirst(RegExp(r'^[vV](?=\d)'), '');
    if (normalized.isEmpty || normalized == '*') {
      return const _PartialVersion(
        major: null,
        minor: null,
        patch: null,
        precision: 0,
      );
    }

    String? build;
    final buildIndex = normalized.indexOf('+');
    if (buildIndex >= 0) {
      build = normalized.substring(buildIndex + 1);
      normalized = normalized.substring(0, buildIndex);
    }
    String? prerelease;
    final prereleaseIndex = normalized.indexOf('-');
    if (prereleaseIndex >= 0) {
      prerelease = normalized.substring(prereleaseIndex + 1);
      normalized = normalized.substring(0, prereleaseIndex);
    }

    final parts = normalized.split('.');
    if (parts.length > 3) {
      throw FormatException('Invalid semantic version: $input');
    }
    final values = <int?>[];
    var precision = 0;
    var wildcardSeen = false;
    for (final part in parts) {
      final isWildcard = part == '*' || part.toLowerCase() == 'x';
      if (isWildcard) {
        wildcardSeen = true;
        values.add(null);
        continue;
      }
      if (wildcardSeen || !RegExp(r'^\d+$').hasMatch(part)) {
        throw FormatException('Invalid semantic version: $input');
      }
      values.add(int.parse(part));
      precision++;
    }
    while (values.length < 3) {
      values.add(null);
    }
    if (prerelease != null && precision < 3) {
      throw FormatException('Prerelease versions must be complete: $input');
    }

    return _PartialVersion(
      major: values[0],
      minor: values[1],
      patch: values[2],
      precision: precision,
      prerelease: prerelease,
      build: build,
    );
  }

  bool get isComplete => precision == 3;

  Version get lower => Version(
        major ?? 0,
        minor ?? 0,
        patch ?? 0,
        pre: prerelease,
        build: build,
      );

  Version? get upperExclusive {
    if (precision == 0) return null;
    if (precision == 1) return Version((major ?? 0) + 1, 0, 0);
    if (precision == 2) return Version(major ?? 0, (minor ?? 0) + 1, 0);
    return null;
  }

  Version get caretUpperExclusive {
    final resolvedMajor = major ?? 0;
    final resolvedMinor = minor ?? 0;
    final resolvedPatch = patch ?? 0;
    if (resolvedMajor > 0) {
      return Version(resolvedMajor + 1, 0, 0);
    }
    if (precision == 1) {
      return Version(1, 0, 0);
    }
    if (resolvedMinor > 0 || precision == 2) {
      return Version(0, resolvedMinor + 1, 0);
    }
    return Version(0, 0, resolvedPatch + 1);
  }

  Version get tildeUpperExclusive {
    final resolvedMajor = major ?? 0;
    if (precision <= 1) {
      return Version(resolvedMajor + 1, 0, 0);
    }
    return Version(resolvedMajor, (minor ?? 0) + 1, 0);
  }
}
