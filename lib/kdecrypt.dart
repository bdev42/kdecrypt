import 'dart:io';
import 'package:kdecrypt/kdg_encryption_base.dart' as kdg;

bool runOnLogFile(String fileName, bool isWindows, String encryptionKey) {
  var logFile = File(fileName);

  if(!logFile.existsSync()) {
    print("File '$fileName' not found");
    return false;
  }
  print("Processing $fileName...");

  var iv = kdg.Encryption.ivFromFileContents(file: logFile, isWindows: isWindows);

  print("KEY: '$encryptionKey' \nIV: '$iv'");

  var logLines = logFile.readAsLinesSync();
  var counter = 1; // The first line is always the original filename (= IV) unencrypted, but the counter is still incremented so we start at 1

  print("Counter initialized at: $counter");
  print("----------------------------------------------------------------------------\n\n");

  var decryptor = kdg.Encryption.initDecrypt(encryptionKey: encryptionKey, initializationVector: iv, counter: counter);

  for(final(i, l) in logLines.indexed) {
    if(i == 0) continue;
    print("$i> ${decryptor.decrypt(l)}");
  }

  return false;
}
