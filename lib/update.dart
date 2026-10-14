import 'dart:convert';

import 'package:http/http.dart' as http;

const String kUpdateOwner = 'NiceKotoriChan';
const String kUpdateRepo = 'KotoriExpense';
const String kSkippedUpdateKey = 'update.skipped';

String get kLatestReleaseApi =>
    'https://api.github.com/repos/$kUpdateOwner/$kUpdateRepo/releases/latest';

String get kReleasesPage =>
    'https://github.com/$kUpdateOwner/$kUpdateRepo/releases/latest';

class UpdateError implements Exception {
  final String message;

  const UpdateError(this.message);

  @override
  String toString() => message;
}

class ReleaseAsset {
  final String name;
  final String url;
  final int size;

  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
  });

  factory ReleaseAsset.fromJson(Map<String, dynamic> j) => ReleaseAsset(
    name: '${j['name'] ?? ''}',
    url: '${j['browser_download_url'] ?? ''}',
    size: (j['size'] as num?)?.toInt() ?? 0,
  );
}

class ReleaseInfo {
  final String tag;
  final String version;
  final String notes;
  final ReleaseAsset? apk;

  const ReleaseInfo({
    required this.tag,
    required this.version,
    required this.notes,
    required this.apk,
  });
}

List<int> versionParts(String v) => [
  for (final p in v.trim().split('+').first.split('.'))
    int.tryParse(RegExp(r'\d+').stringMatch(p) ?? '') ?? 0,
];

bool isNewerVersion(String latest, String current) {
  final a = versionParts(latest);
  final b = versionParts(current);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

ReleaseInfo parseRelease(String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const UpdateError('GitHub 返回的不是 JSON');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const UpdateError('GitHub 返回的不是一个对象');
  }

  final tag = '${decoded['tag_name'] ?? ''}'.trim();
  if (tag.isEmpty) throw const UpdateError('这个 release 没有 tag');

  final raw = decoded['assets'];
  final apks = <ReleaseAsset>[
    if (raw is List)
      for (final a in raw)
        if (a is Map<String, dynamic>) ReleaseAsset.fromJson(a),
  ].where((a) => a.name.toLowerCase().endsWith('.apk') && a.url.isNotEmpty);

  return ReleaseInfo(
    tag: tag,
    version: tag.startsWith('v') ? tag.substring(1) : tag,
    notes: '${decoded['body'] ?? ''}'.trim(),
    apk: apks.isEmpty
        ? null
        : apks.firstWhere(
            (a) => a.name.toLowerCase().contains(kUpdateRepo.toLowerCase()),
            orElse: () => apks.first,
          ),
  );
}

Future<ReleaseInfo> fetchLatestRelease({http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final r = await c.get(
      Uri.parse(kLatestReleaseApi),
      headers: const {
        'User-Agent': kUpdateRepo,
        'Accept': 'application/vnd.github+json',
      },
    );
    if (r.statusCode != 200) {
      throw UpdateError('GitHub 返回 HTTP ${r.statusCode}');
    }
    return parseRelease(utf8.decode(r.bodyBytes));
  } finally {
    if (client == null) c.close();
  }
}
