import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'VoiceExpensePage.dart';

/// Update this to your API base URL
const String baseUrl = "https://beatporttopcharts.com/php/api/expense";

/// Model
class Expense {
  final int id;
  final String category;
  final double amount;
  final DateTime createdAt;

  Expense({
    required this.id,
    required this.category,
    required this.amount,
    required this.createdAt,
  });

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: j['id'] as int,
        category: j['category'] as String,
        amount: double.parse(j['amount'].toString()),
        createdAt: DateTime.parse(j['created_at']),
      );
}

/// API response container
class ExpenseListResponse {
  final List<Expense> items;
  final int totalCount;
  final bool hasMore;
  final int page;
  final int pageSize;
  final List<String> categories; // Distinct categories (optional)
  ExpenseListResponse({
    required this.items,
    required this.totalCount,
    required this.hasMore,
    required this.page,
    required this.pageSize,
    required this.categories,
  });

  factory ExpenseListResponse.fromJson(Map<String, dynamic> j) {
    final items = (j['items'] as List<dynamic>)
        .map((e) => Expense.fromJson(e as Map<String, dynamic>))
        .toList();
    return ExpenseListResponse(
      items: items,
      totalCount: j['total'] ?? items.length,
      hasMore: j['has_more'] ?? false,
      page: j['page'] ?? 1,
      pageSize: j['page_size'] ?? items.length,
      categories: (j['categories'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

class ExpensesDashboardPage extends StatefulWidget {
  const ExpensesDashboardPage({super.key});

  @override
  State<ExpensesDashboardPage> createState() => _ExpensesDashboardPageState();
}

class _ExpensesDashboardPageState extends State<ExpensesDashboardPage> {
  // Filters
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _categoryFilter;
  final TextEditingController _searchCtrl = TextEditingController();

  // Data
  List<Expense> _expenses = [];
  List<String> _categories = [];
  bool _loading = false;
  bool _hasMore = false;
  int _page = 1;
  final int _pageSize = 50;

  // UK formatting
  final NumberFormat gbpFmt =
      NumberFormat.currency(locale: 'en_GB', symbol: '£');
  final DateFormat dateFmt = DateFormat('dd MMM yyyy', 'en_GB');

  @override
  void initState() {
    super.initState();
    _loadExpenses(reset: true);
  }

  Future<void> _loadExpenses({bool reset = false}) async {
    setState(() => _loading = true);
    try {
      if (reset) {
        _page = 1;
        _expenses.clear();
        _hasMore = false;
      }

      final uri = Uri.parse("$baseUrl/expenses_list.php").replace(
        queryParameters: {
          'page': _page.toString(),
          'page_size': _pageSize.toString(),
          if (_fromDate != null)
            'from': _fromDate!.toIso8601String().substring(0, 10),
          if (_toDate != null)
            'to': _toDate!.toIso8601String().substring(0, 10),
          if (_categoryFilter != null && _categoryFilter!.isNotEmpty)
            'category': _categoryFilter!,
          if (_searchCtrl.text.trim().isNotEmpty) 'q': _searchCtrl.text.trim(),
        },
      );

      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final jsonMap = json.decode(res.body) as Map<String, dynamic>;
        final parsed = ExpenseListResponse.fromJson(jsonMap);
        setState(() {
          _page = parsed.page;
          _hasMore = parsed.hasMore;
          _categories = parsed.categories.isNotEmpty
              ? parsed.categories
              : _categories; // keep previous if not provided
          _expenses.addAll(parsed.items);
        });
      } else {
        _showSnack("Error ${res.statusCode}: ${res.reasonPhrase}");
      }
    } catch (e) {
      _showSnack("Network error: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    await _loadExpenses(reset: true);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 2),
    ));
  }

  double get _totalAmount => _expenses.fold(0.0, (sum, e) => sum + e.amount);

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initialFirst = _fromDate ?? DateTime(now.year, now.month, 1);
    final initialLast = _toDate ?? now;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: initialFirst, end: initialLast),
      locale: const Locale('en', 'GB'),
    );
    if (picked != null) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end;
      });
      _loadExpenses(reset: true);
    }
  }

  Widget _buildFilters() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ElevatedButton.icon(
          onPressed: _pickDateRange,
          icon: const Icon(Icons.date_range),
          label: Text(
            _fromDate != null && _toDate != null
                ? "${dateFmt.format(_fromDate!)} – ${dateFmt.format(_toDate!)}"
                : "Date range",
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            value: _categoryFilter?.isEmpty == true ? null : _categoryFilter,
            hint: const Text('Category'),
            items: [
              const DropdownMenuItem(value: '', child: Text('All categories')),
              ..._categories.map(
                (c) => DropdownMenuItem(value: c, child: Text(c)),
              ),
            ],
            onChanged: (val) {
              setState(() => _categoryFilter = (val ?? '').trim());
              _loadExpenses(reset: true);
            },
          ),
        ),
        SizedBox(
          width: 240,
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: 'Search (category, amount)',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchCtrl.clear();
                  _loadExpenses(reset: true);
                },
              ),
            ),
            onSubmitted: (_) => _loadExpenses(reset: true),
          ),
        ),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _fromDate = null;
              _toDate = null;
              _categoryFilter = null;
              _searchCtrl.clear();
            });
            _loadExpenses(reset: true);
          },
          icon: const Icon(Icons.filter_alt_off),
          label: const Text('Clear filters'),
        ),
      ],
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: ListTile(
                leading: const Icon(Icons.summarize),
                title: const Text('Total'),
                subtitle: Text(
                  gbpFmt.format(_totalAmount),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text('Items: ${_expenses.length}'),
            const SizedBox(width: 8),
            if (_hasMore)
              TextButton(
                onPressed: _loading
                    ? null
                    : () {
                        setState(() => _page += 1);
                        _loadExpenses(reset: false);
                      },
                child: const Text('Load more'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading && _expenses.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_expenses.isEmpty) {
      return const Center(child: Text('No expenses found.'));
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _expenses.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, idx) {
          final e = _expenses[idx];
          return Dismissible(
            key: ValueKey("expense_${e.id}"),
            background: Container(
              color: Colors.redAccent,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            secondaryBackground: Container(
              color: Colors.redAccent,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (_) async {
              return await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Delete expense'),
                  content: Text(
                      'Delete ${e.category} (${gbpFmt.format(e.amount)}) from ${dateFmt.format(e.createdAt)}?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
            },
            onDismissed: (_) async {
              final ok = await _deleteExpense(e.id);
              if (!ok) {
                _showSnack('Delete failed');
                // Restore item if delete failed
                setState(() => _expenses.insert(idx, e));
              } else {
                _showSnack('Deleted');
              }
            },
            child: ListTile(
              leading: CircleAvatar(
                child: Text(
                  e.category.isNotEmpty ? e.category[0].toUpperCase() : '?',
                ),
              ),
              title: Text(
                e.category,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(dateFmt.format(e.createdAt)),
              trailing: Text(
                gbpFmt.format(e.amount),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool> _deleteExpense(int id) async {
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/expenses_delete.php"),
        body: {'id': id.toString()},
      );
      if (res.statusCode == 200) {
        setState(() {
          _expenses.removeWhere((x) => x.id == id);
        });
        return true;
      }
    } catch (_) {}
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(title: const Text('Expenses Dashboard')),
      appBar: AppBar(
        title: const Text('Expenses Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: "Add Expense",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VoiceExpensePage()),
              ).then((saved) {
                if (saved == true) _loadExpenses(reset: true);
              });
            },
          )
        ],
      ),
      // floatingActionButton: FloatingActionButton.extended(
      //   onPressed: () {
      //     Navigator.push(
      //       context,
      //       MaterialPageRoute(
      //         builder: (_) => const VoiceExpensePage(),
      //       ),
      //     ).then((_) => _loadExpenses(reset: true)); // Refresh after returning
      //   },
      //   icon: const Icon(Icons.add),
      //   label: const Text("Add Expense"),
      // ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const VoiceExpensePage()),
          ).then((saved) {
            if (saved == true) _loadExpenses(reset: true);
          });
        },
        icon: const Icon(Icons.mic),
        label: const Text("Add Expense"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _buildFilters(),
            const SizedBox(height: 8),
            _buildSummaryCard(),
            const SizedBox(height: 8),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }
}
