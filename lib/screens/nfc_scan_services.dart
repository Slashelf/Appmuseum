import 'dart:convert';
import 'package:nfc_manager/nfc_manager.dart';
import '../repositories/data_repository.dart';
import '../models/object_model.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';
class NfcService {
  static bool scanned = false;

  static void startNfcSession({
    required Function(ObjectModel obj) onObjectFound,
    required Function(String message) onMessage,
    String iosAlert = 'NFC',
  }) {
    NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443},
      onDiscovered: (tag) async {
        if (scanned) return;
        scanned = true;
      

        try {
          final ndef = Ndef.from(tag);
          if (ndef == null) {
            onMessage("nfcNoNdef");
            scanned = false;
            return;
          }

          final ndefMessage = await ndef.read();

          if (ndefMessage != null && ndefMessage.records.isNotEmpty) {
            final payloadBytes = ndefMessage.records.first.payload;
            final statusByte = payloadBytes[0];
            final languageCodeLength = statusByte & 0x3F;
            final textBytes = payloadBytes.sublist(1 + languageCodeLength);
            final code = utf8.decode(textBytes);

            final obj = await DataRepository.findByCode(code);
            if (obj != null) {
              onObjectFound(obj);
            } else {
              onMessage("nfcUnknown");
            }
          } else {
            onMessage("nfcNoRecords");
          }
        } catch (e) {
          onMessage("nfcReadError:$e");
        }

        scanned = false;
      },
      alertMessageIos: iosAlert,
    );
  }

  static void stopNfcSession() {
    NfcManager.instance.stopSession();
  }
}
