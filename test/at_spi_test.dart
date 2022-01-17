import 'package:at_spi/at_spi.dart';
import 'package:test/test.dart';

void main() {
  test('client', () async {
    var client = AtSpiClient();
    await client.connect();
    await client.close();
  });
}
