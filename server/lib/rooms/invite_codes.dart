import 'dart:math';

/// Five characters, no look-alikes (0/O, 1/I/L), so codes survive being
/// read aloud or typed from a screenshot: 31^5, about 28 million codes.
const inviteAlphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
const inviteLength = 5;

String newInviteCode(Random random) => String.fromCharCodes([
  for (var i = 0; i < inviteLength; i++)
    inviteAlphabet.codeUnitAt(random.nextInt(inviteAlphabet.length)),
]);

/// Players type codes in any case and sometimes with spaces.
String normalizeInviteCode(String raw) =>
    raw.replaceAll(RegExp(r'\s|-'), '').toUpperCase();
