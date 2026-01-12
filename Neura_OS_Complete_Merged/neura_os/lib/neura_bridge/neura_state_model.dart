class NeuraStateModel {
  final String mood;
  final double energy;
  final String room;

  const NeuraStateModel({
    required this.mood,
    required this.energy,
    required this.room,
  });

  Map<String, dynamic> toJson() => {
        "type": "SET_STATE",
        "mood": mood,
        "energy": energy,
        "room": room,
      };
}
