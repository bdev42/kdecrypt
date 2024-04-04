import 'dart:convert';
import 'dart:io';
import 'package:kdecrypt/kdecrypt.dart' as kdecrypt;

void main(List<String> arguments) {
  if(arguments.isEmpty) {
    print("Missing argument: <path-to-logfile>");
    return;
  }

  const key = String.fromEnvironment("key");

  var keyBytes = base64.decode(key).length;
  print("key length: $keyBytes (${keyBytes * 8} bits)");

  kdecrypt.runOnLogFile(arguments.first, bool.fromEnvironment("win", defaultValue: Platform.isWindows), key);
}
