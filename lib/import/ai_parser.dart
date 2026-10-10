import 'dart:convert';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:http/http.dart' as http;

import '../models.dart';

const String kAiBaseUrl = 'ai.base_url';
const String kAiApiKey = 'ai.api_key';
const String kAiModel = 'ai.model';
const String kAiPrompt = 'ai.prompt';

const String kDefaultAiPrompt = '''
你是账单解析器。用户会给你一段从账单文件导出的文本（CSV、TSV 或直接复制的表格）。

请分两步处理：
1. 弄干净：读懂表头，去掉说明、空行、汇总、分页重复等非流水内容，统一引号和分隔符。
2. 映射：把每条流水映射到固定的列。

只输出一个 JSON 数组，不要解释，不要 markdown 代码块。元素形如：
{"date":"2026-01-02","type":"收付款方式","counterparty":"交易对方","item":"商品说明","currency":"CNY","direction":"expense","amount":12.34,"category":"交易分类"}

字段要求：
date 用 xxxx-xx-xx，只到日、不要时分秒，认不出日期的行丢掉；
direction 只填 income 或 expense，按金额正负或「收入/支出」列判断，认不出收支的行丢掉；
amount 填正数，单位元，最多两位小数；
currency 默认 CNY；
type、counterparty、item、category 没有就填空字符串。
''';

class AiConfig {
  final String baseUrl;
  final String apiKey;
  final String model;
  final String prompt;

  const AiConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.prompt,
  });

  factory AiConfig.fromSettings(Map<String, String> s) {
    final prompt = (s[kAiPrompt] ?? '').trim();
    return AiConfig(
      baseUrl: (s[kAiBaseUrl] ?? '').trim(),
      apiKey: (s[kAiApiKey] ?? '').trim(),
      model: (s[kAiModel] ?? '').trim(),
      prompt: prompt.isEmpty ? kDefaultAiPrompt : prompt,
    );
  }

  bool get ready => baseUrl.isNotEmpty && model.isNotEmpty;
}

class AiError implements Exception {
  final String message;

  const AiError(this.message);

  @override
  String toString() => message;
}

String? decodeBillText(List<int> bytes) {
  if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) return null;
  String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    try {
      text = gbk.decode(bytes);
    } on FormatException {
      return null;
    }
  }
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  return text;
}

Future<ParseResult> parseAi(
  List<int> bytes,
  AiConfig cfg, {
  void Function(AiTrace)? onTrace,
}) async {
  if (!cfg.ready) throw const AiError('还没配好 AI，先去「设置 → 模型配置」');

  final text = decodeBillText(bytes);
  if (text == null || text.trim().isEmpty) {
    throw const AiError('AI 只吃文本（CSV / TSV / TXT），表格请先导出成 CSV');
  }

  final trace = await aiExchange(
    cfg,
    text,
    system: cfg.prompt,
    onRequest: onTrace,
  );
  onTrace?.call(trace);
  if (!trace.ok) throw AiError(trace.failure);

  final rows = parseAiRows(trace.reply!);
  return ParseResult(
    sourceName: 'AI',
    txns: rows.txns,
    issues: rows.issues,
    dataRowCount: rows.txns.length + rows.issues.length,
  );
}

const Duration kAiChatTimeout = Duration(seconds: 120);
const Duration kAiProbeTimeout = Duration(seconds: 30);

const int kTraceTextChars = 120;
const int kTraceBodyChars = 400;

class AiTrace {
  final String endpoint;
  final String model;
  final String? system;
  final String user;
  final int userChars;
  final int? status;
  final int? elapsedMs;
  final String body;
  final String? reply;
  final String? error;

  const AiTrace({
    required this.endpoint,
    required this.model,
    this.system,
    required this.user,
    required this.userChars,
    this.status,
    this.elapsedMs,
    this.body = '',
    this.reply,
    this.error,
  });

  bool get ok => reply != null;

  String get failure {
    final e = error;
    if (e == null) return 'AI 没返回内容';
    if (status == null || body.isEmpty) return e;
    return '$e：${_brief(body)}';
  }
}

String _chatUrl(AiConfig cfg) =>
    'POST ${cfg.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';

Future<AiTrace> aiExchange(
  AiConfig cfg,
  String text, {
  String? system,
  Duration timeout = kAiChatTimeout,
  void Function(AiTrace)? onRequest,
}) async {
  final endpoint = _chatUrl(cfg);
  final systemBrief = system == null || system.trim().isEmpty
      ? null
      : _brief(system, kTraceTextChars);

  AiTrace build({int? status, int? elapsedMs, String body = '', String? reply, String? error}) =>
      AiTrace(
        endpoint: endpoint,
        model: cfg.model,
        system: systemBrief,
        user: _brief(text, kTraceTextChars),
        userChars: text.length,
        status: status,
        elapsedMs: elapsedMs,
        body: body,
        reply: reply,
        error: error,
      );

  if (cfg.baseUrl.isEmpty) return build(error: '先填 API 地址');
  if (cfg.model.isEmpty) return build(error: '先填模型名');

  onRequest?.call(build());

  final raw = await _post(cfg, text, timeout, system: system);
  if (raw.status == null) {
    return build(elapsedMs: raw.ms, error: '连不上：${raw.netError}');
  }
  if (raw.status != 200) {
    return build(
      status: raw.status,
      elapsedMs: raw.ms,
      body: _brief(raw.body, kTraceBodyChars),
      error: _httpError(raw.status!),
    );
  }

  final parsed = _extract(raw.body);
  if (parsed.content == null) {
    return build(
      status: raw.status,
      elapsedMs: raw.ms,
      body: _brief(raw.body, kTraceBodyChars),
      error: parsed.failure,
    );
  }
  return build(status: raw.status, elapsedMs: raw.ms, reply: parsed.content);
}

