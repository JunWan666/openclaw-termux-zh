import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/constants.dart';

void main() {
  test('x86_64 RootFS 下载包含同架构镜像回退', () {
    final candidates = AppConstants.getRootfsDownloadCandidates('x86_64');

    expect(candidates, hasLength(4));
    expect(candidates.first, AppConstants.rootfsAmd64);
    expect(
      candidates.every(
        (url) => url.endsWith('ubuntu-base-24.04.3-base-amd64.tar.gz'),
      ),
      isTrue,
    );
    expect(
        candidates, contains(predicate<String>((url) => url.contains('tuna'))));
    expect(
        candidates, contains(predicate<String>((url) => url.contains('ustc'))));
  });

  test('armv7 RootFS 镜像回退保持 armhf 架构', () {
    final candidates = AppConstants.getRootfsDownloadCandidates('arm');

    expect(
      candidates.every(
        (url) => url.endsWith('ubuntu-base-24.04.3-base-armhf.tar.gz'),
      ),
      isTrue,
    );
  });
}
