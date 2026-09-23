// ============================================================================
// خدمة الرسائل (WhatsApp / SMS)
// ============================================================================
// مبدأ صارم: لا يُعتبر الإشعار "مُرسلًا" (sent) إلا بعد تأكيد فعلي. بما أن هذا
// الإصدار لا يملك اعتماد (API key) لمزوّد WhatsApp Business API أو بوابة SMS
// فعلية، فالآلية المتاحة الآن هي فتح تطبيق WhatsApp/الرسائل النصية على جهاز
// المستخدم مع نص الرسالة جاهزًا لإرساله يدويًا (url_launcher / wa.me link).
// حالة السجل في هذه الحالة تبقى 'pending' حتى يؤكد المستخدم الإرسال يدويًا،
// أو تتحول 'failed' إذا تعذّر فتح التطبيق. الكود مصمم بحيث يمكن لاحقًا حقن
// عميل API حقيقي (WhatsApp Business Cloud API أو مزود SMS) دون تغيير بنية
// الجداول أو واجهة الاستدعاء.
// ============================================================================

import 'package:url_launcher/url_launcher.dart';
import '../core/db.dart';

abstract class MessageProvider {
  /// يحاول الإرسال فعليًا ويعيد true فقط إذا تأكد الإرسال من المزوّد.
  /// التطبيق الافتراضي (بدون API) يعيد false دائمًا لأنه لا توجد طريقة
  /// لتأكيد الإرسال الفعلي بمجرد فتح تطبيق خارجي.
  Future<bool> send({required String phone, required String message});
}

/// المزوّد الافتراضي: يفتح واتساب/الرسائل مع نص جاهز، بدون أي ادّعاء بالإرسال.
class ManualOpenProvider implements MessageProvider {
  final bool whatsapp;
  ManualOpenProvider({required this.whatsapp});

  @override
  Future<bool> send({required String phone, required String message}) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = whatsapp
        ? Uri.parse('https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}')
        : Uri.parse('sms:$cleanPhone?body=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    // فتح التطبيق ليس تأكيدًا للإرسال — يبقى pending في كل الأحوال، بصرف
    // النظر عن نجاح فتح التطبيق الخارجي. راجع تعليق الفئة أعلاه.
    return false;
  }
}

/// نقطة توسعة مستقبلية: عند توفر اعتماد API حقيقي (مثال: WhatsApp Business
/// Cloud API)، يُنفَّذ هذا الصنف ويُستبدل به [ManualOpenProvider] في
/// [MessageService.provider] دون أي تغيير آخر في بقية النظام.
class ApiMessageProvider implements MessageProvider {
  final String apiBaseUrl;
  final String apiToken;
  ApiMessageProvider({required this.apiBaseUrl, required this.apiToken});

  @override
  Future<bool> send({required String phone, required String message}) async {
    throw UnimplementedError(
        'لم يتم ربط مزوّد API فعلي بعد. أضف بيانات الاعتماد في الإعدادات ونفّذ الاستدعاء هنا.');
  }
}

class MessageService {
  /// غيّر هذا لاستخدام مزوّد API حقيقي متى توفّر.
  static MessageProvider provider = ManualOpenProvider(whatsapp: true);

  static String _render(String template, Map<String, String> values) {
    var out = template;
    values.forEach((k, v) => out = out.replaceAll('{{$k}}', v));
    return out;
  }

  static Future<String> _setting(String key, String fallback) async {
    final r = await AppDb.instance.q('SELECT value FROM settings WHERE key=?', [key]);
    return r.isEmpty ? fallback : r.first['value'] as String;
  }

  /// يُنشئ رسالة إشعار الحمولة من القالب القابل للتعديل في الإعدادات،
  /// ويسجّلها في جدول notifications بحالة 'pending'، ثم يحاول فتح واتساب.
  static Future<void> queueLoadNotification(int loadId) async {
    final rows = await AppDb.instance.q('''
      SELECT l.*, f.name AS factory_name, d.name AS driver_name, d.phone AS driver_phone,
             t.plate AS truck_plate
      FROM loads l
      JOIN parties f ON f.id = l.factory_id
      JOIN drivers d ON d.id = l.driver_id
      JOIN trucks t ON t.id = l.truck_id
      WHERE l.id = ?
    ''', [loadId]);
    if (rows.isEmpty) return;
    final r = rows.first;
    final template = await _setting('whatsapp_template_load', '');
    final values = {
      'factory': r['factory_name'].toString(),
      'driver': r['driver_name'].toString(),
      'truck': r['truck_plate'].toString(),
      'bulk': (r['bulk_total'] ?? 0).toString(),
      'bags': (r['bags'] ?? 0).toString(),
      'tons': (r['weight_tons'] ?? 0).toString(),
      'transport': (r['transport_total'] ?? 0).toString(),
      'operation_no': r['operation_no'].toString(),
      'date': r['datetime'].toString(),
    };
    final message = _render(template, values);
    final now = DateTime.now().toIso8601String();
    final notifId = await AppDb.instance.ins('notifications', {
      'load_id': loadId,
      'channel': 'whatsapp',
      'recipient_phone': r['driver_phone'],
      'message': message,
      'status': 'pending',
      'created': now,
      'updated': now,
    });
    await _attemptSend(notifId, r['driver_phone']?.toString() ?? '', message);
  }

  static Future<void> _attemptSend(int notifId, String phone, String message) async {
    try {
      if (phone.isEmpty) {
        await _updateStatus(notifId, 'failed', error: 'لا يوجد رقم هاتف مسجّل للسائق');
        return;
      }
      final confirmed = await provider.send(phone: phone, message: message);
      await _updateStatus(notifId, confirmed ? 'sent' : 'pending');
    } catch (e) {
      await _updateStatus(notifId, 'failed', error: e.toString());
    }
  }

  static Future<void> _updateStatus(int notifId, String status, {String? error}) async {
    await AppDb.instance.upd('notifications', {
      'status': status,
      'error': error,
      'updated': DateTime.now().toIso8601String(),
    }, 'id=?', [notifId]);
  }

  /// يستدعيها المستخدم يدويًا من واجهة الإشعارات بعد أن يتأكد أنه أرسل
  /// الرسالة فعليًا من واتساب/الرسائل — هذا هو التأكيد الوحيد الموثوق حاليًا.
  static Future<void> markConfirmedSent(int notifId) async {
    await _updateStatus(notifId, 'sent');
  }

  static Future<List<Map<String, Object?>>> pendingNotifications() =>
      AppDb.instance.q("SELECT * FROM notifications WHERE status='pending' ORDER BY id DESC");
}
