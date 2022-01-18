import 'dart:async';

import 'package:dbus/dbus.dart';

/// Roles of nodes.
enum AtSpiRole {
  invalid,
  acceleratorLabel,
  alert,
  animation,
  arrow,
  calendar,
  canvas,
  checkBox,
  checkMenuItem,
  colorChooser,
  columnHeader,
  comboBox,
  dateEditor,
  desktopIcon,
  desktopFrame,
  dial,
  dialog,
  directoryPane,
  drawingArea,
  fileChooser,
  filler,
  focusTraversable,
  fontChooser,
  frame,
  glassPane,
  htmlContainer,
  icon,
  image,
  internalFrame,
  label,
  layeredPane,
  list,
  listItem,
  menu,
  menuBar,
  menuItem,
  optionPane,
  pageTab,
  pageTabList,
  panel,
  passwordText,
  popupMenu,
  progressBar,
  pushButton,
  radioButton,
  radioMenuItem,
  rootPane,
  rowHeader,
  scrollBar,
  scrollPane,
  separator,
  slider,
  spinButton,
  splitPane,
  statusBar,
  table,
  tableCell,
  tableColumnHeader,
  tableRowHeader,
  tearoffMenuItem,
  terminal,
  text,
  toggleButton,
  toolBar,
  toolTip,
  tree,
  treeTable,
  unknown,
  viewport,
  window,
  extended,
  header,
  footer,
  paragraph,
  ruler,
  application,
  autocomplete,
  editbar,
  embedded,
  entry,
  chart,
  caption,
  documentFrame,
  heading,
  page,
  section,
  redundantObject,
  form,
  link,
  inputMethodWindow,
  tableRow,
  treeItem,
  documentSpreadsheet,
  documentPresentation,
  documentText,
  documentWeb,
  documentEmail,
  comment,
  listBox,
  grouping,
  imageMap,
  notification,
  infoBar,
  levelBar,
  titleBar,
  blockQuote,
  audio,
  video,
  definition,
  article,
  landmark,
  log,
  marquee,
  math,
  rating,
  timer,
  static,
  mathFraction,
  mathRoot,
  subscript,
  superscript,
  descriptionList,
  descriptionTerm,
  descriptionValue,
  footnote,
  contentDeletion,
  contentInsertion,
  mark,
  suggestion
}

class AtSpiNodeAddress {
  final String busName;
  final DBusObjectPath path;

  const AtSpiNodeAddress(this.busName, this.path);

  factory AtSpiNodeAddress.fromDBusValue(DBusValue value) {
    value as DBusStruct;
    return AtSpiNodeAddress((value.children[0] as DBusString).value,
        value.children[1] as DBusObjectPath);
  }

  @override
  String toString() => "AtSpiNodeAddress('$busName', $path)";
}

/// A node in the tree.
class AtSpiNode extends DBusRemoteObject {
  final AtSpiRemoteClient remoteClient;
  final List<String> interfaces;

  AtSpiNode(
      {required this.remoteClient,
      required String name,
      required DBusObjectPath path,
      required this.interfaces})
      : super(remoteClient.atSpiBus, name: name, path: path);

  Future<List<AtSpiNode>> getChildren() async {
    var result = await callMethod(
        'org.a11y.atspi.Accessible', 'GetChildren', [],
        replySignature: DBusSignature('a(so)'));
    var childrenAddresses = (result.values[0] as DBusArray)
        .children
        .map((value) => AtSpiNodeAddress.fromDBusValue(value));
    return childrenAddresses
        .map((address) => remoteClient.client._findNode(address))
        .where((node) => node != null)
        .cast<AtSpiNode>()
        .toList();
  }

  Future<AtSpiRole> getRole() async {
    var result = await callMethod('org.a11y.atspi.Accessible', 'GetRole', [],
        replySignature: DBusSignature('u'));
    var roleNumber = (result.values[0] as DBusUint32).value;
    return AtSpiRole.values[roleNumber]; // FIXME: Handle errors
  }

