/// A tiny seeded random generator (xorshift32).
///
/// We use our own instead of `dart:math` `Random` so a match dealt from a
/// seed deals the same way on every Dart version and platform, which keeps
/// stored matches replayable. Only shifts and xor, so it is exact on the
/// web too.
class SeededRandom {
  SeededRandom(int seed) : _state = _mix(seed);

  int _state;

  static int _mix(int seed) {
    final s = (seed ^ 0x9E3779B9) & 0xFFFFFFFF;
    return s == 0 ? 0x6D2B79F5 : s;
  }

  int _next() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x & 0xFFFFFFFF;
    return _state;
  }

  /// A number from 0 to [max] - 1.
  int nextInt(int max) {
    if (max <= 0) throw ArgumentError.value(max, 'max', 'must be positive');
    return _next() % max;
  }

  /// Shuffles [list] in place (Fisher-Yates).
  void shuffle<T>(List<T> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
  }
}
