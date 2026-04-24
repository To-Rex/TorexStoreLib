import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:torexstore/torexstore.dart';
import 'package:torexstore_app/main.dart';

/// Helper: vaqtinchalik papkada TorexStore konfiguratsiya qiladi
Future<void> _setupTestDb() async {
  final tempDir = Directory.systemTemp.createTempSync('torex_test_').path;
  TorexStore.configure(TorexStoreConfig(
    customPath: tempDir,
    idleTimeout: Duration.zero, // Disable idle timeout for tests
  ));
}

/// Helper: testdan keyin tozalash
Future<void> _cleanup() async {
  final path = TorexStore.instance.path;
  await TorexStore.reset();
  if (path != null) {
    final dir = Directory(path);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

void main() {
  group('TorexStoreApp Widget Tests', () {
    setUp(() async {
      await _setupTestDb();
    });

    tearDown(() async {
      await _cleanup();
    });

    testWidgets('Ilova muvaffaqiyatli yuklanadi', (tester) async {
      await tester.pumpWidget(const TorexStoreApp());
      await tester.pumpAndSettle();

      expect(find.text('TOREX Store'), findsOneWidget);
    });

    testWidgets('TabBar 3 ta tab ko\'rsatadi', (tester) async {
      await tester.pumpWidget(const TorexStoreApp());
      await tester.pumpAndSettle();

      expect(find.text('Users'), findsOneWidget);
      expect(find.text('Products'), findsOneWidget);
      expect(find.text('Tools'), findsOneWidget);
    });

    testWidgets('Users tab bo\'sh holatda to\'g\'ri matn ko\'rsatadi',
        (tester) async {
      await tester.pumpWidget(const TorexStoreApp());
      await tester.pumpAndSettle();

      expect(find.text('Foydalanuvchilar yo\'q'), findsOneWidget);
      expect(
          find.text('"Foydalanuvchi qo\'shish" tugmasini bosing'),
          findsOneWidget);
    });

    testWidgets('Products tab bo\'sh holatda to\'g\'ri matn ko\'rsatadi',
        (tester) async {
      await tester.pumpWidget(const TorexStoreApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Products'));
      await tester.pumpAndSettle();

      expect(find.text('Mahsulotlar yo\'q'), findsOneWidget);
      expect(
          find.text('"Mahsulot qo\'shish" tugmasini bosing'),
          findsOneWidget);
    });

    testWidgets('Tools tab to\'g\'ri render bo\'ladi', (tester) async {
      await tester.pumpWidget(const TorexStoreApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tools'));
      await tester.pumpAndSettle();

      expect(find.text('Ma\'lumotlar bazasi'), findsOneWidget);
      expect(find.text('Operatsiyalar'), findsOneWidget);
      expect(find.text('Compaction (Diskni tozalash)'), findsOneWidget);
      expect(find.text('Kolleksiyalar ro\'yxati'), findsOneWidget);
      expect(find.text('Barcha ma\'lumotlarni yangilash'), findsOneWidget);
    });

    testWidgets('Foydalanuvchi qo\'shish tugmasi mavjud', (tester) async {
      await tester.pumpWidget(const TorexStoreApp());
      await tester.pumpAndSettle();

      expect(find.text('Foydalanuvchi qo\'shish'), findsOneWidget);
    });

    testWidgets('Mahsulot qo\'shish tugmasi mavjud', (tester) async {
      await tester.pumpWidget(const TorexStoreApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Products'));
      await tester.pumpAndSettle();

      expect(find.text('Mahsulot qo\'shish'), findsOneWidget);
    });

    testWidgets('Foydalanuvchi qo\'shish tugmasini bosganda yangi user paydo bo\'ladi',
        (tester) async {
      await tester.pumpWidget(const TorexStoreApp());
      await tester.pumpAndSettle();

      expect(find.text('Foydalanuvchilar yo\'q'), findsOneWidget);

      await tester.tap(find.text('Foydalanuvchi qo\'shish'));
      await tester.pumpAndSettle();

      expect(find.text('Foydalanuvchilar yo\'q'), findsNothing);
      expect(find.byType(Card), findsWidgets);
    });

    testWidgets('Mahsulot qo\'shish tugmasini bosganda yangi product paydo bo\'ladi',
        (tester) async {
      await tester.pumpWidget(const TorexStoreApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Products'));
      await tester.pumpAndSettle();

      expect(find.text('Mahsulotlar yo\'q'), findsOneWidget);

      await tester.tap(find.text('Mahsulot qo\'shish'));
      await tester.pumpAndSettle();

      expect(find.text('Mahsulotlar yo\'q'), findsNothing);
      expect(find.byType(Card), findsWidgets);
    });

    testWidgets('Foydalanuvchi qo\'shib, keyin o\'chirish mumkin',
        (tester) async {
      await tester.pumpWidget(const TorexStoreApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Foydalanuvchi qo\'shish'));
      await tester.pumpAndSettle();

      final deleteButtons = find.byIcon(Icons.delete_outline);
      expect(deleteButtons, findsOneWidget);

      await tester.tap(deleteButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('Foydalanuvchilar yo\'q'), findsOneWidget);
    });

    testWidgets('Mahsulot qo\'shib, keyin o\'chirish mumkin',
        (tester) async {
      await tester.pumpWidget(const TorexStoreApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Products'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mahsulot qo\'shish'));
      await tester.pumpAndSettle();

      final deleteButtons = find.byIcon(Icons.delete_outline);
      expect(deleteButtons, findsOneWidget);

      await tester.tap(deleteButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('Mahsulotlar yo\'q'), findsOneWidget);
    });

    testWidgets('age ≥ 25 query tugmasi mavjud', (tester) async {
      await tester.pumpWidget(const TorexStoreApp());
      await tester.pumpAndSettle();

      expect(find.text('age ≥ 25'), findsOneWidget);
    });

    testWidgets('price > 500 query tugmasi mavjud', (tester) async {
      await tester.pumpWidget(const TorexStoreApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Products'));
      await tester.pumpAndSettle();

      expect(find.text('price > 500'), findsOneWidget);
    });

    testWidgets('Tools tab da statistika ko\'rsatiladi', (tester) async {
      final db = TorexStore.instance;
      await db.put(
          'users',
          TorexDocument(
              id: 'test_user_1', fields: {'name': 'Alice', 'age': 25}));
      await db.put(
          'products',
          TorexDocument(
              id: 'test_product_1',
              fields: {'name': 'Laptop', 'price': 999.0}));

      await tester.pumpWidget(const TorexStoreApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tools'));
      await tester.pumpAndSettle();

      expect(find.text('Foydalanuvchilar'), findsOneWidget);
      expect(find.text('Mahsulotlar'), findsOneWidget);
    });

    testWidgets('Yangilash tugmasi ishlaydi', (tester) async {
      await tester.pumpWidget(const TorexStoreApp());
      await tester.pumpAndSettle();

      final refreshButtons = find.byIcon(Icons.refresh);
      expect(refreshButtons, findsWidgets);

      await tester.tap(refreshButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('TOREX Store'), findsOneWidget);
    });

    testWidgets('Compaction tugmasi bosiladi', (tester) async {
      await tester.pumpWidget(const TorexStoreApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tools'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Compaction (Diskni tozalash)'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('TorexStore Unit Tests', () {
    setUp(() async {
      await _setupTestDb();
    });

    tearDown(() async {
      await _cleanup();
    });

    test('Auto-init birinchi operatsiyada ishlaydi', () async {
      final db = TorexStore.instance;
      // Birinchi operatsiya auto-init qiladi
      await db.put('users', TorexDocument(id: 'u1', fields: {'name': 'Alice'}));
      expect(db.isReady, true);
      expect(db.path, isNotNull);
    });

    test('put() va get() to\'g\'ri ishlaydi', () async {
      final db = TorexStore.instance;
      final doc = TorexDocument(
          id: 'user_1', fields: {'name': 'Alice', 'age': 25});
      await db.put('users', doc);

      final result = await db.get('users', 'user_1');
      expect(result, isNotNull);
      expect(result!.id, 'user_1');
      expect(result['name'], 'Alice');
      expect(result['age'], 25);
    });

    test('getAll() bo\'sh kolleksiya uchun [] qaytaradi', () async {
      final db = TorexStore.instance;
      final result = await db.getAll('nonexistent');
      expect(result, isEmpty);
    });

    test('delete() hujjatni o\'chiradi', () async {
      final db = TorexStore.instance;
      final doc = TorexDocument(
          id: 'user_1', fields: {'name': 'Alice', 'age': 25});
      await db.put('users', doc);

      await db.delete('users', 'user_1');
      final result = await db.get('users', 'user_1');
      expect(result, isNull);
    });

    test('exists() mavjudlikni tekshiradi', () async {
      final db = TorexStore.instance;
      final doc = TorexDocument(
          id: 'user_1', fields: {'name': 'Alice', 'age': 25});
      await db.put('users', doc);

      expect(await db.exists('users', 'user_1'), true);
      expect(await db.exists('users', 'user_999'), false);
    });

    test('count() to\'g\'ri hisoblaydi', () async {
      final db = TorexStore.instance;
      expect(await db.count('users'), 0);

      await db.put(
          'users',
          TorexDocument(
              id: 'u1', fields: {'name': 'Alice', 'age': 25}));
      await db.put(
          'users',
          TorexDocument(
              id: 'u2', fields: {'name': 'Bob', 'age': 30}));

      expect(await db.count('users'), 2);
    });

    test('collections() kolleksiya nomlarini qaytaradi', () async {
      final db = TorexStore.instance;
      await db.put(
          'users',
          TorexDocument(
              id: 'u1', fields: {'name': 'Alice', 'age': 25}));
      await db.put(
          'products',
          TorexDocument(
              id: 'p1', fields: {'name': 'Laptop', 'price': 999.0}));

      final cols = await db.collections();
      expect(cols, containsAll(['users', 'products']));
    });

    test('query() eq filter to\'g\'ri ishlaydi', () async {
      final db = TorexStore.instance;
      await db.put(
          'users',
          TorexDocument(
              id: 'u1', fields: {'name': 'Alice', 'age': 25}));
      await db.put(
          'users',
          TorexDocument(
              id: 'u2', fields: {'name': 'Bob', 'age': 30}));

      final result =
          await db.query('users', QueryFilter.eq('name', 'Alice'));
      expect(result.length, 1);
      expect(result.first['name'], 'Alice');
    });

    test('query() gt filter to\'g\'ri ishlaydi', () async {
      final db = TorexStore.instance;
      await db.put(
          'users',
          TorexDocument(
              id: 'u1', fields: {'name': 'Alice', 'age': 25}));
      await db.put(
          'users',
          TorexDocument(
              id: 'u2', fields: {'name': 'Bob', 'age': 30}));
      await db.put(
          'users',
          TorexDocument(
              id: 'u3', fields: {'name': 'Charlie', 'age': 17}));

      final result =
          await db.query('users', QueryFilter.gt('age', 20));
      expect(result.length, 2);
    });

    test('query() gte filter to\'g\'ri ishlaydi', () async {
      final db = TorexStore.instance;
      await db.put(
          'users',
          TorexDocument(
              id: 'u1', fields: {'name': 'Alice', 'age': 25}));
      await db.put(
          'users',
          TorexDocument(
              id: 'u2', fields: {'name': 'Bob', 'age': 30}));
      await db.put(
          'users',
          TorexDocument(
              id: 'u3', fields: {'name': 'Charlie', 'age': 17}));

      final result =
          await db.query('users', QueryFilter.gte('age', 25));
      expect(result.length, 2);
    });

    test('query() range filter to\'g\'ri ishlaydi', () async {
      final db = TorexStore.instance;
      await db.put(
          'users',
          TorexDocument(
              id: 'u1', fields: {'name': 'Alice', 'age': 20}));
      await db.put(
          'users',
          TorexDocument(
              id: 'u2', fields: {'name': 'Bob', 'age': 25}));
      await db.put(
          'users',
          TorexDocument(
              id: 'u3', fields: {'name': 'Charlie', 'age': 35}));

      final result =
          await db.query('users', QueryFilter.range('age', 20, 30));
      expect(result.length, 2); // 20 va 25 (30 kirmaydi)
    });

    test('query() and filter to\'g\'ri ishlaydi', () async {
      final db = TorexStore.instance;
      await db.put(
          'users',
          TorexDocument(
              id: 'u1',
              fields: {'name': 'Alice', 'age': 25, 'city': 'Tashkent'}));
      await db.put(
          'users',
          TorexDocument(
              id: 'u2',
              fields: {'name': 'Bob', 'age': 30, 'city': 'Samarkand'}));
      await db.put(
          'users',
          TorexDocument(
              id: 'u3',
              fields: {'name': 'Charlie', 'age': 20, 'city': 'Tashkent'}));

      final result = await db.query(
          'users',
          QueryFilter.and([
            QueryFilter.gte('age', 25),
            QueryFilter.eq('city', 'Tashkent'),
          ]));
      expect(result.length, 1);
      expect(result.first['name'], 'Alice');
    });

    test('query() or filter to\'g\'ri ishlaydi', () async {
      final db = TorexStore.instance;
      await db.put(
          'users',
          TorexDocument(
              id: 'u1', fields: {'name': 'Alice', 'age': 25}));
      await db.put(
          'users',
          TorexDocument(
              id: 'u2', fields: {'name': 'Bob', 'age': 30}));
      await db.put(
          'users',
          TorexDocument(
              id: 'u3', fields: {'name': 'Charlie', 'age': 17}));

      final result = await db.query(
          'users',
          QueryFilter.or([
            QueryFilter.eq('name', 'Alice'),
            QueryFilter.eq('name', 'Charlie'),
          ]));
      expect(result.length, 2);
    });

    test('generateId() noyob ID generatsiya qiladi', () {
      final db = TorexStore.instance;
      final id1 = db.generateId();
      final id2 = db.generateId();
      expect(id1, isNot(equals(id2)));
      expect(id1, isNotEmpty);
    });

    test('compact() muvaffaqiyatli ishlaydi', () async {
      final db = TorexStore.instance;
      await db.put(
          'users',
          TorexDocument(
              id: 'u1', fields: {'name': 'Alice', 'age': 25}));
      await db.delete('users', 'u1');

      final result = await db.compact();
      expect(result, contains('Compaction'));
    });

    test('watch() stream hodisalarni yuboradi', () async {
      final db = TorexStore.instance;
      final events = <StoreChangeEvent>[];
      db.watch('users').listen(events.add);

      await db.put(
          'users',
          TorexDocument(
              id: 'u1', fields: {'name': 'Alice', 'age': 25}));

      await Future.delayed(const Duration(milliseconds: 100));

      expect(events.length, 1);
      expect(events.first.type, StoreEventType.insert);
      expect(events.first.id, 'u1');
    });

    test('watch() update hodisani yuboradi', () async {
      final db = TorexStore.instance;
      final events = <StoreChangeEvent>[];
      db.watch('users').listen(events.add);

      await db.put(
          'users',
          TorexDocument(
              id: 'u1', fields: {'name': 'Alice', 'age': 25}));
      await db.put(
          'users',
          TorexDocument(
              id: 'u1', fields: {'name': 'Alice Updated', 'age': 26}));

      await Future.delayed(const Duration(milliseconds: 100));

      expect(events.length, 2);
      expect(events[0].type, StoreEventType.insert);
      expect(events[1].type, StoreEventType.update);
    });

    test('watch() delete hodisani yuboradi', () async {
      final db = TorexStore.instance;
      final events = <StoreChangeEvent>[];
      db.watch('users').listen(events.add);

      await db.put(
          'users',
          TorexDocument(
              id: 'u1', fields: {'name': 'Alice', 'age': 25}));
      await db.delete('users', 'u1');

      await Future.delayed(const Duration(milliseconds: 100));

      expect(events.length, 2);
      expect(events[0].type, StoreEventType.insert);
      expect(events[1].type, StoreEventType.delete);
    });

    test('Singleton pattern ishlaydi', () async {
      final db1 = TorexStore.instance;
      final db2 = TorexStore.I;
      expect(identical(db1, db2), true);
    });

    test('Bo\'sh collection nomi bilan xato otadi', () async {
      final db = TorexStore.instance;
      // Auto-init first
      await db.count('test');
      await expectLater(
        db.put('', TorexDocument(id: 'x', fields: {})),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
