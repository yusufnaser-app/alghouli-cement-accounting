// ============================================================================
// الصلاحيات والجلسة الحالية
// ============================================================================
// مبدأ أساسي: الصلاحية تُفرض هنا على مستوى المنطق (قبل أي كتابة لقاعدة
// البيانات)، وليس فقط بإخفاء الأزرار في الواجهة. أي محاولة لتنفيذ عملية بدون
// صلاحية كافية تُرمى كاستثناء [PermissionDeniedException] بدلًا من الصمت.
// ============================================================================

import 'db.dart';

enum PermAction { view, add, edit, post, cancel, reverse, print, export, send, settings }

class PermissionDeniedException implements Exception {
  final String message;
  PermissionDeniedException(this.message);
  @override
  String toString() => message;
}

class CurrentUser {
  final int id;
  final String username;
  final String fullName;
  final String role;
  const CurrentUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
  });
}

/// جلسة التطبيق الحالية (مستخدم واحد نشط في كل لحظة على الجهاز).
class Session {
  Session._();
  static final Session instance = Session._();
  CurrentUser? _user;
  CurrentUser? get user => _user;
  bool get isLoggedIn => _user != null;

  Future<CurrentUser> login(String username, String password) async {
    final rows = await AppDb.instance.q(
        'SELECT * FROM users WHERE username=? AND active=1', [username]);
    if (rows.isEmpty) throw Exception('اسم المستخدم غير موجود أو الحساب معطّل');
    final r = rows.first;
    final ok = AppDb.verifyPassword(
        password, r['password_salt'] as String, r['password_hash'] as String);
    if (!ok) throw Exception('كلمة المرور غير صحيحة');
    await AppDb.instance
        .upd('users', {'last_login': DateTime.now().toIso8601String()}, 'id=?', [r['id']]);
    _user = CurrentUser(
      id: r['id'] as int,
      username: r['username'] as String,
      fullName: (r['full_name'] as String?) ?? r['username'] as String,
      role: r['role'] as String,
    );
    return _user!;
  }

  void logout() => _user = null;
}

class Permissions {
  /// يتحقق من صلاحية الدور الحالي لتنفيذ [action] على [module].
  /// يرمي [PermissionDeniedException] عند الرفض. يجب استدعاؤه في بداية أي
  /// عملية حساسة في طبقة الخدمات (accounting/operations) وليس فقط في الواجهة.
  static Future<void> require(String module, PermAction action) async {
    final user = Session.instance.user;
    if (user == null) {
      throw PermissionDeniedException('يجب تسجيل الدخول أولًا');
    }
    final rows = await AppDb.instance.q(
        'SELECT * FROM role_permissions WHERE role=? AND module=?', [user.role, module]);
    if (rows.isEmpty) {
      throw PermissionDeniedException('لا توجد صلاحيات معرّفة لدور "${user.role}" في وحدة "$module"');
    }
    final r = rows.first;
    final col = 'can_${action.name}';
    final allowed = (r[col] as int? ?? 0) == 1;
    if (!allowed) {
      throw PermissionDeniedException(
          'صلاحياتك الحالية لا تسمح بتنفيذ "${_actionLabel(action)}" في "$module"');
    }
  }

  /// نسخة غير مُلزمة تُستخدم فقط للتحكم في إظهار/إخفاء عناصر الواجهة.
  /// لا تُستخدم أبدًا كبديل عن [require] قبل الكتابة الفعلية للبيانات.
  static Future<bool> can(String module, PermAction action) async {
    try {
      await require(module, action);
      return true;
    } on PermissionDeniedException {
      return false;
    }
  }

  static String _actionLabel(PermAction a) => switch (a) {
        PermAction.view => 'العرض',
        PermAction.add => 'الإضافة',
        PermAction.edit => 'التعديل',
        PermAction.post => 'الترحيل',
        PermAction.cancel => 'الإلغاء',
        PermAction.reverse => 'العكس المحاسبي',
        PermAction.print => 'الطباعة',
        PermAction.export => 'التصدير',
        PermAction.send => 'الإرسال',
        PermAction.settings => 'الإعدادات',
      };
}
