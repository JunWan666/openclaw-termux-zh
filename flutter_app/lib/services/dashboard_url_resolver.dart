class DashboardUrlResolver {
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
      return tokenMatch.group(1);
    }

    final jsonMatch = _jsonTokenRegex.firstMatch(text);
    return jsonMatch?.group(1);
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
}
