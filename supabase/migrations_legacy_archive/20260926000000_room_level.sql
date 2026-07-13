-- Feature: Room Level
--
-- Adds a room_level column so the UI can render progressively more luxurious
-- seat visuals as a room earns a higher level. Starts at 1 for all rooms.
-- Level can be set by admins or incremented by future automation.

alter table public.rooms
  add column if not exists room_level smallint not null default 1
    check (room_level >= 1 and room_level <= 99);
