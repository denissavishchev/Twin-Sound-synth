import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Compiles the C++ DSP engine (src/synth.cpp + miniaudio) for whatever
/// platform Flutter is building: Android, iOS, macOS, Windows or Linux.
void main(List<String> args) async {
  await build(args, (input, output) async {
    final os = input.config.code.targetOS;
    final builder = CBuilder.library(
      name: 'ai_synth',
      // Must match the library that declares the @Native functions.
      assetName: 'core/audio/synth_bindings.dart',
      sources: ['src/synth.cpp', 'src/miniaudio_impl.cpp'],
      includes: ['src'],
      language: Language.cpp,
      std: 'c++17',
      // Android: link the C++ runtime statically, otherwise libai_synth.so needs
      // libc++_shared.so, which Flutter does not bundle.
      cppLinkStdLib: os == OS.android ? 'c++_static' : null,
      optimizationLevel: OptimizationLevel.o3,
      frameworks: switch (os) {
        OS.macOS => ['CoreFoundation', 'CoreAudio', 'AudioToolbox'],
        OS.iOS => ['CoreFoundation', 'CoreAudio', 'AudioToolbox', 'AVFoundation'],
        _ => const [],
      },
      libraries: switch (os) {
        OS.linux => ['m', 'dl', 'pthread'],
        OS.android => ['log', 'OpenSLES', 'm', 'dl'],
        _ => const [],
      },
    );
    await builder.run(input: input, output: output);
  });
}
