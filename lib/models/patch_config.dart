import 'synth_param.dart';

/// A complete sound: name + one value per [SynthParam]. Immutable; serialises
/// to the JSON preset files.
class PatchConfig {
  PatchConfig({required this.name, Map<SynthParam, double>? values})
      : values = {
          for (final p in SynthParam.values) p: p.clamp(values?[p] ?? p.def),
        };

  final String name;
  final Map<SynthParam, double> values;

  double operator [](SynthParam p) => values[p]!;

  PatchConfig copyWith({String? name, SynthParam? param, double? value}) =>
      PatchConfig(
        name: name ?? this.name,
        values: {
          ...values,
          if (param != null && value != null) param: value,
        },
      );

  Map<String, dynamic> toJson() => {
        'version': 1,
        'name': name,
        'params': {for (final e in values.entries) e.key.key: e.value},
      };

  factory PatchConfig.fromJson(Map<String, dynamic> json) {
    final raw = Map<String, dynamic>.from((json['params'] as Map?) ?? const {});
    return PatchConfig(
      name: (json['name'] as String?) ?? 'Untitled',
      values: {
        for (final p in SynthParam.values)
          if (raw[p.key] is num) p: (raw[p.key] as num).toDouble(),
      },
    );
  }
}
