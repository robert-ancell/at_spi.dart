import 'dart:io';

import 'package:at_spi/at_spi.dart';
import 'package:dbus/dbus.dart';
import 'package:test/test.dart';

class MockAtSpiBusObject extends DBusObject {
  final DBusAddress atSpiBusAddress;

  MockAtSpiBusObject(this.atSpiBusAddress)
      : super(DBusObjectPath('/org/a11y/bus'));

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != 'org.a11y.Bus') {
      return DBusMethodErrorResponse.unknownInterface();
    }

    if (methodCall.name == 'GetAddress') {
      return DBusMethodSuccessResponse([DBusString(atSpiBusAddress.value)]);
    } else {
      return DBusMethodErrorResponse.unknownMethod();
    }
  }
}

class MockAtSpiBusServer extends DBusClient {
  final MockAtSpiBusObject busObject;

  MockAtSpiBusServer(DBusAddress clientAddress, DBusAddress atSpiBusAddress)
      : busObject = MockAtSpiBusObject(atSpiBusAddress),
        super(clientAddress);

  Future<void> start() async {
    await requestName('org.a11y.Bus');
    await registerObject(busObject);
  }
}

class MockAtSpiRegistryServer extends DBusClient {
  MockAtSpiRegistryServer(DBusAddress clientAddress) : super(clientAddress);

  Future<void> start() async {
    await requestName('org.a11y.atspi.Registry');
  }
}

void main() {
  test('client', () async {
    var atSpiBus = DBusServer();
    addTearDown(() async => await atSpiBus.close());
    var atSpiClientAddress = await atSpiBus
        .listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var registryServer = MockAtSpiRegistryServer(atSpiClientAddress);
    addTearDown(() async => await registryServer.close());
    await registryServer.start();

    var sessionBus = DBusServer();
    addTearDown(() async => await sessionBus.close());
    var sessionClientAddress = await sessionBus
        .listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var busServer =
        MockAtSpiBusServer(sessionClientAddress, atSpiClientAddress);
    addTearDown(() async => await busServer.close());
    await busServer.start();

    var client = AtSpiClient(sessionBus: DBusClient(sessionClientAddress));
    await client.connect();
    await client.close();
  });
}
