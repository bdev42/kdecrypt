// file:///C:/Users/robrepi/Projects/kdg/student-monitoring-tool/exam_monitor/packages/kdg_encryption/lib/src/kdg_encryption_base.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class Encryption {

  Encryption.initDecrypt({
    required this.encryptionKey,
    required this.initializationVector,
    int? counter,
  }) {
    _counter = counter ?? 0;
    _isEncrypting = false;
  }

  final String encryptionKey;
  final String initializationVector;
  late final bool _isEncrypting;
  var _counter = 0;

  String decrypt(String base64EncryptedBytes) {
    assert(
      _isEncrypting == false,
      'Encryption is not initialized for decrypting',
    );
    final encryptedBytes = base64.decode(base64EncryptedBytes);
    final bytes = _blockCipher.process(encryptedBytes);
    _counter++;
    return utf8.decode(bytes);
  }

  GCMBlockCipher get _blockCipher {
    return GCMBlockCipher(AESEngine())
      ..init(
        _isEncrypting,
        AEADParameters(_key, _macSize, _nonce, _associatedData),
      );
  }

  KeyParameter get _key => KeyParameter(base64.decode(encryptionKey));

  int get _macSize => 128;

  Uint8List get _nonce {
    final iv = Uint8List.fromList(
        utf8.encode(_counter.toString() + initializationVector));
    return SHA256Digest().process(iv);
  }

  Uint8List get _associatedData => Uint8List.fromList(List.empty());

  static String ivFromFileContents({
    required File file,
    required bool isWindows,
  }) => _extractFileName(file.readAsLinesSync().first, isWindows);

  static String _extractFileName(String path, bool isWindows) => path.split(_pathSeparator(isWindows)).last;

  static String _pathSeparator(bool isWindows) => isWindows ? r'\' : '/';

}
