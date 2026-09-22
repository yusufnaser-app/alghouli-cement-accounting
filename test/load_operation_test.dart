import 'package:flutter_test/flutter_test.dart';
import 'package:cement_accounting_complete/core/db.dart';
import 'package:cement_accounting_complete/core/permissions.dart';
import 'package:cement_accounting_complete/accounting/accounting_engine.dart';
import 'package:cement_accounting_complete/operations/load_operation_service.dart';
import 'test_helpers.dart';

Future<Map<String, int>> _seedBasics() async {
  final db = AppDb.instance.db;
  final now = DateTime.now().toIso8601String();
  final factoryId = await db.insert('parties', {'type': 'factory', 'name': 'مصنع اختبار', 'created': now});
  final traderId = await db.insert('parties', {'type': 'trader', 'name': 'تاجر اختبار', 'created': now});
  final driverId = await db.insert('drivers', {'name': 'سائق اختبار', 'phone': '777000111', 'driver_kind': 'independent', 'created': now});
  final truckId = await db.insert('trucks', {'plate': 'اختبار-1', 'owner_kind': 'driver', 'created': now});
  final productRows = await db.query('products');
  final productId = productRows.first['id'] as int;
  return {'factory': factoryId, 'trader': traderId, 'driver': driverId, 'truck': truckId, 'product': productId};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await freshTestDb();
    await loginAsAdmin();
  });

  test('ترحيل الحمولة ينشئ قيدًا متوازنًا ويحرّك المخزون والحسابات الفرعية معًا', () async {
    final ids = await _seedBasics();
    final input = LoadInput(
      dateTime: DateTime.now(),
      factoryId: ids['factory']!,
      traderId: ids['trader']!,
      driverId: ids['driver']!,
      truckId: ids['truck']!,
      productId: ids['product']!,
      bags: 100,
      weightTons: 5,
      purchasePriceBag: 20,
      transportFareBag: 2,
      commissionBag: 0.5,
      incentiveBag: 0.2,
      transportBeneficiary: TransportBeneficiary.driver,
    );
    final loadId = await LoadOperationService.registerDraft(input, createdBy: Session.instance.user!.id);
    await LoadOperationService.postLoad(loadId, postedBy: Session.instance.user!.id);

    final loadRow = (await AppDb.instance.q('SELECT * FROM loads WHERE id=?', [loadId])).first;
    expect(loadRow['status'], 'posted');
    expect(loadRow['journal_id'], isNotNull);

    // المخزون تحرّك فعليًا
    final product = (await AppDb.instance.q('SELECT * FROM products WHERE id=?', [ids['product']])).first;
    expect((product['stock_bags'] as num).toDouble(), 100);
    expect((product['avg_unit_cost'] as num).toDouble(), closeTo(20, 0.01));

    // القيد متوازن
    final unbalanced = await AccountingEngine.findUnbalancedJournals();
    expect(unbalanced, isEmpty);

    // حركة مخزون سُجّلت
    final moves = await AppDb.instance.q('SELECT * FROM stock_moves WHERE source_id=? AND source_type=?', [loadId, 'loads']);
    expect(moves, isNotEmpty);

    // إشعار واتساب أُنشئ بحالة pending أو failed (ليس sent بدون تأكيد فعلي)
    final notifs = await AppDb.instance.q('SELECT * FROM notifications WHERE load_id=?', [loadId]);
    expect(notifs, isNotEmpty);
    expect(notifs.first['status'], isNot('sent'));
  });

  test('منع الترحيل المكرر لنفس العملية (Idempotency)', () async {
    final ids = await _seedBasics();
    final input = LoadInput(
      dateTime: DateTime.now(),
      factoryId: ids['factory']!,
      driverId: ids['driver']!,
      truckId: ids['truck']!,
      productId: ids['product']!,
      bags: 50,
      weightTons: 2.5,
      purchasePriceBag: 15,
    );
    final loadId = await LoadOperationService.registerDraft(input, createdBy: Session.instance.user!.id);
    await LoadOperationService.postLoad(loadId, postedBy: Session.instance.user!.id);

    expect(
      () => LoadOperationService.postLoad(loadId, postedBy: Session.instance.user!.id),
      throwsA(isA<AlreadyPostedException>()),
    );
  });

  test('لا يمكن حذف عملية مرحّلة — العكس المحاسبي فقط، ويعيد أثر المخزون', () async {
    final ids = await _seedBasics();
    final input = LoadInput(
      dateTime: DateTime.now(),
      factoryId: ids['factory']!,
      driverId: ids['driver']!,
      truckId: ids['truck']!,
      productId: ids['product']!,
      bags: 40,
      weightTons: 2,
      purchasePriceBag: 10,
    );
    final loadId = await LoadOperationService.registerDraft(input, createdBy: Session.instance.user!.id);
    await LoadOperationService.postLoad(loadId, postedBy: Session.instance.user!.id);

    await LoadOperationService.reversePostedLoad(loadId, userId: Session.instance.user!.id, reason: 'اختبار العكس');

    final loadRow = (await AppDb.instance.q('SELECT * FROM loads WHERE id=?', [loadId])).first;
    expect(loadRow['status'], 'reversed');
    expect(loadRow['reversal_journal_id'], isNotNull);

    final product = (await AppDb.instance.q('SELECT * FROM products WHERE id=?', [ids['product']])).first;
    expect((product['stock_bags'] as num).toDouble(), 0, reason: 'يجب أن يعود المخزون كما كان قبل الحمولة بعد العكس');

    // لا يمكن عكسها مرة أخرى ولا ترحيلها مجددًا
    expect(
      () => LoadOperationService.postLoad(loadId, postedBy: Session.instance.user!.id),
      throwsA(isA<NotPostedException>()),
    );
  });

  test('صافي العمولة = إجمالي العمولة + إجمالي الحافز', () async {
    final ids = await _seedBasics();
    final input = LoadInput(
      dateTime: DateTime.now(),
      factoryId: ids['factory']!,
      driverId: ids['driver']!,
      truckId: ids['truck']!,
      productId: ids['product']!,
      bags: 10,
      weightTons: 0.5,
      purchasePriceBag: 20,
      commissionBag: 1,
      incentiveBag: 0.5,
    );
    expect(input.commissionTotal, 10);
    expect(input.incentiveTotal, 5);
    expect(input.netCommission, 15);
  });

  test('الصلاحيات: دور بلا صلاحية ترحيل لا يستطيع ترحيل الحمولة', () async {
    final ids = await _seedBasics();
    // أنشئ مستخدمًا بدور "تقارير" (لا يملك صلاحية الترحيل حسب الإعداد الافتراضي)
    final salt = AppDb.newSalt();
    await AppDb.instance.ins('users', {
      'username': 'viewer',
      'password_hash': AppDb.hashPassword('viewer123', salt),
      'password_salt': salt,
      'full_name': 'مستخدم عرض فقط',
      'role': 'reports',
      'created': DateTime.now().toIso8601String(),
    });
    final input = LoadInput(
      dateTime: DateTime.now(),
      factoryId: ids['factory']!,
      driverId: ids['driver']!,
      truckId: ids['truck']!,
      productId: ids['product']!,
      bags: 5,
      weightTons: 0.25,
      purchasePriceBag: 20,
    );
    final loadId = await LoadOperationService.registerDraft(input, createdBy: Session.instance.user!.id);

    await Session.instance.login('viewer', 'viewer123');
    expect(
      () => LoadOperationService.postLoad(loadId, postedBy: Session.instance.user!.id),
      throwsA(isA<PermissionDeniedException>()),
    );
  });
}
