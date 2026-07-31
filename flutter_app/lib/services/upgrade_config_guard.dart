import 'dart:convert';

import '../models/upgrade_transaction.dart';

class UpgradeConfigGuard {
  const UpgradeConfigGuard._();

  static final _sensitiveKey = RegExp(
    r'(token|secret|password|api.?key|private.?key|credential)',
    caseSensitive: false,
  );

  static Map<String, dynamic> decodeObject(String? content) {
    if (content == null || content.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw const FormatException('openclaw.json 顶层必须是对象');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static Map<String, dynamic> mergePreservingUserValues(
    Map<String, dynamic> original,
    Map<String, dynamic> migrated,
  ) {
    final result = _deepCopyMap(migrated);
    for (final entry in original.entries) {
      final previous = entry.value;
      final current = result[entry.key];
      if (previous is Map && current is Map) {
        result[entry.key] = mergePreservingUserValues(
          Map<String, dynamic>.from(previous),
          Map<String, dynamic>.from(current),
        );
        continue;
      }

      // 用户已有的非空标量、数组及未知对象始终优先；空值允许新版补默认值。
      if (_hasUserValue(previous) || !result.containsKey(entry.key)) {
        result[entry.key] = _deepCopy(previous);
      }
    }
    return result;
  }

  static List<UpgradeConfigChange> describeChanges(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) {
    final changes = <UpgradeConfigChange>[];
    _diffMap(before, after, '', changes);
    return changes;
  }

  static bool doctorNeedsFix(String output) {
    final trimmed = output.trim();
    if (trimmed.isEmpty) return false;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return false;
      if (decoded['ok'] == false) return true;
      final findings = decoded['findings'];
      if (findings is! Iterable) return false;
      for (final finding in findings) {
        if (finding is! Map) continue;
        if (finding['fixable'] == true || finding['repairable'] == true) {
          return true;
        }
        if (finding['severity']?.toString().toLowerCase() == 'error') {
          return true;
        }
      }
    } on FormatException {
      // 非 JSON 输出由调用方作为命令异常处理，不能误判为可自动修复。
    }
    return false;
  }

  static bool _hasUserValue(Object? value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is Iterable) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  static void _diffMap(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
    String prefix,
    List<UpgradeConfigChange> output,
  ) {
    final keys = {...before.keys, ...after.keys}.toList()..sort();
    for (final key in keys) {
      final path = prefix.isEmpty ? key : '$prefix.$key';
      final hadBefore = before.containsKey(key);
      final hasAfter = after.containsKey(key);
      if (!hadBefore || !hasAfter) {
        output.add(UpgradeConfigChange(
          path: path,
          kind: hadBefore ? 'removed' : 'added',
          summary: _summary(path, hasAfter ? after[key] : before[key]),
        ));
        continue;
      }
      final oldValue = before[key];
      final newValue = after[key];
      if (oldValue is Map && newValue is Map) {
        _diffMap(
          Map<String, dynamic>.from(oldValue),
          Map<String, dynamic>.from(newValue),
          path,
          output,
        );
      } else if (!_deepEquals(oldValue, newValue)) {
        output.add(UpgradeConfigChange(
          path: path,
          kind: 'changed',
          summary: _summary(path, newValue),
        ));
      }
    }
  }

  static String _summary(String path, Object? value) {
    if (_sensitiveKey.hasMatch(path)) return '[已隐藏敏感值]';
    if (value is Map) return '对象（${value.length} 项）';
    if (value is Iterable) return '数组（${value.length} 项）';
    if (value == null) return 'null';
    if (value is String) return '字符串（${value.length} 字符）';
    return value.runtimeType.toString();
  }

  static bool _deepEquals(Object? left, Object? right) =>
      jsonEncode(left) == jsonEncode(right);

  static Map<String, dynamic> _deepCopyMap(Map<String, dynamic> value) =>
      Map<String, dynamic>.from(
        jsonDecode(jsonEncode(value)) as Map,
      );

  static Object? _deepCopy(Object? value) => jsonDecode(jsonEncode(value));
}
