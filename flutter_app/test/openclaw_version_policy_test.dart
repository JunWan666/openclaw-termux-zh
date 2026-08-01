import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openclaw/l10n/app_localizations.dart';
import 'package:openclaw/models/openclaw_install_options.dart';
import 'package:openclaw/models/openclaw_version_policy.dart';
import 'package:openclaw/services/openclaw_version_service.dart';

void main() {
  test('Node runtime diagnostics preserve execution failures', () {
    const failed = InstalledNodeRuntime(
      path: '/usr/local/bin/node',
      failure: 'ABI_MISMATCH exit code 126: Exec format error',
    );
    expect(failed.diagnosticDescription, contains('ABI_MISMATCH'));
    expect(failed.diagnosticDescription, contains('exit code 126'));
    expect(
      const InstalledNodeRuntime().diagnosticDescription,
      'node binary not found',
    );
  });

  test('3.13、3.23 和当前最新 7.1 显示推荐标签', () {
    final l10n = AppLocalizations(const Locale('zh'));

    expect(
      formatOpenClawReleaseLabel(l10n, '2026.3.13'),
      '2026.3.13 (推荐)',
    );
    expect(
      formatOpenClawReleaseLabel(l10n, '2026.3.23'),
      '2026.3.23 (推荐)',
    );
    expect(
      formatOpenClawReleaseLabel(
        l10n,
        '2026.7.1',
        channel: OpenClawReleaseChannel.experimental,
      ),
      '2026.7.1 (最新 · 推荐)',
    );
  });

  group('OpenClawReleasePolicy', () {
    test('offline catalog always exposes Stable as the default', () {
      expect(OpenClawReleasePolicy.stableVersion, '2026.3.23');
      expect(
        OpenClawReleasePolicy.orderVersions(const []),
        const ['2026.3.23'],
      );
    });

    test('orders Stable, Experimental, then historical releases', () {
      expect(
        OpenClawReleasePolicy.orderVersions(
          const [
            '2026.3.13',
            '2026.7.1-1',
            '2026.7.1-2',
            '2026.3.23',
            '2026.7.1-2',
          ],
          experimentalVersion: '2026.7.1-2',
        ),
        const [
          '2026.3.23',
          '2026.7.1-2',
          '2026.7.1-1',
          '2026.3.13',
        ],
      );
    });

    test('classifies only pinned versions as Stable or Experimental', () {
      expect(
        OpenClawReleasePolicy.channelFor(
          '2026.3.23',
          experimentalVersion: '2026.7.1-2',
        ),
        OpenClawReleaseChannel.stable,
      );
      expect(
        OpenClawReleasePolicy.channelFor(
          '2026.7.1-2',
          experimentalVersion: '2026.7.1-2',
        ),
        OpenClawReleaseChannel.experimental,
      );
      expect(
        OpenClawReleasePolicy.channelFor(
          '2026.3.13',
          experimentalVersion: '2026.7.1-2',
        ),
        OpenClawReleaseChannel.historical,
      );
    });

    test('compares prerelease and numeric revision identifiers', () {
      expect(
        OpenClawReleasePolicy.compareVersions(
          '2026.7.1-beta.2',
          '2026.7.1-rc.1',
        ),
        lessThan(0),
      );
      expect(
        OpenClawReleasePolicy.compareVersions('2026.7.1-2', '2026.7.1-1'),
        greaterThan(0),
      );
      expect(
        OpenClawReleasePolicy.compareVersions('2026.7.1-2', '2026.7.1'),
        lessThan(0),
      );
    });

    test('detects beta rc and numeric prerelease versions', () {
      expect(OpenClawReleasePolicy.isPrerelease('2026.7.1-beta.2'), isTrue);
      expect(OpenClawReleasePolicy.isPrerelease('2026.7.1-rc.1'), isTrue);
      expect(OpenClawReleasePolicy.isPrerelease('2026.7.1-2'), isTrue);
      expect(OpenClawReleasePolicy.isPrerelease('2026.7.1'), isFalse);
      expect(OpenClawReleasePolicy.isPrerelease('v2026.3.23'), isFalse);
    });

    test('hides prereleases from version pickers by default', () {
      expect(
        OpenClawReleasePolicy.isVisibleInPicker(
          '2026.7.1-beta.2',
          showPrereleases: false,
        ),
        isFalse,
      );
      expect(
        OpenClawReleasePolicy.isVisibleInPicker(
          '2026.7.1-2',
          showPrereleases: false,
        ),
        isFalse,
      );
      expect(
        OpenClawReleasePolicy.isVisibleInPicker(
          '2026.7.1',
          showPrereleases: false,
        ),
        isTrue,
      );
      expect(
        OpenClawReleasePolicy.isVisibleInPicker(
          '2026.7.1-beta.2',
          showPrereleases: true,
        ),
        isTrue,
      );
    });

    test('hides every release older than 2026.3.13', () {
      expect(OpenClawReleasePolicy.minimumVisibleVersion, '2026.3.13');
      for (final version in const [
        '2026.3.12',
        '2026.2.28',
        '2025.12.31',
        '2026.3.13-beta.1',
      ]) {
        expect(
          OpenClawReleasePolicy.isVisibleInPicker(
            version,
            showPrereleases: true,
          ),
          isFalse,
          reason: version,
        );
      }
      expect(
        OpenClawReleasePolicy.isVisibleInPicker(
          '2026.3.13',
          showPrereleases: false,
        ),
        isTrue,
      );
      expect(
        OpenClawReleasePolicy.isVisibleInPicker(
          '2026.4.1',
          showPrereleases: false,
        ),
        isTrue,
      );
    });
  });

  group('NodeVersionRequirement', () {
    const latestRequirement = '>=22.22.3 <23 || >=24.15.0 <25 || >=25.9.0';

    test('supports disjunctions and lower/upper bounds', () {
      final requirement = NodeVersionRequirement.parse(latestRequirement);

      expect(requirement.allows('22.22.2'), isFalse);
      expect(requirement.allows('22.22.3'), isTrue);
      expect(requirement.allows('23.0.0'), isFalse);
      expect(requirement.allows('24.14.1'), isFalse);
      expect(requirement.allows('24.15.0'), isTrue);
      expect(requirement.allows('24.18.1'), isTrue);
      expect(requirement.allows('25.8.9'), isFalse);
      expect(requirement.allows('25.9.0'), isTrue);
    });

    test('supports caret tilde wildcard and hyphen ranges', () {
      expect(
          NodeVersionRequirement.parse('^24.15.0').allows('24.99.0'), isTrue);
      expect(
          NodeVersionRequirement.parse('^24.15.0').allows('25.0.0'), isFalse);
      expect(
          NodeVersionRequirement.parse('~24.15.0').allows('24.15.9'), isTrue);
      expect(
          NodeVersionRequirement.parse('~24.15.0').allows('24.16.0'), isFalse);
      expect(NodeVersionRequirement.parse('24.x').allows('24.18.1'), isTrue);
      expect(NodeVersionRequirement.parse('24.x').allows('25.0.0'), isFalse);
      expect(
        NodeVersionRequirement.parse('22.22.0 - 22.22.3').allows('22.22.3'),
        isTrue,
      );
    });

    test('does not accidentally accept prereleases', () {
      expect(
        NodeVersionRequirement.parse('>=24.15.0 <25').allows('24.15.0-rc.1'),
        isFalse,
      );
      expect(
        NodeVersionRequirement.parse('>=24.15.0-rc.1 <24.15.0')
            .allows('24.15.0-rc.2'),
        isTrue,
      );
    });

    test('selects only a validated runtime satisfying the whole range', () {
      final requirement = NodeVersionRequirement.parse(latestRequirement);

      expect(
        requirement.selectHighestAllowed(const ['22.22.2', '24.18.1']),
        '24.18.1',
      );
      expect(
        requirement.selectHighestAllowed(const ['22.22.2', '24.14.1']),
        isNull,
      );
    });
  });

  group('OpenClawVersionService catalog', () {
    test('online catalog marks the newest formal release as latest', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/latest')) {
          return http.Response(
            jsonEncode({
              'version': '2026.7.1-2',
              'engines': {
                'node': '>=22.22.3 <23 || >=24.15.0 <25 || >=25.9.0',
              },
              'dist': {
                'unpackedSize': 123456,
                'tarball': 'https://example.test/openclaw-2026.7.1-2.tgz',
              },
            }),
            200,
          );
        }
        if (request.url.path == '/openclaw') {
          return http.Response(
            jsonEncode({
              'versions': {
                '2026.3.13': {
                  'version': '2026.3.13',
                  'engines': {'node': '>=22.16.0'},
                },
                '2026.3.23': {
                  'version': '2026.3.23',
                  'engines': {'node': '>=22.16.0'},
                },
                '2026.7.1-2': {
                  'version': '2026.7.1-2',
                  'engines': {
                    'node': '>=22.22.3 <23 || >=24.15.0 <25 || >=25.9.0',
                  },
                },
                '2026.7.1': {
                  'version': '2026.7.1',
                  'engines': {
                    'node': '>=22.22.3 <23 || >=24.15.0 <25 || >=25.9.0',
                  },
                },
              },
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });
      final service = OpenClawVersionService(httpClient: client);

      final catalog = await service.loadReleaseCatalog(arch: 'x86_64');

      expect(catalog.isOffline, isFalse);
      expect(catalog.warning, isNull);
      expect(
        catalog.releases.map((release) => release.version).take(3),
        const ['2026.3.23', '2026.7.1', '2026.7.1-2'],
      );
      expect(catalog.stableRelease.channel, OpenClawReleaseChannel.stable);
      expect(
        catalog.experimentalRelease?.channel,
        OpenClawReleaseChannel.experimental,
      );
      expect(catalog.experimentalRelease?.version, '2026.7.1');
      expect(
        catalog.experimentalRelease?.nodeValidationStatus,
        OpenClawNodeValidationStatus.verified,
      );
    });

    test('offline catalog keeps Stable and an installed pinned release',
        () async {
      final service = OpenClawVersionService(
        httpClient: MockClient((_) async => http.Response('offline', 503)),
      );

      final catalog = await service.loadReleaseCatalog(
        arch: 'x86_64',
        pinnedVersions: const ['2026.7.1-2'],
      );

      expect(catalog.isOffline, isTrue);
      expect(catalog.warning, isNotNull);
      expect(catalog.experimentalRelease, isNull);
      expect(
        catalog.releases.map((release) => release.version),
        const ['2026.3.23', '2026.7.1-2'],
      );
      expect(
        catalog.stableRelease.nodeValidationStatus,
        OpenClawNodeValidationStatus.verified,
      );
    });

    test('armv7 catalog blocks latest when no validated Node runtime matches',
        () {
      final catalog = OpenClawVersionService.buildReleaseCatalog(
        availableReleases: const [],
        latestRelease: const OpenClawReleaseInfo(
          version: '2026.7.1-2',
          nodeRequirement: '>=22.22.3 <23 || >=24.15.0 <25 || >=25.9.0',
        ),
        arch: 'armv7l',
      );

      expect(
        catalog.experimentalRelease?.nodeValidationStatus,
        OpenClawNodeValidationStatus.unsupported,
      );
      expect(
        OpenClawVersionService.nodeVersionSatisfiesRequirement(
          '23.0.0',
          '>=22.22.3 <23 || >=24.15.0 <25',
        ),
        isFalse,
      );
    });
  });
}
