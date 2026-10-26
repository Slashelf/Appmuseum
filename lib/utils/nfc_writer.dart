
/*import 'dart:convert';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';

Future<void> writeTag(NfcTag tag, String code) async {
  final ndef = Ndef.from(tag);
  if (ndef != null) {
    final record = NdefRecord.createMime(
      'application/myapp',
      utf8.encode(jsonEncode({'type':'myapp','code': code})),
    );
    final message = NdefMessage([record]);
    await ndef.write(message);
  }
}*/
