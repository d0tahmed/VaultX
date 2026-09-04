import 'package:sodium/sodium_sumo.dart';

/// Argon2id cost parameters.
///
/// Parameters are written into every envelope header and authenticated as
/// additional data, so an attacker cannot rewrite a stored vault to use cheaper
/// settings and then brute-force it: tampering with the header breaks the tag.
///
/// A device that cannot afford [balanced] may write [interactive] envelopes and
/// still open them later on any device, because the cost lives in the file
/// rather than in the code.
final class KdfProfile {
  const KdfProfile({
    required this.opsLimit,
    required this.memLimitBytes,
    required this.label,
  });

  /// Iteration count (Argon2 time cost).
  final int opsLimit;

  /// Memory cost in bytes (Argon2 memory hardness — the parameter that
  /// actually defeats GPU and ASIC attackers).
  final int memLimitBytes;

  final String label;

  /// 64 MiB. Fallback for low-memory devices only.
  static const interactive = KdfProfile(
    opsLimit: 3,
    memLimitBytes: 64 * 1024 * 1024,
    label: 'interactive',
  );

  /// 256 MiB. Default: comfortably survivable on modern phones, and expensive
  /// enough that large-scale offline guessing is uneconomic.
  static const balanced = KdfProfile(
    opsLimit: 4,
    memLimitBytes: 256 * 1024 * 1024,
    label: 'balanced',
  );

  /// 512 MiB. For users who accept a slower unlock.
  static const hardened = KdfProfile(
    opsLimit: 5,
    memLimitBytes: 512 * 1024 * 1024,
    label: 'hardened',
  );

  static const all = <KdfProfile>[interactive, balanced, hardened];

  /// Rebuilds a profile from values read out of an envelope header.
  factory KdfProfile.fromStored({
    required int opsLimit,
    required int memLimitBytes,
  }) {
    for (final known in all) {
      if (known.opsLimit == opsLimit && known.memLimitBytes == memLimitBytes) {
        return known;
      }
    }
    return KdfProfile(
      opsLimit: opsLimit,
      memLimitBytes: memLimitBytes,
      label: 'custom',
    );
  }

  /// Rejects parameters below libsodium's own floor, so a malformed or hostile
  /// header cannot drive the KDF into a trivially cheap configuration.
  bool isAcceptable(SodiumSumo sodium) {
    final pw = sodium.crypto.pwhash;
    return opsLimit >= pw.opsLimitMin &&
        opsLimit <= pw.opsLimitMax &&
        memLimitBytes >= pw.memLimitMin &&
        memLimitBytes <= pw.memLimitMax &&
        opsLimit >= interactive.opsLimit &&
        memLimitBytes >= interactive.memLimitBytes;
  }

  @override
  String toString() =>
      'KdfProfile($label, ops=$opsLimit, mem=${memLimitBytes ~/ (1024 * 1024)}MiB)';
}
