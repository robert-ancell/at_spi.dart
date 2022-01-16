[![Pub Package](https://img.shields.io/pub/v/at_spi.svg)](https://pub.dev/packages/at_spi)
[![codecov](https://codecov.io/gh/canonical/at_spi.dart/branch/main/graph/badge.svg?token=6P72PJAA7F)](https://codecov.io/gh/canonical/at_spi.dart)

Provides access to the [Assistive Technology Service Provider Interface](https://en.wikipedia.org/wiki/Assistive_Technology_Service_Provider_Interface) (AT-SPI), the standard for accessibility on Linux desktops.

```dart
import 'package:at_spi/at_spi.dart';

var client = AtSpiClient();
await client.connect();
// FIXME
await client.close();
```

## Contributing to at_spi.dart

We welcome contributions! See the [contribution guide](CONTRIBUTING.md) for more details.
