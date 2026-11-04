// lib/avatar/viseme/sapi_viseme_map.dart
//
// Maps the 22 SAPI SPVISEMES ids (the Disney-derived set also used by Azure
// speech viseme events) onto Neura's compact viseme set plus a mouth-open
// amount. Unlike NeuraVisemeEngine's text guesses, these ids come from the
// speech engine's own phoneme stream, timed to audio playback.

import '../../core/neura_events_extra.dart';

class NeuraSapiVisemes {
  NeuraSapiVisemes._();

  /// Highest valid SPVISEMES id (SP_VISEME_21: p b m).
  static const int maxId = 21;

  // Index = SPVISEMES id. Phonemes per id follow the SAPI documentation.
  static const List<NeuraViseme> _visemes = <NeuraViseme>[
    NeuraViseme.rest, //  0 silence
    NeuraViseme.AI, //    1 ae ax ah
    NeuraViseme.AI, //    2 aa
    NeuraViseme.O, //     3 ao
    NeuraViseme.E, //     4 ey eh uh
    NeuraViseme.R, //     5 er
    NeuraViseme.I, //     6 y iy ih ix
    NeuraViseme.WQ, //    7 w uw
    NeuraViseme.O, //     8 ow
    NeuraViseme.AI, //    9 aw
    NeuraViseme.O, //    10 oy
    NeuraViseme.AI, //   11 ay
    NeuraViseme.AI, //   12 h
    NeuraViseme.R, //    13 r
    NeuraViseme.L, //    14 l
    NeuraViseme.SZN, //  15 s z
    NeuraViseme.CHJSH, //16 sh ch jh zh
    NeuraViseme.TH, //   17 th dh
    NeuraViseme.FV, //   18 f v
    NeuraViseme.SZN, //  19 d t n
    NeuraViseme.KG, //   20 k g ng
    NeuraViseme.MBP, //  21 p b m
  ];

  static const List<double> _mouthOpen = <double>[
    0.00, //  0 silence
    0.50, //  1 ae ax ah
    0.60, //  2 aa
    0.50, //  3 ao
    0.35, //  4 ey eh uh
    0.30, //  5 er
    0.25, //  6 y iy ih ix
    0.20, //  7 w uw
    0.45, //  8 ow
    0.55, //  9 aw
    0.45, // 10 oy
    0.55, // 11 ay
    0.30, // 12 h
    0.25, // 13 r
    0.30, // 14 l
    0.15, // 15 s z
    0.20, // 16 sh ch jh zh
    0.25, // 17 th dh
    0.15, // 18 f v
    0.20, // 19 d t n
    0.25, // 20 k g ng
    0.00, // 21 p b m (lips closed)
  ];

  static bool isValid(int id) => id >= 0 && id <= maxId;

  /// Neura viseme for a SPVISEMES id; unknown ids rest.
  static NeuraViseme viseme(int id) =>
      isValid(id) ? _visemes[id] : NeuraViseme.rest;

  /// Mouth-open amount 0..1 for a SPVISEMES id; unknown ids close.
  static double mouthOpen(int id) => isValid(id) ? _mouthOpen[id] : 0.0;
}
