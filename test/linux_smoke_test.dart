import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scenario in [
    (
      name: 'rejects an early normal exit even after a readiness message',
      program: "echo MIAOSIC_SMOKE_READY\nexit 0\n",
      succeeds: false,
    ),
    (
      name: 'rejects a process that never renders its first frame',
      program: 'exec sleep 30\n',
      succeeds: false,
    ),
    (
      name: 'isolates runtime state and accepts a ready running process',
      program: r'''
test "$MIAOSIC_SMOKE_TEST" = 1
test "$XDG_RUNTIME_DIR" != "$MIAOSIC_TEST_PARENT_RUNTIME"
test "$(stat -c %a "$XDG_RUNTIME_DIR")" = 700
echo MIAOSIC_SMOKE_READY
exec sleep 30
''',
      succeeds: true,
    ),
  ]) {
    test('Linux smoke test ${scenario.name}', () async {
      final dir = await Directory.systemTemp.createTemp('miaosic_smoke_test_');
      addTearDown(() => dir.delete(recursive: true));
      final parentRuntime = await Directory(
        '${dir.path}/parent-runtime',
      ).create();
      final bundle = await Directory('${dir.path}/bundle').create();
      final binary = File('${bundle.path}/miaosic');
      await binary.writeAsString(
        '#!/usr/bin/env bash\nset -euo pipefail\n${scenario.program}',
      );
      final chmod = await Process.run('chmod', ['700', binary.path]);
      expect(chmod.exitCode, 0);

      final result = await Process.run(
        'bash',
        ['scripts/smoke_linux_bundle.sh', bundle.path],
        environment: {
          'XDG_RUNTIME_DIR': parentRuntime.path,
          'MIAOSIC_TEST_PARENT_RUNTIME': parentRuntime.path,
        },
      );

      expect(
        result.exitCode,
        scenario.succeeds ? 0 : isNot(0),
        reason: '${result.stdout}\n${result.stderr}',
      );
      expect(await parentRuntime.list().toList(), isEmpty);
    }, skip: !Platform.isLinux);
  }
}