  Future<String> getRoleName() async {
    var result = await callMethod(
        'org.a11y.atspi.Accessible', 'GetRoleName', [],
        replySignature: DBusSignature('s'));
    return (result.values[0] as DBusString).value;
  }

  Future<String> getLocalizedRoleName() async {
    var result = await callMethod(
        'org.a11y.atspi.Accessible', 'GetLocalizedRoleName', [],
        replySignature: DBusSignature('s'));
    return (result.values[0] as DBusString).value;
  }

  Future<List<int>> getState() async {
    var result = await callMethod('org.a11y.atspi.Accessible', 'GetState', [],
        replySignature: DBusSignature('au'));
    return (result.values[0] as DBusArray)
        .children
        .map((value) => (value as DBusUint32).value)
        .toList();
  }

  Future<String> getDescription() async {
    return (await getProperty('org.a11y.atspi.Accessible', 'description',
            signature: DBusSignature('s')) as DBusString)
        .value;
  }

  Future<String> getName() async {
    return (await getProperty('org.a11y.atspi.Accessible', 'name',
            signature: DBusSignature('s')) as DBusString)
        .value;
  }
}

class AtSpiRemoteClient {
  final AtSpiClient client;
  final String name;
  final bool isRegistry;
  StreamSubscription<DBusSignal>? addAccessibleSubscription;
  StreamSubscription<DBusSignal>? removeAccessibleSubscription;
  final nodes = <DBusObjectPath, AtSpiNode>{};

  DBusClient get atSpiBus => client._atSpiBus!;

  AtSpiNode get root =>
      nodes[DBusObjectPath('/org/a11y/atspi/accessible/root')]!;

  AtSpiRemoteClient(this.client, this.name, {this.isRegistry = false});

  Future<void> connect() async {
    if (isRegistry) {
      var path = DBusObjectPath('/org/a11y/atspi/accessible/root');
      nodes[path] = AtSpiNode(
          remoteClient: this,
          name: name,
          path: path,
          interfaces: [
            'org.a11y.atspi.Accessible',
            'org.a11y.atspi.Component'
          ]);
      return;
    }

    DBusMethodSuccessResponse result;
    addAccessibleSubscription = DBusSignalStream(atSpiBus,
            sender: name,
            interface: 'org.a11y.atspi.Cache',
            name: 'AddAccessible',
            signature: DBusSignature('((so)(so)(so)iiassusau)'))
        .listen((signal) {
      _processAddAccessible(signal.values[0] as DBusStruct);
    });
    removeAccessibleSubscription = DBusSignalStream(atSpiBus,
            sender: name,
            interface: 'org.a11y.atspi.Cache',
            name: 'RemoveAccessible',
            signature: DBusSignature('(so)'))
        .listen((signal) {
      _processRemoveAccessible(signal.values[0]);
    });
    try {
      result = await atSpiBus.callMethod(
          destination: name,
          path: DBusObjectPath('/org/a11y/atspi/cache'),
          interface: 'org.a11y.atspi.Cache',
          name: 'GetItems',
          replySignature: DBusSignature('a((so)(so)(so)iiassusau)'));
    } on DBusUnknownObjectException {
      return;
    } on DBusUnknownMethodException {
      return;
    }

    var addedNodes = result.returnValues[0] as DBusArray;
    for (var node in addedNodes.children) {
      _processAddAccessible(node as DBusStruct);
    }
  }

