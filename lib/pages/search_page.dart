import 'package:flutter/material.dart';

import '../db.dart';
import '../icons.dart';
import '../models.dart';
import '../widgets/txn_list.dart';
import 'txn_edit_page.dart';

/// 搜交易对象 / 商品 / 分类 / 类型，结果也按天分组。
class SearchPage extends StatefulWidget {
  final TxnDao dao;

  const SearchPage({super.key, required this.dao});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();

  List<Txn> _results = const [];
  Map<String, String> _categoryIcons = const {};
  bool _touched = false;

  /// 输入快的时候查询会乱序回来，用序号把旧结果丢掉
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQuery);
    _loadIcons();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadIcons() async {
    final m = await widget.dao.categoryIcons();
    if (mounted) setState(() => _categoryIcons = m);
  }

  Future<void> _onQuery() async {
    final seq = ++_seq;
    final kw = _controller.text.trim();

    if (kw.isEmpty) {
      setState(() {
        _results = const [];
        _touched = false;
      });
      return;
    }

    final r = await widget.dao.search(kw);
    if (!mounted || seq != _seq) return;
    setState(() {
      _results = r;
      _touched = true;
    });
  }

  Future<void> _openEditor(Txn txn) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TxnEditPage(dao: widget.dao, txn: txn),
      ),
    );
    if (changed == true) await _onQuery();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '搜交易对象 / 商品 / 分类 / 类型',
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              onPressed: () {
                _controller.clear();
                _onQuery();
              },
              icon: Icon(AppIcons.resolve('clear')),
              tooltip: '清空',
            ),
        ],
      ),
      body: !_touched
          ? Center(
              child: Text(
                '输入关键词开始找',
                style: tt.bodyMedium?.copyWith(color: cs.outline),
              ),
            )
          : _results.isEmpty
          ? Center(
              child: Text(
                '没找到「${_controller.text.trim()}」',
                style: tt.bodyMedium?.copyWith(color: cs.outline),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '找到 ${_results.length} 条',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
                Expanded(
                  child: TxnDayList(
                    txns: _results,
                    categoryIcons: _categoryIcons,
                    onTap: _openEditor,
                  ),
                ),
              ],
            ),
    );
  }
}
