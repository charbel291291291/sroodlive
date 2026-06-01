import 'package:flutter/material.dart';

import '../models/room.dart';
import '../services/rooms_service.dart';

class RoomsDebugScreen extends StatefulWidget {
  const RoomsDebugScreen({super.key});

  @override
  State<RoomsDebugScreen> createState() => _RoomsDebugScreenState();
}

class _RoomsDebugScreenState extends State<RoomsDebugScreen> {
  final RoomsService _roomsService = const RoomsService();

  List<Room> _rooms = [];
  bool _loading = false;
  String _message = 'Ready';

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _message = 'Loading...';
    });

    try {
      await action();
    } catch (error) {
      setState(() {
        _message = 'Error: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadRooms() async {
    final rooms = await _roomsService.getRooms();

    setState(() {
      _rooms = rooms;
      _message = 'Loaded ${rooms.length} rooms';
    });
  }

  Future<void> _createRoom() async {
    final room = await _roomsService.createRoom(
      name: 'Test SrOOd Room',
      description: 'Temporary test room',
      language: 'ar',
      maxSeats: 12,
    );

    setState(() {
      _message = 'Created room: ${room.name}';
    });

    await _loadRooms();
  }

  Future<void> _joinFirstRoom() async {
    if (_rooms.isEmpty) {
      setState(() {
        _message = 'No rooms found. Create one first.';
      });
      return;
    }

    await _roomsService.joinRoom(_rooms.first.id);

    setState(() {
      _message = 'Joined room: ${_rooms.first.name}';
    });
  }

  Future<void> _leaveFirstRoom() async {
    if (_rooms.isEmpty) {
      setState(() {
        _message = 'No rooms found.';
      });
      return;
    }

    await _roomsService.leaveRoom(_rooms.first.id);

    setState(() {
      _message = 'Left room: ${_rooms.first.name}';
    });
  }

  @override
  void initState() {
    super.initState();
    _run(_loadRooms);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rooms Debug'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(_message),
            const SizedBox(height: 16),
            if (_loading) const LinearProgressIndicator(),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _loading ? null : () => _run(_loadRooms),
                  child: const Text('Load rooms'),
                ),
                ElevatedButton(
                  onPressed: _loading ? null : () => _run(_createRoom),
                  child: const Text('Create test room'),
                ),
                ElevatedButton(
                  onPressed: _loading ? null : () => _run(_joinFirstRoom),
                  child: const Text('Join first room'),
                ),
                ElevatedButton(
                  onPressed: _loading ? null : () => _run(_leaveFirstRoom),
                  child: const Text('Leave first room'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: _rooms.length,
                separatorBuilder: (_, index) => const Divider(),
                itemBuilder: (context, index) {
                  final room = _rooms[index];

                  return ListTile(
                    title: Text(room.name),
                    subtitle: Text(
                      [
                        if (room.description != null) room.description!,
                        'Language: ${room.language}',
                        'Seats: ${room.maxSeats}',
                      ].join('\n'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