  void _processAddAccessible(DBusStruct node) {
    var values = node.children;
    var address = AtSpiNodeAddress.fromDBusValue(values[0]);
    assert(address.busName == name);
    //var applicationAddress = AtSpiNodeAddress.fromDBusValue(values[1]);
    //var parentAddress = AtSpiNodeAddress.fromDBusValue(values[2]);
    //var ? = (values[3] as DBusInt32).value;
    //var ? = (values[4] as DBusInt32).value;
    var interfaces = (values[5] as DBusArray)
        .children
        .map((value) => (value as DBusString).value)
        .toList();
    //var description = (values[6] as DBusString).value;
    //var roleNumber = (values[7] as DBusUint32).value;
    //var role = AtSpiRole.values[roleNumber]; // FIXME: Handle errors
    //var ? = (values[8] as DBusString).value;
    //var state = (values[9] as DBusArray).children.map((value) => (value as DBusUint32).value).toList();

    nodes[address.path] = AtSpiNode(
        remoteClient: this,
        name: name,
        path: address.path,
        interfaces: interfaces);
  }

  void _processRemoveAccessible(DBusValue value) {
    var address = AtSpiNodeAddress.fromDBusValue(value);
    assert(address.busName == name);
    print('- $address');
  }

  Future<void> close() async {
    await addAccessibleSubscription?.cancel();
    await removeAccessibleSubscription?.cancel();
  }
}

/// A client that connects to AT-SPI.
class AtSpiClient {
  // The session bus.
  final DBusClient? _sessionBus;

  // The bus AT-SPI is running on.
  DBusClient? _atSpiBus;
  String? _registryOwner;

  final _remoteClients = <String, AtSpiRemoteClient>{};

  AtSpiNode get root => _remoteClients[_registryOwner]!.root;

  /// Creates a new AT-SPI client connected to the session D-Bus.
  AtSpiClient({DBusClient? sessionBus}) : _sessionBus = sessionBus;

  /// Connects to AT-SPI.
  /// Must be called before accessing methods and properties.
  Future<void> connect() async {
    DBusClient bus;
    var closeBus = false;
    if (_sessionBus == null) {
      bus = DBusClient.session();
      closeBus = true;
    } else {
      bus = _sessionBus!;
    }

    // Get the address of the AT-SPI bus.
    var result = await bus.callMethod(
        destination: 'org.a11y.Bus',
        path: DBusObjectPath('/org/a11y/bus'),
        interface: 'org.a11y.Bus',
        name: 'GetAddress',
        replySignature: DBusSignature('s'));
    var address = (result.returnValues[0] as DBusString).value;
    if (closeBus) {
      await bus.close();
    }

    _atSpiBus = DBusClient(DBusAddress(address));
    _registryOwner = await _atSpiBus!.getNameOwner('org.a11y.atspi.Registry');
    _atSpiBus!.nameOwnerChanged.listen((event) {
      if (event.name == 'org.a11y.atspi.Registry') {
        _registryOwner = event.newOwner;
      } else if (event.oldOwner == null) {
        _remoteClientAdded(event.name);
      } else if (event.newOwner == null) {
        _remoteClientRemoved(event.name);
      }
    });
    var names = await _atSpiBus!.listNames();
    for (var name in names) {
      _remoteClientAdded(name);
    }
  }

  void _remoteClientAdded(String name) {
    if (!name.startsWith(':')) {
      return;
    }

    if (_remoteClients.containsKey(name)) {
      return;
    }

    var remoteClient =
        AtSpiRemoteClient(this, name, isRegistry: name == _registryOwner);
    _remoteClients[name] = remoteClient;
    remoteClient.connect();
  }

  void _remoteClientRemoved(String name) {
    if (!name.startsWith(':') || name == _registryOwner) {
      return;
    }

    var remoteClient = _remoteClients[name];
    _remoteClients.remove(name);
    if (remoteClient != null) {}
  }

  AtSpiNode? _findNode(AtSpiNodeAddress address) {
    return _remoteClients[address.busName]?.nodes[address.path];
  }

  /// Terminates all active connections. If a client remains unclosed, the Dart process may not terminate.
  Future<void> close() async {
    await _sessionBus?.close();
    for (var client in _remoteClients.values) {
      await client.close();
    }
  }
}
