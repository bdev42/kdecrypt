- Decrypts XMON log files.
- Lets you see what information KdG actually collects.
- Yes you can consider this "anti-spyware".
- **ABSOLUTELY NO "tech-support"** will be provided.

# How to use
- You need [dart](https://dart.dev/get-dart) to run/compile this script. 
- From the project root, compile it* with:
```sh
dart compile exe -Dkey=<key> bin/kdecrypt.dart
```
_Where **`<key>`** is the [encryption key](#conclusion).  
(**Optionally:** you can also provide **`<isWindows>`** if you wish to use it for log files 
generated on a different Platform than your present one with an additional `-Dwin=<isWindows>` argument.)_

Finally simply run the generated executable with the path to your logfile as argument, e.g.
```sh
./bin/kdecrypt ./path/to/logfile.log
```

*alternatively use `dart run`

## What this **IS NOT**
This is **NOT for cheating**, we do not condone cheating in any way!  
This is for fun and **educational purposes only**!  
_If you try to use this for cheating in any shape or form I hope you get caught_ 😝

# For the curious
What follows is a walkthrough of the reverse engineering steps of this project (for the curious).

### **What encryption algorithm does it use?**  
Thanks to KdG generously including the complete source-code in their "release" build(s), 
i shall let their code comments explain:

```dart
/// Service to handle all file related operations
/// This service can handle the encryption of data
/// The encryption of the data happens on a per line basis
/// In order to achieve this, the AES-GCM algorithm is used
/// (see https://en.wikipedia.org/wiki/Galois/Counter_Mode)
class FileService {
    ...
```
_(Found in section `file:///C:/Users/robrepi/Projects/kdg/student-monitoring-tool/exam_monitor/packages/kdg_core/lib/src/services/file_service.dart` 
of `flutter_assets/kernel_blob.bin`)_

> So, KdG has used symetric key encryption. AGAIN!  
> This means the key to decrypt the log file is the  
> one and the same that is used to encrypt it.  
> Therefore the key **has to be** included in xmon one way or another!  

#### **IV and counter**
Besides the encryption key, this algorithm also requires an **initialization vector (IV)**
and it has a **counter** that might be initialized randomly as well!

Luckily reading the source code we can see that the **counter** always starts at 0
and is incremented by 1 on every call to the encrypt function:

```dart
var _counter = 0; //<--

String encrypt(String plainText) {
    assert(
      _isEncrypting == true,
      'Encryption is not initialized for encrypting',
    );
    final bytes = Uint8List.fromList(utf8.encode(plainText));
    final encryptedBytes = _blockCipher.process(bytes);
    _counter++;  //<--
    return base64.encode(encryptedBytes);
}
```
We also know that `Encryption.encrypt` is called from the `writeLine` function (and the prior code comment also explains),
therefore the counter is simply the index of each line in the log file.

To find out what the IV is we simply trace it back to the creation of the encryptor,
this reveals that the IV is always the **original** file name of the log file.
To make sure this original file name is kept safe, it is included in the very first line
of every log file unencrypted:

```dart
final file = await _openFile(logFilePath);
final iv = Encryption.ivFromFileName(
    file: file,
    isWindows: defaultTargetPlatform == TargetPlatform.windows,
);
if (needNewLogFile) {
    // We write the logFilePath as the first line in file
    // because the canvas LMS system will change the filename while uploading
    // However, we need the intact filename in order to properly decrypt the file.
    writeLine(file, iv, encryptLine: false);
}
_createEncryption(file, iv);
```
_We even get a handy `ivFromFileContents` function in the `Encryption` class to recover the IV!_

### **What is the super secret key though?**
#### **Where to look?**
Some more searching reveals that the encryption key originates from this class:
```dart
@module
abstract class RegisterModule {
  @Named('encryptionKey')
  String get encryptionKey => const String.fromEnvironment(
        'encryption_key',
      );
  @Named('shouldEncrypt')
  bool get shouldEncrypt => const bool.fromEnvironment(
    'should_encrypt',
  );
```
> `String.fromEnvironment` is a special dart constructor that uses what are called **environment declarations**,
> these are **not system environment variables**, they are key-value pairs that are defined during **compile time** 
> with the --dart-define flutter command line option (-D or --define for dart).

**Compile time** means they would only be found in the **compiled binaries of XMON**, this makes our job considerably more difficult.

Sadly we cannot just search for the key of the key-value pair _"encryption_key"_ since the compiler simply sets the value of the constant
to the value of the key-value pair, it does not include the name of it.

#### **What to look for?**
If we look at how this **String** becomes the **usable encryption key** (bits), we can see that it is decoded from **base64**:
```dart
KeyParameter get _key => KeyParameter(base64.decode(encryptionKey));
```
So now we know our **encryption key** will be a **base64 encoded string** somewhere in the binary files of XMON.

#### **A needle in the haystack**
From the algorithm we know the key is fixed length and must be 16, 24 or 32 bytes long (128, 192 or 256 bits respectively).

This means the base64 encoded version must match one of these formats:

```
AAAAAAAAAAAAAAAAAAAAAA==
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
```
_(where A is any base64 character)_

A simple regex to match all three is: `([A-Za-z0-9+\/]{22}==|[A-Za-z0-9+\/]{43}=|[A-Za-z0-9+\/]{32})`

Running this regex for either app.so (windows version) or libapp.so (linux bundle):
```sh
grep -aoP '([A-Za-z0-9+\/]{22}==|[A-Za-z0-9+\/]{43}=|[A-Za-z0-9+\/]{32})' <file>
```
yields quite a few matches, but most of them can be recognized as either _.so symbols_ or _complete garbage™_ at first glance.  

All, except for two good-looking candidates with the second one being especially promising given that it is the **only match with the maximum expected length** (256 bit key) in the output, it also looks very much like a base64 string!

1. `adb4292f3ec25074ca70abcd2d5c7251`
2. `56YbOeITDndfnn+ajHBXGwYC6D1k6zvj1fkyNYqJSZk=`

### off by one
The second string above is indeed the encryption key, but when I first tried it it did not work!
After some experimenting I found out the problem was that the counter should start at 1 instead of 0
for the decryption. The exact reason why remains somewhat a mystery, but i suspect it is because:

The `encryption` function is still called in this expression when `writeLine` is called 
with `shouldEncrypt = false` for writing the **original unecrypted name** of the logfile (IV):
```dart
final writeData = encryptLine ?? shouldEncrypt ? _encryption.encrypt(data) : data;
```
**OR** The logfile is somehow reopened after the first line is written and the counter 
initializes at the existing file's current line length.
```dart
int _initializeCounter(File logFile) {
    var counter = 0;
    if (logFile.existsSync()) {
      counter = logFile.readAsLinesSync().length;
    }
    _logger.finer('Initialized counter with value $counter');
    return counter;
}
```

## Conclusion
So in conclusion we know:
- The *encryption algorithm* is **AES-GCM** (symmetric key cryptography!)
- The *encryption key* encoded in base64 is `56YbOeITDndfnn+ajHBXGwYC6D1k6zvj1fkyNYqJSZk=`
- The *initialization vector* is always the **first line of the log file**
- The *counter* starts at 1 for decryption, and is **the index of each line in the log file**
