// Conditional facade so Web builds don't choke on dart:io.

export 'neura_bridge_stub.dart'
    if (dart.library.io) 'neura_bridge_io.dart';
