import 'dart:async';
import 'package:flutter/material.dart';
import 'package:libstore/torex_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = TorexStorage();
  await db.init();

  runApp(TorexStoreApp(db: db));
}

class TorexStoreApp extends StatelessWidget {
  final TorexStorage db;

  const TorexStoreApp({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TOREX Store',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C3CE1),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
      home: HomePage(db: db),
    );
  }
}

// ─── Home Page ──────────────────────────────────────────────────────────────

class HomePage extends StatefulWidget {
  final TorexStorage db;
  const HomePage({super.key, required this.db});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<TorexDocument> _users = [];
  List<TorexDocument> _products = [];
  StreamSubscription<StoreChangeEvent>? _userSubscription;
  StreamSubscription<StoreChangeEvent>? _productSubscription;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    _setupWatchers();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final users = await widget.db.getAll('users');
      final products = await widget.db.getAll('products');
      setState(() {
        _users = users;
        _products = products;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      _showSnackBar('Xatolik: $e', isError: true);
    }
  }

  void _setupWatchers() {
    _userSubscription = widget.db.watch('users').listen((event) {
      _loadData();
      _showSnackBar('Users: ${event.type.name} - ${event.id}');
    });

    _productSubscription = widget.db.watch('products').listen((event) {
      _loadData();
      _showSnackBar('Products: ${event.type.name} - ${event.id}');
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _addUser() async {
    final id = widget.db.generateId();
    final names = ['Alice', 'Bob', 'Charlie', 'Diana', 'Eve', 'Frank', 'Grace'];
    final cities = ['Tashkent', 'Samarkand', 'Bukhara', 'Khiva', 'Namangan'];

    final doc = TorexDocument(
      id: id,
      fields: {
        'name': names[DateTime.now().millisecond % names.length],
        'age': 18 + DateTime.now().second % 50,
        'city': cities[DateTime.now().millisecond % cities.length],
        'active': true,
        'score': (DateTime.now().millisecond % 100).toDouble(),
      },
    );

    await widget.db.put('users', doc);
  }

  Future<void> _addProduct() async {
    final id = widget.db.generateId();
    final products = ['Laptop', 'Phone', 'Tablet', 'Monitor', 'Keyboard', 'Mouse'];
    final categories = ['Electronics', 'Accessories', 'Computing'];

    final doc = TorexDocument(
      id: id,
      fields: {
        'name': products[DateTime.now().millisecond % products.length],
        'price': (50 + DateTime.now().second % 2000).toDouble(),
        'category': categories[DateTime.now().millisecond % categories.length],
        'inStock': true,
        'quantity': 1 + DateTime.now().second % 100,
      },
    );

    await widget.db.put('products', doc);
  }

  Future<void> _deleteItem(String collection, String id) async {
    await widget.db.delete(collection, id);
  }

  Future<void> _queryAdults() async {
    final results = await widget.db.query('users', QueryFilter.gte('age', 25));
    setState(() => _users = results);
    _showSnackBar('Topildi: ${results.length} ta foydalanuvchi (age >= 25)');
  }

  Future<void> _queryExpensiveProducts() async {
    final results = await widget.db.query('products', QueryFilter.gt('price', 500));
    setState(() => _products = results);
    _showSnackBar('Topildi: ${results.length} ta mahsulot (price > 500)');
  }

  Future<void> _runCompact() async {
    final result = await widget.db.compact();
    _showSnackBar(result);
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    _productSubscription?.cancel();
    _tabController.dispose();
    widget.db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TOREX Store',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.people), text: 'Users'),
            Tab(icon: Icon(Icons.inventory_2), text: 'Products'),
            Tab(icon: Icon(Icons.settings), text: 'Tools'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildUsersTab(),
                _buildProductsTab(),
                _buildToolsTab(),
              ],
            ),
    );
  }

  // ─── Users Tab ─────────────────────────────────────────────────────────

  Widget _buildUsersTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _addUser,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Foydalanuvchi qo\'shish'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _queryAdults,
                icon: const Icon(Icons.search),
                label: const Text('age ≥ 25'),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                tooltip: 'Yangilash',
              ),
            ],
          ),
        ),
        Expanded(
          child: _users.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Foydalanuvchilar yo\'q',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '"Foydalanuvchi qo\'shish" tugmasini bosing',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _users.length,
                  itemBuilder: (context, index) {
                    final user = _users[index];
                    final name = user['name'] as String? ?? '?';
                    final age = user['age']?.toString() ?? '?';
                    final city = user['city'] as String? ?? '?';
                    final active = user['active'] as bool? ?? false;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: active
                              ? Colors.green.shade100
                              : Colors.grey.shade300,
                          child: Text(
                            name[0].toUpperCase(),
                            style: TextStyle(
                              color: active
                                  ? Colors.green.shade700
                                  : Colors.grey,
                            ),
                          ),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('Yosh: $age | Shahar: $city'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Chip(
                              label: Text(
                                active ? 'Faol' : 'Nofaol',
                                style: const TextStyle(fontSize: 12),
                              ),
                              backgroundColor: active
                                  ? Colors.green.shade100
                                  : Colors.red.shade100,
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _deleteItem('users', user.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ─── Products Tab ──────────────────────────────────────────────────────

  Widget _buildProductsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _addProduct,
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('Mahsulot qo\'shish'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _queryExpensiveProducts,
                icon: const Icon(Icons.search),
                label: const Text('price > 500'),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                tooltip: 'Yangilash',
              ),
            ],
          ),
        ),
        Expanded(
          child: _products.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Mahsulotlar yo\'q',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '"Mahsulot qo\'shish" tugmasini bosing',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _products.length,
                  itemBuilder: (context, index) {
                    final product = _products[index];
                    final name = product['name'] as String? ?? '?';
                    final price = product['price']?.toString() ?? '?';
                    final category = product['category'] as String? ?? '?';
                    final quantity = product['quantity']?.toString() ?? '?';
                    final inStock = product['inStock'] as bool? ?? false;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: inStock
                              ? Colors.orange.shade100
                              : Colors.grey.shade300,
                          child: Icon(
                            inStock ? Icons.check : Icons.close,
                            color: inStock ? Colors.orange : Colors.grey,
                          ),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('Kategoriya: $category | Miqdor: $quantity'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '\$$price',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _deleteItem('products', product.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ─── Tools Tab ─────────────────────────────────────────────────────────

  Widget _buildToolsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ma\'lumotlar bazasi',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                FutureBuilder<int>(
                  future: widget.db.count('users'),
                  builder: (context, snapshot) => _buildStatRow(
                    Icons.people,
                    'Foydalanuvchilar',
                    '${snapshot.data ?? 0} ta',
                  ),
                ),
                const SizedBox(height: 8),
                FutureBuilder<int>(
                  future: widget.db.count('products'),
                  builder: (context, snapshot) => _buildStatRow(
                    Icons.inventory_2,
                    'Mahsulotlar',
                    '${snapshot.data ?? 0} ta',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Operatsiyalar',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _runCompact,
                    icon: const Icon(Icons.cleaning_services),
                    label: const Text('Compaction (Diskni tozalash)'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () async {
                      final collections = await widget.db.collections();
                      _showSnackBar('Kolleksiyalar: ${collections.join(', ')}');
                    },
                    icon: const Icon(Icons.folder),
                    label: const Text('Kolleksiyalar ro\'yxati'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _loadData,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Barcha ma\'lumotlarni yangilash'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Query misollar',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                _buildQueryChip('Tenglash', 'QueryFilter.eq("name", "Alice")'),
                _buildQueryChip('Katta', 'QueryFilter.gt("age", 18)'),
                _buildQueryChip('Kichik', 'QueryFilter.lt("price", 100)'),
                _buildQueryChip('Diapazon', 'QueryFilter.range("age", 18, 30)'),
                _buildQueryChip('Mantiqiy VA', 'QueryFilter.and([gt("age",18), eq("city","Tashkent"))])'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildQueryChip(String title, String code) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                code,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
