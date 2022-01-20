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
  bool operator ==(other) =>
      other is AtSpiNodeAddress &&
      other.busName == busName &&
      other.path == path;

  @override
  int get hashCode => busName.hashCode ^ path.hashCode;

  @override
  String toString() => "AtSpiNodeAddress('$busName', $path)";
}

/// A node in the tree.
class AtSpiNode extends DBusRemoteObject {
  final AtSpiClient atSpiClient;
  final List<String> interfaces;

  AtSpiNode(this.atSpiClient, AtSpiNodeAddress address,
      {required this.interfaces})
      : super(atSpiClient._atSpiBus, name: address.busName, path: address.path);

  Future<List<AtSpiNode>> getChildren() async {
    var result = await callMethod(
        'org.a11y.atspi.Accessible', 'GetChildren', [],
        replySignature: DBusSignature('a(so)'));
    var childrenAddresses = (result.values[0] as DBusArray)
        .children
        .map((value) => AtSpiNodeAddress.fromDBusValue(value));
    return childrenAddresses
        .map((address) => atSpiClient._nodes[address])
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

/// A client that connects to AT-SPI.
class AtSpiClient {
  // The session bus.
  final DBusClient? _sessionBus;

  // The bus AT-SPI is running on.
  late final DBusClient _atSpiBus;
  String _registryOwner = '';
  StreamSubscription<DBusSignal>? _addAccessibleSubscription;
  StreamSubscription<DBusSignal>? _removeAccessibleSubscription;
  StreamSubscription<DBusSignal>? _childrenChangedSubscription;
  StreamSubscription<DBusSignal>? _propertyChangeSubscription;
  StreamSubscription<DBusSignal>? _stateChangedSubscription;
  StreamSubscription<DBusNameOwnerChangedEvent>? _nameOwnerChangedSubscription;

  final _nodes = <AtSpiNodeAddress, AtSpiNode>{};

  AtSpiNode get root => _nodes[AtSpiNodeAddress(
      _registryOwner, DBusObjectPath('/org/a11y/atspi/accessible/root'))]!;

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

    _registryOwner =
        await _atSpiBus.getNameOwner('org.a11y.atspi.Registry') ?? '';
    var rootAddress = AtSpiNodeAddress(
        _registryOwner, DBusObjectPath('/org/a11y/atspi/accessible/root'));
    _nodes[rootAddress] = AtSpiNode(this, rootAddress,
        interfaces: ['org.a11y.atspi.Accessible', 'org.a11y.atspi.Component']);

    _addAccessibleSubscription = DBusSignalStream(_atSpiBus,
            interface: 'org.a11y.atspi.Cache',
            name: 'AddAccessible',
            signature: DBusSignature('((so)(so)(so)iiassusau)'))
        .listen((signal) {
      _processAddAccessible(signal.values[0]);
    });
    _removeAccessibleSubscription = DBusSignalStream(_atSpiBus,
            interface: 'org.a11y.atspi.Cache',
            name: 'RemoveAccessible',
            signature: DBusSignature('(so)'))
        .listen((signal) {
      var address = AtSpiNodeAddress.fromDBusValue(signal.values[0]);
      _nodes.remove(address);
    });
    _childrenChangedSubscription = DBusSignalStream(_atSpiBus,
            interface: 'org.a11y.atspi.Event.Object',
            name: 'ChildrenChanged',
            signature: DBusSignature('siiva{sv}'))
        .listen((signal) {
      //print(signal);
    });
    _propertyChangeSubscription = DBusSignalStream(_atSpiBus,
            interface: 'org.a11y.atspi.Event.Object',
            name: 'PropertyChange',
            signature: DBusSignature('siiva{sv}'))
        .listen((signal) {
      print(signal);
    });
    _stateChangedSubscription = DBusSignalStream(_atSpiBus,
            interface: 'org.a11y.atspi.Event.Object',
            name: 'StateChanged',
            signature: DBusSignature('siiva{sv}'))
        .listen((signal) {
      //print(signal);
    });
    _nameOwnerChangedSubscription =
        _atSpiBus.nameOwnerChanged.listen((event) async {
      if (event.name == 'org.a11y.atspi.Registry') {
        _registryOwner = event.newOwner ?? '';
      } else if (event.oldOwner == null) {
        await _busNameAdded(event.name);
      } else if (event.newOwner == null) {
        _busNameRemoved(event.name);
      }
    });
    var names = await _atSpiBus.listNames();
    for (var name in names) {
      if (name != _registryOwner) {
        await _busNameAdded(name);
      }
    }
  }

  Future<void> _busNameAdded(String name) async {
    if (!name.startsWith(':')) {
      return;
    }

    DBusMethodSuccessResponse result;
    try {
      result = await _atSpiBus.callMethod(
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
    for (var value in addedNodes.children) {
      _processAddAccessible(value);
    }
  }

  void _processAddAccessible(DBusValue value) {
    var values = (value as DBusStruct).children;
    var address = AtSpiNodeAddress.fromDBusValue(values[0]);
    var interfaces = (values[5] as DBusArray)
        .children
        .map((value) => (value as DBusString).value)
        .toList();
    _nodes[address] = AtSpiNode(this, address, interfaces: interfaces);
  }

  void _busNameRemoved(String name) {
    if (!name.startsWith(':') || name == _registryOwner) {
      return;
    }

    // Remove all nodes from this address.
    _nodes.removeWhere((key, value) => key.busName == name);
  }

  /// Terminates all active connections. If a client remains unclosed, the Dart process may not terminate.
  Future<void> close() async {
    await _sessionBus?.close();
    await _addAccessibleSubscription?.cancel();
    await _removeAccessibleSubscription?.cancel();
    await _childrenChangedSubscription?.cancel();
    await _propertyChangeSubscription?.cancel();
    await _stateChangedSubscription?.cancel();
    await _nameOwnerChangedSubscription?.cancel();
    await _atSpiBus.close();
  }
}