Future<_Raw> _post(
  AiConfig cfg,
  String text,
  Duration timeout, {
  String? system,
}) async {
  final base = cfg.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final messages = <Map<String, String>>[
    if (system != null && system.trim().isNotEmpty)
      {'role': 'system', 'content': system},
    {'role': 'user', 'content': text},
  ];

  final sw = Stopwatch()..start();
  try {
    final resp = await http
        .post(
          Uri.parse('$base/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            if (cfg.apiKey.isNotEmpty) 'Authorization': 'Bearer ${cfg.apiKey}',
          },
          body: jsonEncode({'model': cfg.model, 'messages': messages}),
        )
        .timeout(timeout);
    sw.stop();
    return _Raw(
      status: resp.statusCode,
      ms: sw.elapsedMilliseconds,
      body: utf8.decode(resp.bodyBytes, allowMalformed: true),
    );
  } catch (e) {
    sw.stop();
    return _Raw(status: null, ms: sw.elapsedMilliseconds, body: '', netError: '$e');
  }
}

class _Raw {
  final int? status;
  final int ms;
  final String body;
  final String? netError;

  const _Raw({
    required this.status,
    required this.ms,
    required this.body,
    this.netError,
  });
}

String _httpError(int status) {
  if (status == 401 || status == 403) return '认证失败（HTTP $status），key 不对或没有权限';
  if (status == 404) return '路径不存在（HTTP 404），检查 API 地址或模型名';
  if (status == 429) return '被限流或额度用尽（HTTP 429）';
  if (status >= 500) return '服务端出错（HTTP $status）';
  return 'HTTP $status';
}

({String? content, String? failure}) _extract(String raw) {
  Object? data;
  try {
    data = jsonDecode(raw);
  } on FormatException {
    return (content: null, failure: '返回的不是 JSON');
  }

  final choices = data is Map ? data['choices'] : null;
  if (choices is! List || choices.isEmpty) {
    return (content: null, failure: '返回里没有 choices');
  }
  final first = choices.first;
  final msg = first is Map ? first['message'] : null;
  final content = msg is Map ? msg['content'] : null;
  if (content is! String || content.trim().isEmpty) {
    return (content: null, failure: 'AI 没返回内容');
  }
  return (content: content, failure: null);
}

({List<Txn> txns, List<ParseIssue> issues}) parseAiRows(String content) {
  final rows = _jsonArray(content);
  if (rows == null) throw AiError('AI 返回的不是 JSON 数组：${_brief(content)}');

  final txns = <Txn>[];
  final issues = <ParseIssue>[];

  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    if (row is! Map) {
      issues.add(ParseIssue(i + 1, '不是一条流水'));
      continue;
    }

    final date = _date(row['date']);
    if (date == null) {
      issues.add(ParseIssue(i + 1, '交易时间认不出'));
      continue;
    }

    final direction = _direction(row['direction']);
    if (direction == null) {
      issues.add(ParseIssue(i + 1, '收支认不出'));
      continue;
    }

    final cents = _cents(row['amount']);
    if (cents == null) {
      issues.add(ParseIssue(i + 1, '金额认不出或为 0'));
      continue;
    }

    txns.add(
      Txn(
        date: date,
        currency: _text(row['currency']) ?? 'CNY',
        type: _text(row['type']),
        counterparty: _text(row['counterparty']),
        item: _text(row['item']),
        direction: direction,
        amountCents: cents,
        category: _text(row['category']),
      ),
    );
  }

  return (txns: txns, issues: issues);
}

List<dynamic>? _jsonArray(String content) {
  final start = content.indexOf('[');
  final end = content.lastIndexOf(']');
  if (start < 0 || end <= start) return null;

  Object? v;
  try {
    v = jsonDecode(content.substring(start, end + 1));
  } on FormatException {
    return null;
  }
  return v is List ? v : null;
}

String? _text(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

String? _direction(Object? v) {
  final s = _text(v)?.toLowerCase();
  if (s == null) return null;
  if (s == '-' || s.contains('支') || s.contains('expense')) return 'expense';
  if (s == '+' || s.contains('收') || s.contains('income')) return 'income';
  return null;
}

int? _cents(Object? v) {
  if (v == null) return null;
  final cents = parseAmountCents(v is String ? v : v.toString());
  if (cents == null || cents == 0) return null;
  return cents.abs();
}

String? _date(Object? v) {
  final s = _text(v);
  if (s == null) return null;
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

String _brief(String s, [int max = 200]) {
  final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.length > max ? '${t.substring(0, max)}…' : t;
}
