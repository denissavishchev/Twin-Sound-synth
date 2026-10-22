// Raw dart:ffi bindings to src/synth.cpp. The shared library is compiled by
// hook/build.dart and bundled automatically (Dart native assets); the asset id
// of these @Native functions is this file's URI.
import 'dart:ffi';

@Native<Int32 Function()>(symbol: 'synth_start')
external int synthStart();

@Native<Void Function()>(symbol: 'synth_stop')
external void synthStop();

@Native<Int32 Function(Int32)>(symbol: 'synth_init_offline')
external int synthInitOffline(int sampleRate);

@Native<Void Function(Pointer<Float>, Int32)>(symbol: 'synth_render', isLeaf: true)
external void synthRender(Pointer<Float> interleaved, int frames);

@Native<Void Function()>(symbol: 'synth_destroy')
external void synthDestroy();

// Leaf calls skip the Dart↔native state transition: they are the fast path for
// touch events and knob turns.
@Native<Void Function(Int32, Float)>(symbol: 'synth_note_on', isLeaf: true)
external void synthNoteOn(int note, double velocity);

@Native<Void Function(Int32)>(symbol: 'synth_note_off', isLeaf: true)
external void synthNoteOff(int note);

@Native<Void Function()>(symbol: 'synth_all_notes_off', isLeaf: true)
external void synthAllNotesOff();

@Native<Void Function(Int32, Int32, Float)>(symbol: 'synth_set_param', isLeaf: true)
external void synthSetParam(int zone, int id, double value);

@Native<Float Function(Int32)>(symbol: 'synth_get_peak', isLeaf: true)
external double synthGetPeak(int zone);

@Native<Int32 Function()>(symbol: 'synth_active_voices', isLeaf: true)
external int synthActiveVoices();

@Native<Int32 Function()>(symbol: 'synth_sample_rate', isLeaf: true)
external int synthSampleRate();

@Native<Void Function(Pointer<Float>, Int32)>(symbol: 'synth_get_scope', isLeaf: true)
external void synthGetScope(Pointer<Float> out, int n);
