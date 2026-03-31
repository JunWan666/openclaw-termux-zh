class DashboardUrlResolver {
  static const _noiseSuffixes = ['gatewayws', 'copied', 'copy'];
  static final _urlRegex =
      RegExp(r'''https?://[^\s<>"'\]\)]+''', caseSensitive: false);
  static final _tokenRegex = RegExp(
    r'[#?&]token=([A-Za-z0-9._~-]+)',
    caseSensitive: false,
  );
  static final _jsonTokenRegex = RegExp(
    r'''["']token["']\s*:\s*["']([A-Za-z0-9._~-]+)["']''',
    caseSensitive: false,
  );

  static String? extractToken(String text) {
    final tokenMatch = _tokenRegex.firstMatch(text);
    if (tokenMatch != null) {
      return _sanitizeToken(tokenMatch.group(1));
    }

    final jsonMatch = _jsonTokenRegex.firstMatch(text);
    return _sanitizeToken(jsonMatch?.group(1));
  }

  static bool hasToken(String? url) {
    if (url == null || url.isEmpty) {
      return false;
    }
    return extractToken(url) != null;
  }

  static String buildDashboardUrl(Uri baseUri, String token) {
    return dashboardBaseUri(baseUri)
        .replace(fragment: 'token=$token')
        .toString();
  }

  static String? normalizeDashboardUrl(String? value, {Uri? baseUri}) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final trimmed = _trimCandidate(value.trim());
    final resolved = extractDashboardUrlFromText(trimmed, baseUri: baseUri);
    if (resolved != null) {
      return resolved;
    }

    final uri = Uri.tryParse(trimmed);
    final token = extractToken(trimmed);
    if (uri != null && token != null) {
      return buildDashboardUrl(uri, token);
    }

    return trimmed;
  }

  static String? extractDashboardUrlFromText(String text, {Uri? baseUri}) {
    for (final match in _urlRegex.allMatches(text)) {
      final candidate = _trimCandidate(match.group(0)!);
      final uri = Uri.tryParse(candidate);
      final token = extractToken(candidate);
      if (uri == null || token == null) {
        continue;
      }
      return buildDashboardUrl(uri, token);
    }

    final token = extractToken(text);
    if (token == null || baseUri == null) {
      return null;
    }

    return buildDashboardUrl(baseUri, token);
  }

  static Uri dashboardBaseUri(Uri uri) {
    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : 0,
      path: '/',
    );
  }

  static String _trimCandidate(String value) {
    return value.replaceFirst(RegExp(r'[\s),.;]+$'), '');
  }

  static String? _sanitizeToken(String? token) {
    if (token == null) {
      return null;
    }

    var sanitized = token.trim();
    var changed = true;
    while (changed) {
      changed = false;
      final lower = sanitized.toLowerCase();
      for (final suffix in _noiseSuffixes) {
        if (sanitized.length <= suffix.length) {
          continue;
        }
        if (lower.endsWith(suffix)) {
          sanitized = sanitized.substring(0, sanitized.length - suffix.length);
          changed = true;
          break;
        }
      }
    }

    return sanitized.isEmpty ? null : sanitized;
  }
}
