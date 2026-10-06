import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('las fotos de la pantalla principal están en la aplicación', () async {
    for (final name in [
      'actividades',
      'sugerencias',
      'monumentos',
      'servicios',
    ]) {
      final data = await rootBundle.load('assets/home/$name.jpg');
      expect(data.lengthInBytes, greaterThan(10000), reason: name);
      // Cabecera de un archivo JPEG.
      expect(data.getUint8(0), 0xFF, reason: name);
      expect(data.getUint8(1), 0xD8, reason: name);
    }
  });
}
