enum RoomSongSourceType { remote, localFile }

class RoomSong {
  const RoomSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.url,
    this.durationSeconds,
    this.coverUrl,
    this.addedBy,
    this.sourceType = RoomSongSourceType.remote,
    this.localPath,
  });

  final String id;
  final String title;
  final String artist;
  final String url;
  final int? durationSeconds;
  final String? coverUrl;
  final String? addedBy;
  final RoomSongSourceType sourceType;
  final String? localPath;

  String get formattedDuration {
    if (durationSeconds == null) return '--:--';
    final m = durationSeconds! ~/ 60;
    final s = durationSeconds! % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  RoomSong copyWith({
    String? addedBy,
    RoomSongSourceType? sourceType,
    String? localPath,
  }) =>
      RoomSong(
        id: id,
        title: title,
        artist: artist,
        url: url,
        durationSeconds: durationSeconds,
        coverUrl: coverUrl,
        addedBy: addedBy ?? this.addedBy,
        sourceType: sourceType ?? this.sourceType,
        localPath: localPath ?? this.localPath,
      );
}

const kRoomMusicCatalog = <RoomSong>[
  RoomSong(
    id: 'sh_1',
    title: 'SoundHelix Song 1',
    artist: 'T. Schürger',
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
    durationSeconds: 372,
  ),
  RoomSong(
    id: 'sh_2',
    title: 'SoundHelix Song 2',
    artist: 'T. Schürger',
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
    durationSeconds: 268,
  ),
  RoomSong(
    id: 'sh_3',
    title: 'SoundHelix Song 3',
    artist: 'T. Schürger',
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
    durationSeconds: 340,
  ),
  RoomSong(
    id: 'sh_4',
    title: 'SoundHelix Song 4',
    artist: 'T. Schürger',
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
    durationSeconds: 229,
  ),
  RoomSong(
    id: 'sh_5',
    title: 'SoundHelix Song 5',
    artist: 'T. Schürger',
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3',
    durationSeconds: 313,
  ),
  RoomSong(
    id: 'sh_6',
    title: 'SoundHelix Song 6',
    artist: 'T. Schürger',
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3',
    durationSeconds: 280,
  ),
  RoomSong(
    id: 'sh_7',
    title: 'SoundHelix Song 7',
    artist: 'T. Schürger',
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-7.mp3',
    durationSeconds: 415,
  ),
];
