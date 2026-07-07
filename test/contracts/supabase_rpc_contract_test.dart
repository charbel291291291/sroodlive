import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current;
  final migrations = Directory('${root.path}/supabase/migrations');

  String migrationSql() => migrations
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.sql'))
      .map((file) => file.readAsStringSync())
      .join('\n')
      .toLowerCase();

  test('required gamification read RPCs are migrated', () {
    final sql = migrationSql();
    const rpcNames = {'get_store_items', 'get_my_tasks', 'get_my_backpack'};

    for (final rpc in rpcNames) {
      expect(
        RegExp(
          'create\\s+(?:or\\s+replace\\s+)?function\\s+public\\.$rpc\\s*\\(',
        ).hasMatch(sql),
        isTrue,
        reason: '$rpc must be defined in a source-controlled migration',
      );
    }
  });

  test('server-authoritative game mutation RPCs are migrated', () {
    final sql = migrationSql();
    const rpcNames = {
      'place_magic_srood_global_bet',
      'place_hungry_cat_global_bet',
      'treasure_open_box',
    };

    for (final rpc in rpcNames) {
      expect(
        RegExp(
          'create\\s+(?:or\\s+replace\\s+)?function\\s+public\\.$rpc\\s*\\(',
        ).hasMatch(sql),
        isTrue,
        reason: '$rpc must be defined in a source-controlled migration',
      );
    }
  });

  test('Flutter services call the expected read contracts', () {
    final gamification = File(
      '${root.path}/lib/features/gamification/services/gamification_service.dart',
    ).readAsStringSync();

    for (final rpc in const {
      'get_store_items',
      'get_my_tasks',
      'get_my_backpack',
    }) {
      expect(gamification, contains("'$rpc'"));
    }
  });
}
