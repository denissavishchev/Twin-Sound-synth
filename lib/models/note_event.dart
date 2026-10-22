const List<String> kNoteNames = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
];

String noteName(int midi) => '${kNoteNames[midi % 12]}${midi ~/ 12 - 1}';
bool isBlackKey(int midi) => const {1, 3, 6, 8, 10}.contains(midi % 12);

/// Engine key of a note played from keyboard [zone]: the two keyboards use
/// different keys even for the same pitch, so they never cut each other off.
int engineKey(int zone, int pitch) => zone * 128 + pitch.clamp(0, 127);
