import 'dart:convert';
import 'dart:io';

import 'models.dart';

class BillVisibility {
  final File file;
  Set<int> _hidden;

  BillVisibility(this.file, this._hidden);

  static Future<BillVisibility> open(File file) async {
    var hidden = <int>{};
    try {
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString());
        if (raw is List) {
          hidden = {
            for (final e in raw)
              if (e is int) e,
          };
        }
      }
    } catch (_) {
      hidden = <int>{};
    }
    return BillVisibility(file, hidden);
  }

  bool isHidden(int? recordId) => recordId != null && _hidden.contains(recordId);

  bool isVisible(int? recordId) => !isHidden(recordId);

  List<Txn> visible(List<Txn> txns) => _hidden.isEmpty
      ? txns
      : [for (final t in txns) if (isVisible(t.recordId)) t];

  Future<void> setHidden(int recordId, bool hidden) {
    final next = {..._hidden};
    if (hidden) {
      next.add(recordId);
    } else {
      next.remove(recordId);
    }
    _hidden = next;
    return _persist();
  }

  Future<void> _persist() async {
    final sorted = _hidden.toList()..sort();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(sorted));
  }
}
