import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libstore/libstore.dart';

import 'package:torexstore/main.dart';

/// Helper: vaqtinchalik papkada TorexStorage yaratadi
Future<TorexStorage> _createTestDb() async {
  final db = TorexStorage();
  final tempDir =
      Directory.systemTemp.createTempSync('torex_test_').path;
  await db.init(path: tempDir);
  return db;
}

/// Helper: testdan keyin papkani tozalash
void _cleanup(TorexStorage db) {
  final path = db.path;
  db.close();
  if (path != null) {
    final dir = Directory(path);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

void main() {
  group('TorexStoreApp Widget Tests', () {
    late TorexStorage db;

    setUp(() async {
      db = await _createTestDb();
    });

    tearDown(() {
      _cleanup(db);
    });

    testWidgets('Ilova muvaffaqiyatli yuklanadi', (tester) async {
      await tester.pumpWidget(TorexStoreApp(db: db));
      await tester.pumpAndSettle();

      expect(find.text('TOREX Store'), findsOneWidget);
    });

    testWidgets('TabBar 3 ta tab ko\'rsatadi', (tester) async {
      await tester.pumpWidget(TorexStoreApp(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Users'), findsOneWidget);
      expect(find.text('Products'), findsOneWidget);
      expect(find.text('Tools'), findsOneWidget);
    });

    testWidgets('Users tab bo\'sh holatda to\'g\'ri matn ko\'rsatadi',
        (tester) async {
      await tester.pumpWidget(TorexStoreApp(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Foydalanuvchilar yo\'q'), findsOneWidget);
      expect(
          find.text('"Foydalanuvchi qo\'shish" tugmasini bosing'),
          findsOneWidget);
    });

    testWidgets('Products tab bo\'sh holatda to\'g\'ri matn ko\'rsatadi',
        (tester) async {
      await tester.pumpWidget(TorexStoreApp(db: db));
      await tester.pumpAndSettle();

      // Products tab ga o'tish
      await tester.tap(find.text('Products'));
      await tester.pumpAndSettle();

      expect(find.text('Mahsulotlar yo\'q'), findsOneWidget);
      expect(
          find.text('"Mahsulot qo\'shish" tugmasini bosing'),
          findsOneWidget);
    });

    testWidgets('Tools tab to\'g\'ri render bo\'ladi', (tester) async {
      await tester.pumpWidget(TorexStoreApp(db: db));
      await tester.pumpAndSettle();

      // Tools tab ga o'tish
      await tester.tap(find.text('Tools'));
      await tester.pumpAndSettle();

      expect(find.text('Ma\'lumotlar bazasi'), findsOneWidget);
      expect(find.text('Operatsiyalar'), findsOneWidget);
      expect(find.text('Compaction (Diskni tozalash)'), findsOneWidget);
      expect(find.text('Kolleksiyalar ro\'yxati'), findsOneWidget);
      expect(find.text('Barcha ma\'lumotlarni yangilash'), findsOneWidget);
    });

    testWidgets('Foydalanuvchi qo\'shish tugmasi mavjud', (tester) async {
      await tester.pumpWidget(TorexStoreApp(db: db));
      await tester.pumpAndSettle();

      expect(
          find.text('Foydalanuvchi qo\'shish'), findsOneWidget);
    });

    testWidgets('Mahsulot qo\'shish tugmasi mavjud', (tester) async {
      await tester.pumpWidget(TorexStoreApp(db: db));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Products'));
      await tester.pumpAndSettle();

      expect(find.text('Mahsulot qo\'shish'), findsOneWidget);
    });

    testWidgets('Foydalanuvchi qo\'shish tugmasini bosganda yangi user paydo bo\'ladi',
        (tester) async {
      await tester.pumpWidget(TorexStoreApp(db: db));
      await tester.pumpAndSettle();

      // Bo'sh holatni tekshirish
      expect(find.text('Foydalanuvchilar yo\'q'), findsOneWidget);

      // Foydalanuvchi qo'shish
      await tester.tap(find.text('Foydalanuvchi qo\'shish'));
      await tester.pumpAndSettle();

      // Endi bo'sh holat matni yo'q, Card paydo bo'lishi kerak
      expect(find.text('Foydalanuvchilar yo\'q'), findsNothing);
      expect(find.byType(Card), findsWidgets);
    });

    testWidgets('Mahsulot qo\'shish tugmasini bosganda yangi product paydo bo\'ladi',
        (tester) async {
      await tester.pumpWidget(TorexStoreApp(db: db));
      await tester.pumpAndSettle();

      // Products tab ga o'tish
      await tester.tap(find.text('Products'));
      await tester.pumpAndSettle();

      expect(find.text('Mahsulotlar yo\'q'), findsOneWidget);

      // Mahsulot qo'shish
      await tester.tap(find.text('Mahsulot qo\'shish'));
      await tester.pumpAndSettle();

      expect(find.text('Mahsulotlar yo\'q'), findsNothing);
      expect(find.byType(Card), findsWidgets);
    });

    testWidgets('Foydalanuvchi qo\'shib, keyin o\'chirish mumkin',
        (tester) async {
      await tester.pumpWidget(TorexStoreApp(db: db));
      await tester.pumpAndSettle();

      // Foydalanuvchi qo'shish
      await tester.tap(find.text('Foydalanuvchi qo\'shish'));
      await tester.pumpAndSettle();

      // O'chirish tugmasini topish (delete icon)
      final deleteButtons = find.byIcon(Icons.delete_outline);
      expect(deleteButtons, findsOneWidget);

      // O'chirish
      await tester.tap(deleteButtons.first);
      await tester.pumpAndSettle();

      // Qayta bo'sh holatga qaytishi kerak
      expect(find.text('Foydalanuvchilar yo\'q'), findsOneWidget);
    });

    testWidgets('Mahsulot qo\'shib, keyin o\'chirish mumkin',
        (tester) async {
      await tester.pumpWidget(TorexStoreApp(db: db));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Products'));
      await tester.pumpAndSettle();

      // Mahsulot qo'shish
      await tester.tap(find.text('Mahsulot qo\'shish'));
      await tester.pumpAndSettle();

      final deleteButtons = find.byIcon(Icons.delete_outline);
      expect(deleteButtons, findsOneWidget);

      await tester.tap(deleteButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('Mahsulotlar yo\'q'), findsOneWidget);
    });

    testWidgets('age ≥ 25 query tugmasi mavjud', (tester) async {
      await tester.pumpWidget(TorexStoreApp(db: db));
      await tester.pumpAndSettle();

      expect(find.text('age ≥ 25'), findsOneWidget);
    });

    testWidgets('price > 500 query tugmasi mavjud', (tester) async {
      await tester.pumpWidget(TorexStoreApp(db: db));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Products'));
      await tester.pumpAndSettle();

      expect(find.text('price > 500'), findsOneWidget);
    });

    testWidgets('Tools tab da statistika ko\'rsatiladi', (tester) async {
      // Avval ma'lumot qo'shamiz
      await db.put(
          'users',
          TorexDocument(
              id: 'test_user_1', fields: {'name': 'Alice', 'age': 25}));
      await db.put(
          'products',
          TorexDocument(
              id: 'test_product_1',
              fields: {'name': 'Laptop', 'price': 999.0}));

      await tester.pumpWidget(TorexStoreApp(db: db));
      await tester.pumpAndSettle();

      // Tools tab ga o'tish
      await tester.tap(find.text('Tools'));
      await tester.pumpAndSettle();

      expect(find.text('Foydalanuvchilar'), findsOneWidget);
      expect(find.text('Mahsulotlar'), findsOneWidget);
    });

    testWidgets('Yangilash tugmasi ishlaydi', (tester) async {
      await tester.pumpWidget(TorexStoreApp(db: db));
      await tester.pumpAndSettle();

      // Users tab da yangilash tugmasi
      final refreshButtons = find.byIcon(Icons.refresh);
      expect(refreshButtons, findsWidgets);

      await tester.tap(refreshButtons.first);
      await tester.pumpAndSettle();

      // Xatoliksiz qayta yuklanishi kerak
      expect(find.text('TOREX Store'), findsOneWidget);
    });

    testWidgets('Compaction tugmasi bosiladi', (tester) async {
      await tester.pumpWidget(TorexStoreApp(db: db));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tools'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Compaction (Diskni tozalash)'));
      await tester.pumpAndSettle();

      // SnackBar paydo bo'lishi kerak
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('TorexStorage Unit Tests', () {
    late TorexStorage db;

    setUp(() async {
      db = await _createTestDb();
    });

    tearDown(() {
      _cleanup(db);
    });

    test('init() muvaffaqiyatli ishlaydi', () {
      expect(db.isInitialized, true);
      expect(db.path, isNotNull);
    });

    test('put() va get() to\'g\'ri ishlaydi', () async {
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
      final result = await db.getAll('nonexistent');
      expect(result, isEmpty);
    });

    test('delete() hujjatni o\'chiradi', () async {
      final doc = TorexDocument(
          id: 'user_1', fields: {'name': 'Alice', 'age': 25});
      await db.put('users', doc);

      await db.delete('users', 'user_1');
      final result = await db.get('users', 'user_1');
      expect(result, isNull);
    });

    test('exists() mavjudlikni tekshiradi', () async {
      final doc = TorexDocument(
          id: 'user_1', fields: {'name': 'Alice', 'age': 25});
      await db.put('users', doc);

      expect(await db.exists('users', 'user_1'), true);
      expect(await db.exists('users', 'user_999'), false);
    });

    test('count() to\'g\'ri hisoblaydi', () async {
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
      final id1 = db.generateId();
      final id2 = db.generateId();
      expect(id1, isNot(equals(id2)));
      expect(id1, isNotEmpty);
    });

    test('compact() muvaffaqiyatli ishlaydi', () async {
      await db.put(
          'users',
          TorexDocument(
              id: 'u1', fields: {'name': 'Alice', 'age': 25}));
      await db.delete('users', 'u1');

      final result = await db.compact();
      expect(result, contains('Compaction tugadi'));
    });

    test('watch() stream hodisalarni yuboradi', () async {
      final events = <StoreChangeEvent>[];
      db.watch('users').listen(events.add);

      await db.put(
          'users',
          TorexDocument(
              id: 'u1', fields: {'name': 'Alice', 'age': 25}));

      // Stream hodisalar biroz vaqt oladi
      await Future.delayed(const Duration(milliseconds: 100));

      expect(events.length, 1);
      expect(events.first.type, StoreEventType.insert);
      expect(events.first.id, 'u1');
    });

    test('watch() update hodisani yuboradi', () async {
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

    test('close() va qayta init() ishlaydi', () async {
      await db.put(
          'users',
          TorexDocument(
              id: 'u1', fields: {'name': 'Alice', 'age': 25}));
      await db.close();

      expect(db.isInitialized, false);

      // Qayta init
      await db.init();
      expect(db.isInitialized, true);
    });

    test('Bo\'sh collection nomi bilan xato otadi', () async {
      expect(
        () => db.put('', TorexDocument(id: 'x', fields: {})),
        throwsArgumentError,
      );
    });

    test('Init qilinmagan holda xato otadi', () async {
      final uninitDb = TorexStorage();
      expect(
        () => uninitDb.getAll('test'),
        throwsStateError,
      );
    });
  });
}
