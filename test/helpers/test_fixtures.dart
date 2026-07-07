const storeItemFixture = <String, dynamic>{
  'id': 'frame-gold',
  'name': 'Gold Frame',
  'name_ar': 'Gold Frame AR',
  'description': 'A premium frame',
  'description_ar': 'Premium frame AR',
  'item_type': 'avatar_frame',
  'price_coins': 1500,
  'price_diamonds': 10,
  'metadata': {'frame_key': 'gold_frame'},
  'is_active': true,
  'sort_order': 3,
  'owned': true,
};

const taskFixture = <String, dynamic>{
  'id': 'daily-room',
  'title': 'Join a room',
  'title_ar': 'Join a room AR',
  'description': 'Join one room',
  'description_ar': 'Join one room AR',
  'task_type': 'daily',
  'requirement_type': 'room_join',
  'requirement_count': 2,
  'reward_type': 'coins',
  'reward_amount': 500,
  'sort_order': 1,
  'progress': 1,
  'completed': false,
  'claimed': false,
  'completed_at': null,
};

const backpackItemFixture = <String, dynamic>{
  'id': 'ownership-1',
  'item_id': 'frame-gold',
  'item_type': 'avatar_frame',
  'equipped': true,
  'acquired_at': '2026-07-01T10:00:00Z',
  'item': storeItemFixture,
};

const roomFixture = <String, dynamic>{
  'id': 'room-1',
  'owner_id': 'owner-1',
  'name': 'Test Room',
  'livekit_room_name': 'livekit-room-1',
  'max_seats': 12,
  'is_private': true,
  'is_locked': true,
  'is_closed': false,
  'room_pin_enabled': true,
  'created_at': '2026-07-01T10:00:00Z',
  'closed_seats': [2, 5],
  'country_code': ' lb ',
  'room_level': 4,
  'room_xp': 1200,
  'xp_today_gift': 30,
  'xp_today_passive': 20,
  'profiles': {'country': 'Lebanon'},
};

const privateMessageFixture = <String, dynamic>{
  'id': 'message-1',
  'conversation_id': 'conversation-1',
  'sender_id': 'sender-1',
  'receiver_id': 'receiver-1',
  'body': 'Hello',
  'created_at': '2026-07-01T10:00:00Z',
  'read_at': '2026-07-01T10:01:00Z',
  'deleted_at': null,
};
