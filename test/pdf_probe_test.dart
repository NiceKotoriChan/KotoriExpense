import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// 探针（不是业务代码）：用 Dart 库把样例 PDF 抽成文本并落盘，供人工比对。
/// `syncfusion_flutter_pdf` 依赖 `package:flutter`，所以必须挂在 `flutter test`
/// 下跑，`dart run` 起不来。
void main() {
  const pdfPath = 'test/samples/招商银行交易流水.pdf';
  const outDir = '.workbuddy/tmp/pdf_probe';

  test('抽出来的文本落盘', () {
    Directory(outDir).createSync(recursive: true);
    final doc = PdfDocument(inputBytes: File(pdfPath).readAsBytesSync());
    try {
      final text = PdfTextExtractor(doc).extractText();
      File('$outDir/syncfusion.txt').writeAsStringSync(text);

      // ignore: avoid_print
      print('RESULT 字符=${text.length} 行=${'\n'.allMatches(text).length + 1} '
          '页数=${doc.pages.count}');

      expect(text.trim(), isNotEmpty);
    } finally {
      doc.dispose();
    }
  });
}
