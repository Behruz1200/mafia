/// Which countries the app runs in and where coin stakes are allowed.
///
/// Values come from server config, not code, so adding a country is a
/// config change. First market: Uzbekistan (`UZ`).
class RegionPolicy {
  const RegionPolicy({
    required this.launchCountries,
    required this.stakeCountries,
    this.minStakeAge = 18,
  });

  /// Countries where the app may be used at all.
  final Set<String> launchCountries;

  /// Countries where staked (coin) matches are allowed. Free matches work
  /// in every launch country.
  final Set<String> stakeCountries;
  final int minStakeAge;

  bool allowsApp(String? country) =>
      country != null && launchCountries.contains(country.toUpperCase());

  bool allowsStakes({required String? country, required bool isAdult}) =>
      isAdult &&
      country != null &&
      stakeCountries.contains(country.toUpperCase());

  factory RegionPolicy.fromJson(Map<String, Object?> j) => RegionPolicy(
    launchCountries: {
      for (final c in j['launchCountries']! as List)
        (c as String).toUpperCase(),
    },
    stakeCountries: {
      for (final c in j['stakeCountries']! as List) (c as String).toUpperCase(),
    },
    minStakeAge: j['minStakeAge'] as int? ?? 18,
  );
}

/// Languages the app ships with. Uzbek is the default.
const supportedLocales = ['uz', 'ru', 'en'];
