import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  final inputPath = args.isNotEmpty
      ? args[0]
      : 'assets/app_icon_source.png';
  final outputPath = args.length > 1 ? args[1] : 'assets/app_icon.png';

  final bytes = File(inputPath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    stderr.writeln('Could not decode $inputPath');
    exit(1);
  }

  final size = decoded.width < decoded.height ? decoded.width : decoded.height;
  final left = (decoded.width - size) ~/ 2;
  final top = (decoded.height - size) ~/ 2;
  final square = img.copyCrop(decoded, x: left, y: top, width: size, height: size);

  final output = img.Image(width: size, height: size, numChannels: 4);
  final center = size / 2;
  final radius = size / 2;

  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = x + 0.5 - center;
      final dy = y + 0.5 - center;
      final distance = (dx * dx + dy * dy);
      if (distance > radius * radius) {
        output.setPixelRgba(x, y, 0, 0, 0, 0);
        continue;
      }

      final pixel = square.getPixel(x, y);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();
      final a = pixel.a.toInt();

      // Drop near-black corners outside the green disc.
      if (r < 24 && g < 24 && b < 24) {
        output.setPixelRgba(x, y, 0, 0, 0, 0);
        continue;
      }

      output.setPixelRgba(x, y, r, g, b, a);
    }
  }

  File(outputPath).writeAsBytesSync(img.encodePng(output));
  stdout.writeln('Wrote circular icon to $outputPath');
}
