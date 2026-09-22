// ============================================================================
// سجل التدقيق — يسجل كل عملية حساسة (إضافة/ترحيل/إلغاء/عكس) مع من نفّذها
// ومتى، وحالة السجل قبل وبعد التغيير عند الإمكان، لأغراض المراجعة والتتبع.
// ============================================================================

import 'dart:convert';
import 'db.dart';
import 'permissions.dart';

class Audit {
  static Future<void> log({
    required String action,
    required String entity,
    int? entityId,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  }) async {
    final user = Session.instance.user;
    await AppDb.instance.ins('audit_log', {
      'user_id': user?.id,
      'username': user?.username ?? 'system',
      'action': action,
      'entity': entity,
      'entity_id': entityId,
      'before_json': before == null ? null : jsonEncode(before),
      'after_json': after == null ? null : jsonEncode(after),
      'created': DateTime.now().toIso8601String(),
    });
  }
}
