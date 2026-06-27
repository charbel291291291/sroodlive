import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../profile/screens/user_profile_screen.dart';
import '../../rooms/models/room.dart';
import '../../rooms/screens/room_details_screen.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    required this.isArabic,
    this.countryCode,
    super.key,
  });

  final bool isArabic;
  final String? countryCode;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchResult {
  final String id;
  final String type;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final bool? isLive;
  final Room? room;

  const _SearchResult({
    required this.id,
    required this.type,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.isLive,
    this.room,
  });
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  late final TabController _tabController;
  Timer? _debounce;
  bool _isSearching = false;
  String _query = '';
  List<_SearchResult> _results = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _tabController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    setState(() => _query = q);
    if (q.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 380),
      () => _search(q.trim()),
    );
  }

  Future<void> _search(String q) async {
    setState(() => _isSearching = true);
    try {
      final [usersRaw, roomsRaw] = await Future.wait<dynamic>([
        SupabaseService.requiredClient
            .from('profiles')
            .select('id, display_name, username, avatar_url, bio, public_user_id')
            .or('display_name.ilike.%$q%,username.ilike.%$q%,public_user_id.ilike.%$q%')
            .limit(20),
        () {
          var rq = SupabaseService.requiredClient
              .from('rooms')
              .select(
                'id, owner_id, name, description, language, livekit_room_name, max_seats, is_private, is_locked, is_closed, is_live, cover_url, created_at, country_code',
              )
              .ilike('name', '%$q%')
              .eq('is_closed', false);
          final cc = widget.countryCode?.trim().toUpperCase();
          if (cc != null && cc.isNotEmpty) {
            rq = rq.eq('country_code', cc);
          }
          return rq.limit(20);
        }(),
      ]);

      final users = (usersRaw as List).map(
        (row) => _SearchResult(
          id: row['id'] as String,
          type: 'user',
          title: row['display_name'] as String? ??
              row['username'] as String? ??
              'Unknown',
          subtitle: row['public_user_id'] as String? ?? row['bio'] as String?,
          imageUrl: row['avatar_url'] as String?,
        ),
      );

      final rooms = (roomsRaw as List).map((row) {
        final r = row as Map<String, dynamic>;
        return _SearchResult(
          id: r['id'] as String,
          type: 'room',
          title: r['name'] as String? ?? 'Room',
          subtitle: r['description'] as String?,
          imageUrl: r['cover_url'] as String?,
          isLive: r['is_live'] as bool?,
          room: Room.fromJson(r),
        );
      });

      if (!mounted) return;
      setState(() {
        _results = [...users, ...rooms];
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSearching = false);
    }
  }

  List<_SearchResult> get _userResults =>
      _results.where((r) => r.type == 'user').toList();
  List<_SearchResult> get _roomResults =>
      _results.where((r) => r.type == 'room').toList();

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;

    return Scaffold(
      backgroundColor: const Color(0xFF08060F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildSearchBar(isArabic),
              if (_query.length >= 2) _buildTabBar(isArabic),
              Expanded(
                child: _query.length < 2
                    ? _buildEmptyState(isArabic)
                    : _isSearching
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF8B26D9),
                        ),
                      )
                    : _results.isEmpty
                    ? _buildNoResults(isArabic)
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildResultsList(_userResults, isArabic),
                          _buildResultsList(_roomResults, isArabic),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isArabic) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              isArabic ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
              color: Colors.white,
            ),
          ),
          Expanded(
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF160B24),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF4A3470)),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _focusNode,
                textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
                onChanged: _onQueryChanged,
                decoration: InputDecoration(
                  hintText: isArabic
                      ? 'ابحث عن أشخاص أو غرف...'
                      : 'Search people or rooms...',
                  hintStyle: const TextStyle(
                    color: Color(0xFF6E5A8A),
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF9E91B8),
                  ),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Color(0xFF9E91B8),
                            size: 18,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            _onQueryChanged('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(bool isArabic) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF160B24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: const Color(0xFF3A174F),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFF8B26D9)),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF9E91B8),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        tabs: [
          Tab(
            text: isArabic
                ? 'أشخاص (${_userResults.length})'
                : 'People (${_userResults.length})',
          ),
          Tab(
            text: isArabic
                ? 'غرف (${_roomResults.length})'
                : 'Rooms (${_roomResults.length})',
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(List<_SearchResult> items, bool isArabic) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          isArabic ? 'لا توجد نتائج' : 'No results',
          style: const TextStyle(color: Color(0xFF9E91B8), fontSize: 15),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _ResultTile(result: items[i], isArabic: isArabic),
    );
  }

  Widget _buildEmptyState(bool isArabic) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_rounded, color: Color(0xFF2A1840), size: 72),
          const SizedBox(height: 16),
          Text(
            isArabic
                ? 'ابحث عن أشخاص أو غرف'
                : 'Search for people or rooms',
            style: const TextStyle(
              color: Color(0xFF9E91B8),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults(bool isArabic) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.search_off_rounded,
            color: Color(0xFF4A3470),
            size: 56,
          ),
          const SizedBox(height: 14),
          Text(
            isArabic
                ? 'لا توجد نتائج لـ "$_query"'
                : 'No results for "$_query"',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFBCAED6),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result, required this.isArabic});

  final _SearchResult result;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final dir = isArabic ? TextDirection.rtl : TextDirection.ltr;
    final isUser = result.type == 'user';

    return GestureDetector(
      onTap: () {
        if (result.type == 'user') {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  UserProfileScreen(userId: result.id, isArabic: isArabic),
            ),
          );
        } else if (result.room != null) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  RoomDetailsScreen(room: result.room!, isArabic: isArabic),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF160B24),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF6E3AA8).withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          textDirection: dir,
          children: [
            isUser
                ? CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF241638),
                    backgroundImage: result.imageUrl != null
                        ? NetworkImage(result.imageUrl!)
                        : null,
                    child: result.imageUrl == null
                        ? Text(
                            result.title.isNotEmpty
                                ? result.title[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          )
                        : null,
                  )
                : Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF241638),
                      borderRadius: BorderRadius.circular(14),
                      image: result.imageUrl != null
                          ? DecorationImage(
                              image: NetworkImage(result.imageUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: result.imageUrl == null
                        ? const Icon(
                            Icons.meeting_room_rounded,
                            color: Color(0xFF9E91B8),
                            size: 24,
                          )
                        : null,
                  ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: isArabic
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Row(
                    textDirection: dir,
                    children: [
                      Flexible(
                        child: Text(
                          result.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (result.isLive == true) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFF4D6D,
                            ).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(
                                0xFFFF4D6D,
                              ).withValues(alpha: 0.5),
                            ),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(
                              color: Color(0xFFFF4D6D),
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (result.subtitle?.isNotEmpty == true) ...[
                    const SizedBox(height: 3),
                    Text(
                      result.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF9E91B8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isUser
                  ? Icons.person_add_alt_rounded
                  : Icons.arrow_forward_ios_rounded,
              color: const Color(0xFF6E5A8A),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
