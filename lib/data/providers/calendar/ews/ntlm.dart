import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/digests/md4.dart';

/// Собственная реализация NTLMv2 (Type1/Type2/Type3) — для self-hosted Exchange
/// EWS, где требуется NTLM (Basic отдаёт 401). Пакета под современный http нет,
/// поэтому считаем сообщения сами.

const _signature = [0x4e, 0x54, 0x4c, 0x4d, 0x53, 0x53, 0x50, 0x00]; // "NTLMSSP\0"

// Negotiate flags: Unicode|OEM|RequestTarget|NTLM|AlwaysSign|ExtSessionSecurity|128|56
const int _flags = 0xa0088207;

/// Type 1 (Negotiate) → base64.
String createType1() {
  final b = BytesBuilder();
  b.add(_signature);
  b.add(_le32(1));
  b.add(_le32(_flags));
  b.add(_le16(0)); b.add(_le16(0)); b.add(_le32(32)); // domain (пусто)
  b.add(_le16(0)); b.add(_le16(0)); b.add(_le32(32)); // workstation (пусто)
  return base64.encode(b.toBytes());
}

class Type2 {
  Type2(this.challenge, this.targetInfo);
  final Uint8List challenge; // 8 байт
  final Uint8List targetInfo;
}

/// Разбор Type 2 (Challenge) из base64.
Type2 parseType2(String b64) {
  final d = base64.decode(b64);
  final challenge = Uint8List.sublistView(d, 24, 32);
  // TargetInfoFields @ offset 40: len(2), maxlen(2), offset(4)
  final tiLen = d[40] | (d[41] << 8);
  final tiOff = d[44] | (d[45] << 8) | (d[46] << 16) | (d[47] << 24);
  final targetInfo = Uint8List.sublistView(d, tiOff, tiOff + tiLen);
  return Type2(challenge, targetInfo);
}

/// Type 3 (Authenticate) → base64. NTLMv2.
String createType3({
  required String user,
  required String password,
  required String domain,
  required String workstation,
  required Type2 type2,
}) {
  final ntHash = _md4(_utf16le(password));
  final responseKeyNT =
      _hmacMd5(ntHash, _utf16le(user.toUpperCase() + domain));

  final clientChallenge = _random(8);
  final timestamp = _fileTime();

  // temp = 0x01 0x01 00*6 + timestamp(8) + clientChallenge(8) + 00*4 + targetInfo + 00*4
  final temp = BytesBuilder()
    ..add([0x01, 0x01, 0, 0, 0, 0, 0, 0])
    ..add(timestamp)
    ..add(clientChallenge)
    ..add([0, 0, 0, 0])
    ..add(type2.targetInfo)
    ..add([0, 0, 0, 0]);
  final tempBytes = temp.toBytes();

  final ntProof = _hmacMd5(
      responseKeyNT, _concat(type2.challenge, tempBytes));
  final ntResponse = _concat(ntProof, tempBytes);

  // LMv2 response
  final lmProof = _hmacMd5(
      responseKeyNT, _concat(type2.challenge, clientChallenge));
  final lmResponse = _concat(lmProof, clientChallenge);

  final domainBytes = _utf16le(domain);
  final userBytes = _utf16le(user);
  final wsBytes = _utf16le(workstation);

  // payload порядок: domain, user, ws, lm, nt, sessionKey(пусто)
  // Заголовок Type3 без Version/MIC = 64 байта (8 sig +4 type +6×8 security
  // buffers +4 flags). Раньше стояло 72 → сдвиг payload на 8 байт → сервер
  // читал поля не с того места → 401.
  var offset = 64;
  int o(int len) {
    final cur = offset;
    offset += len;
    return cur;
  }

  final domainOff = o(domainBytes.length);
  final userOff = o(userBytes.length);
  final wsOff = o(wsBytes.length);
  final lmOff = o(lmResponse.length);
  final ntOff = o(ntResponse.length);
  final skOff = o(0);

  final b = BytesBuilder();
  b.add(_signature);
  b.add(_le32(3));
  b.add(_field(lmResponse.length, lmOff));
  b.add(_field(ntResponse.length, ntOff));
  b.add(_field(domainBytes.length, domainOff));
  b.add(_field(userBytes.length, userOff));
  b.add(_field(wsBytes.length, wsOff));
  b.add(_field(0, skOff));
  b.add(_le32(_flags));
  // payload
  b.add(domainBytes);
  b.add(userBytes);
  b.add(wsBytes);
  b.add(lmResponse);
  b.add(ntResponse);
  return base64.encode(b.toBytes());
}

// ───────── helpers ─────────

List<int> _le16(int v) => [v & 0xff, (v >> 8) & 0xff];
List<int> _le32(int v) =>
    [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];

/// Поле security buffer: len, maxlen, offset.
List<int> _field(int len, int off) => [..._le16(len), ..._le16(len), ..._le32(off)];

Uint8List _utf16le(String s) {
  final out = Uint8List(s.length * 2);
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    out[i * 2] = c & 0xff;
    out[i * 2 + 1] = (c >> 8) & 0xff;
  }
  return out;
}

Uint8List _md4(List<int> data) {
  final d = MD4Digest();
  d.update(Uint8List.fromList(data), 0, data.length);
  final out = Uint8List(16);
  d.doFinal(out, 0);
  return out;
}

Uint8List _hmacMd5(List<int> key, List<int> data) =>
    Uint8List.fromList(Hmac(md5, key).convert(data).bytes);

Uint8List _concat(List<int> a, List<int> b) =>
    Uint8List.fromList([...a, ...b]);

final _rng = Random.secure();
Uint8List _random(int n) =>
    Uint8List.fromList(List.generate(n, (_) => _rng.nextInt(256)));

/// Windows FILETIME (100-нс с 1601) как 8 байт LE.
Uint8List _fileTime() {
  final ms = DateTime.now().toUtc().millisecondsSinceEpoch;
  final ft = (ms + 11644473600000) * 10000; // в 100-нс интервалах
  final out = Uint8List(8);
  var v = ft;
  for (var i = 0; i < 8; i++) {
    out[i] = v & 0xff;
    v = v >> 8;
  }
  return out;
}
