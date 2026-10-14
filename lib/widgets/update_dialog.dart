import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';

import '../update.dart';

Future<bool?> showUpdateDialog(
  BuildContext context, {
  required ReleaseInfo release,
  required String current,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _UpdateDialog(release: release, current: current),
);

class _UpdateDialog extends StatefulWidget {
  final ReleaseInfo release;
  final String current;

  const _UpdateDialog({required this.release, required this.current});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  OtaUpdate? _ota;
  StreamSubscription<OtaEvent>? _sub;
  int _percent = 0;
  bool _downloading = false;
  bool _installing = false;
  String? _error;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final apk = widget.release.apk;
    if (apk == null) return;

    setState(() {
      _error = null;
      _percent = 0;
      _downloading = true;
      _installing = false;
    });

    final ota = OtaUpdate();
    _ota = ota;
    try {
      _sub = ota
          .execute(apk.url, destinationFilename: apk.name)
          .listen(_onEvent, onError: _onError);
    } catch (e) {
      _onError(e);
    }
  }

  void _onEvent(OtaEvent e) {
    if (!mounted) return;
    final status = e.status;

    if (status == OtaStatus.DOWNLOADING) {
      setState(() => _percent = int.tryParse(e.value ?? '') ?? _percent);
    } else if (status == OtaStatus.INSTALLING) {
      setState(() {
        _downloading = false;
        _installing = true;
      });
    } else if (status == OtaStatus.INSTALLATION_DONE) {
      setState(() => _installing = false);
    } else if (status == OtaStatus.CANCELED) {
      setState(() {
        _downloading = false;
        _installing = false;
        _error = null;
      });
    } else if (status == OtaStatus.ALREADY_RUNNING_ERROR) {
      setState(() {
        _downloading = false;
        _error = '上一次下载还没结束';
      });
    } else if (status == OtaStatus.PERMISSION_NOT_GRANTED_ERROR) {
      setState(() {
        _downloading = false;
        _error = '没有安装权限：去系统设置里允许本应用「安装未知应用」，再试一次';
      });
    } else if (status == OtaStatus.DOWNLOAD_ERROR ||
        status == OtaStatus.CHECKSUM_ERROR ||
        status == OtaStatus.INSTALLATION_ERROR ||
        status == OtaStatus.INTERNAL_ERROR) {
      setState(() {
        _downloading = false;
        _installing = false;
        _error = e.value ?? '更新失败';
      });
    }
  }

  void _onError(Object e) {
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _installing = false;
      _error = '$e';
    });
  }

  Widget _body(ColorScheme cs) {
    final notes = widget.release.notes;
    final error = _error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('当前 v${widget.current}'),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          SelectableText(notes),
        ],
        if (_downloading) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: _percent <= 0 ? null : _percent / 100,
          ),
          const SizedBox(height: 6),
          Text('正在下载 $_percent%'),
        ],
        if (_installing) ...[
          const SizedBox(height: 16),
          const Text('已交给系统安装器，装完请重新打开'),
        ],
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(error, style: TextStyle(color: cs.error)),
        ],
      ],
    );
  }

  List<Widget> _actions(BuildContext context) {
    if (_downloading) {
      return [
        TextButton(
          onPressed: () => _ota?.cancel(),
          child: const Text('取消下载'),
        ),
      ];
    }
    if (_installing) {
      return [
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('完成'),
        ),
      ];
    }
    if (_error != null) {
      return [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton(onPressed: _start, child: const Text('重试')),
      ];
    }
    return [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('稍后'),
      ),
      FilledButton(onPressed: _start, child: const Text('下载并安装')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('发现新版本 v${widget.release.version}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(child: _body(cs)),
      ),
      actions: _actions(context),
    );
  }
}
