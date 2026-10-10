import 'dart:convert';

import 'models.dart';

const String kCategoryRulesKey = 'category.rules';

class CategoryRule {
  final String keyword;
  final String category;

  const CategoryRule({required this.keyword, required this.category});
}

List<CategoryRule> decodeRules(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final data = jsonDecode(raw);
    if (data is! List) return const [];
    final out = <CategoryRule>[];
    for (final e in data) {
      if (e is! Map) continue;
      final keyword = (e['keyword'] as String?)?.trim() ?? '';
      final category = (e['category'] as String?)?.trim() ?? '';
      if (keyword.isEmpty || category.isEmpty) continue;
      out.add(CategoryRule(keyword: keyword, category: category));
    }
    return out;
  } catch (_) {
    return const [];
  }
}

String encodeRules(List<CategoryRule> rules) => jsonEncode([
  for (final r in rules) {'keyword': r.keyword, 'category': r.category},
]);

List<CategoryRule> _matchOrder(List<CategoryRule> rules) =>
    [...rules]..sort((a, b) => b.keyword.length.compareTo(a.keyword.length));

String? _match(Txn t, List<CategoryRule> order) {
  final hay = [
    for (final s in [t.counterparty, t.item])
      if (s != null && s.trim().isNotEmpty) s.toLowerCase(),
  ];
  if (hay.isEmpty) return null;
  for (final r in order) {
    final k = r.keyword.toLowerCase();
    if (hay.any((h) => h.contains(k))) return r.category;
  }
  return null;
}

Txn _withCategory(Txn t, String category) => Txn(
  id: t.id,
  recordId: t.recordId,
  date: t.date,
  currency: t.currency,
  type: t.type,
  counterparty: t.counterparty,
  item: t.item,
  direction: t.direction,
  amountCents: t.amountCents,
  category: category,
);

List<Txn> applyRules(Iterable<Txn> txns, List<CategoryRule> rules) {
  final out = txns.toList();
  if (rules.isEmpty) return out;
  final order = _matchOrder(rules);
  return [
    for (final t in out)
      if (t.category != null && t.category!.trim().isNotEmpty)
        t
      else
        _matchedOrSelf(t, order),
  ];
}

Txn _matchedOrSelf(Txn t, List<CategoryRule> order) {
  final category = _match(t, order);
  return category == null ? t : _withCategory(t, category);
}
