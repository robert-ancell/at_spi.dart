import 'dart:async';

import 'package:dbus/dbus.dart';

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

class AtSpiNode {
  final String path;
  final List<String> interfaces;

  AtSpiNode({required this.path, required this.interfaces});
}

class AtSpiRemoteClient {
  final DBusClient bus;
  final String address;

  AtSpiRemoteClient(this.bus, this.address);

  Future<void> connect() async {
    DBusMethodSuccessResponse result;
    try {
      result = await bus.callMethod(
          destination: address,
          path: DBusObjectPath('/org/a11y/atspi/cache'),
          interface: 'org.a11y.atspi.Cache',
          name: 'GetItems',
          replySignature: DBusSignature('a((so)(so)(so)iiassusau)'));
    } on DBusUnknownObjectException {
      return;
    } on DBusUnknownMethodException {
      return;
    }

    var nodes = result.returnValues[0] as DBusArray;
    for (var node in nodes.children) {
      var values = (node as DBusStruct).children;
      var name = values[0] as DBusStruct;
      var namePath = name.children[1] as DBusObjectPath;
      //var application = values[1] as DBusStruct;
      var parent = values[2] as DBusStruct;
      var parentPath = parent.children[1] as DBusObjectPath;
      //var ? = (values[3] as DBusInt32).value;
      //var ? = (values[4] as DBusInt32).value;
      var interfaces = (values[5] as DBusArray)
          .children
          .map((value) => (value as DBusString).value)
          .toList();
      var description = (values[6] as DBusString).value;
      var roleNumber = (values[7] as DBusUint32).value;
      var role = AtSpiRole.values[roleNumber]; // FIXME: Handle errors
      //var ? = (values[8] as DBusString).value;
      //var state = (values[9] as DBusArray).children.map((value) => (value as DBusUint32).value).toList();
      print(
          '$address ${namePath.value} ${parentPath.value} $interfaces $description $role');
    }
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
    print(address);
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
    if (!name.startsWith(':') || name == _registryOwner) {
      return;
    }

    if (_remoteClients.containsKey(name)) {
      return;
    }

    var remoteClient = AtSpiRemoteClient(_atSpiBus!, name);
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

  /// Terminates all active connections. If a client remains unclosed, the Dart process may not terminate.
  Future<void> close() async {
    await _sessionBus?.close();
  }
}
