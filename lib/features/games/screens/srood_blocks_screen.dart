import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/srood_blocks_models.dart';
import '../services/srood_blocks_service.dart';

// ── Tetromino definitions ─────────────────────────────────────────────────────

// Each piece: list of rotations, each rotation: list of [row, col] offsets
const List<List<List<List<int>>>> _kPieces = [
  // I
  [
    [[0,0],[0,1],[0,2],[0,3]],
    [[0,0],[1,0],[2,0],[3,0]],
    [[0,0],[0,1],[0,2],[0,3]],
    [[0,0],[1,0],[2,0],[3,0]],
  ],
  // O
  [
    [[0,0],[0,1],[1,0],[1,1]],
    [[0,0],[0,1],[1,0],[1,1]],
    [[0,0],[0,1],[1,0],[1,1]],
    [[0,0],[0,1],[1,0],[1,1]],
  ],
  // T
  [
    [[0,1],[1,0],[1,1],[1,2]],
    [[0,0],[1,0],[1,1],[2,0]],
    [[0,0],[0,1],[0,2],[1,1]],
    [[0,1],[1,0],[1,1],[2,1]],
  ],
  // S
  [
    [[0,1],[0,2],[1,0],[1,1]],
    [[0,0],[1,0],[1,1],[2,1]],
    [[0,1],[0,2],[1,0],[1,1]],
    [[0,0],[1,0],[1,1],[2,1]],
  ],
  // Z
  [
    [[0,0],[0,1],[1,1],[1,2]],
    [[0,1],[1,0],[1,1],[2,0]],
    [[0,0],[0,1],[1,1],[1,2]],
    [[0,1],[1,0],[1,1],[2,0]],
  ],
  // J
  [
    [[0,0],[1,0],[1,1],[1,2]],
    [[0,0],[0,1],[1,0],[2,0]],
    [[0,0],[0,1],[0,2],[1,2]],
    [[0,2],[1,2],[2,1],[2,2]],
  ],
  // L
  [
    [[0,2],[1,0],[1,1],[1,2]],
    [[0,0],[1,0],[2,0],[2,1]],
    [[0,0],[0,1],[0,2],[1,0]],
    [[0,0],[0,1],[1,1],[2,1]],
  ],
];

const List<Color> _kPieceColors = [
  Color(0xFF22D3EE), // I - cyan
  Color(0xFFF0C15A), // O - gold
  Color(0xFFA855F7), // T - purple
  Color(0xFF4ADE80), // S - green
  Color(0xFFF87171), // Z - red
  Color(0xFF60A5FA), // J - blue
  Color(0xFFFB923C), // L - orange
];

// ── Board constants ───────────────────────────────────────────────────────────

const int _kCols = 10;
const int _kRows = 20;

// ── Game state ────────────────────────────────────────────────────────────────

class _Piece {
  _Piece({required this.type, this.rotation = 0, this.row = 0, this.col = 3});
  final int type;
  int rotation;
  int row;
  int col;

  List<List<int>> get cells => _kPieces[type][rotation];

  List<List<int>> get worldCells =>
      cells.map((c) => [c[0] + row, c[1] + col]).toList();

  _Piece copyWith({int? rotation, int? row, int? col}) => _Piece(
        type:     type,
        rotation: rotation ?? this.rotation,
        row:      row      ?? this.row,
        col:      col      ?? this.col,
      );
}

enum _GamePhase { playing, paused, over }

// ── Main screen ───────────────────────────────────────────────────────────────

class SroodBlocksScreen extends StatefulWidget {
  const SroodBlocksScreen({required this.isArabic, super.key});
  final bool isArabic;

  @override
  State<SroodBlocksScreen> createState() => _SroodBlocksScreenState();
}

class _SroodBlocksScreenState extends State<SroodBlocksScreen> {
  BlocksDailyStatus? _status;
  bool _loadingStatus = true;
  String? _statusError;

  // tab: 0 = play, 1 = leaderboard
  int _tab = 0;
  List<BlocksLeaderboardEntry>? _leaderboard;
  bool _loadingLeaderboard = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() { _loadingStatus = true; _statusError = null; });
    try {
      final s = await SroodBlocksService.getDailyStatus();
      if (mounted) setState(() { _status = s; _loadingStatus = false; });
    } catch (e) {
      if (mounted) setState(() { _statusError = e.toString(); _loadingStatus = false; });
    }
  }

  Future<void> _loadLeaderboard() async {
    setState(() => _loadingLeaderboard = true);
    try {
      final lb = await SroodBlocksService.getWeeklyLeaderboard();
      if (mounted) setState(() { _leaderboard = lb; _loadingLeaderboard = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingLeaderboard = false);
    }
  }

  bool get _ar => widget.isArabic;

  Future<void> _launchPlay({required bool isPaid}) async {
    try {
      await SroodBlocksService.startPlay(isPaid: isPaid);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('insufficient_coins')
          ? (_ar ? 'رصيد غير كافٍ' : 'Insufficient coins')
          : e.toString().contains('no_free_plays_left')
              ? (_ar ? 'لا تبقى لديك جولات مجانية' : 'No free plays left')
              : (_ar ? 'خطأ، حاول مجدداً' : 'Error, please try again');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    if (!mounted) return;
    final result = await Navigator.of(context).push<BlocksSubmitResult?>(
      MaterialPageRoute<BlocksSubmitResult?>(
        builder: (_) => _BlocksGameScreen(isArabic: widget.isArabic),
      ),
    );
    await _loadStatus();
    if (result != null && mounted && result.xpEarned > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_ar
            ? '+${result.xpEarned} XP 🎮'
            : '+${result.xpEarned} XP earned 🎮'),
        backgroundColor: const Color(0xFF6D28D9),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08030F),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: _tab == 0 ? _buildLobby() : _buildLeaderboard(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFF4C1D95)],
              ),
            ),
            child: const Center(
              child: Text('🟪', style: TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _ar ? 'سرود بلوكس' : 'Srood Blocks',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      child: Row(
        children: [
          _TabChip(
            label: _ar ? 'العب' : 'Play',
            selected: _tab == 0,
            onTap: () => setState(() => _tab = 0),
          ),
          const SizedBox(width: 10),
          _TabChip(
            label: _ar ? 'المتصدرون' : 'Leaderboard',
            selected: _tab == 1,
            onTap: () {
              setState(() => _tab = 1);
              if (_leaderboard == null) _loadLeaderboard();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLobby() {
    if (_loadingStatus) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)));
    }
    if (_statusError != null || _status == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_ar ? 'فشل التحميل' : 'Failed to load',
                style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 12),
            TextButton(onPressed: _loadStatus, child: Text(_ar ? 'إعادة المحاولة' : 'Retry')),
          ],
        ),
      );
    }
    final s = _status!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 100),
      child: Column(
        children: [
          _buildBoardPreview(),
          const SizedBox(height: 24),
          _buildStatsRow(s),
          const SizedBox(height: 28),
          _buildPlayButton(s),
          if (!s.hasFreePlay) ...[
            const SizedBox(height: 16),
            _buildExtraPlayButton(s),
          ],
          const SizedBox(height: 28),
          _buildRules(),
        ],
      ),
    );
  }

  Widget _buildBoardPreview() {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A0533), Color(0xFF2D0D5E)],
        ),
        border: Border.all(color: const Color(0xFF6D28D9).withValues(alpha: 0.5)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // decorative mini blocks
          for (final pos in const <(double, double)>[
            (0.15, 0.3), (0.3, 0.6), (0.55, 0.2), (0.7, 0.7), (0.45, 0.8),
          ])
            Positioned(
              left: 160 * pos.$1,
              top:  180 * pos.$2,
              child: Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: _kPieceColors[
                    (_kPieceColors.length * pos.$1).toInt() % _kPieceColors.length
                  ].withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _kPieceColors[
                      (_kPieceColors.length * pos.$1).toInt() % _kPieceColors.length
                    ].withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🟪', style: TextStyle(fontSize: 44)),
              const SizedBox(height: 8),
              Text(
                _ar ? 'ألعب الآن!' : 'Play Now!',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _ar ? 'رتّب البلوكس واكسب XP' : 'Stack blocks and earn XP',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(BlocksDailyStatus s) {
    return Row(
      children: [
        Expanded(child: _StatCard(
          icon: '🎮',
          label: _ar ? 'جولات متبقية' : 'Plays Left',
          value: '${s.playsRemaining} / ${s.freePlays}',
        )),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(
          icon: '⭐',
          label: _ar ? 'XP اليوم' : 'XP Today',
          value: '${s.xpToday} / ${s.xpCap}',
        )),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(
          icon: '🪙',
          label: _ar ? 'العملات' : 'Coins',
          value: '${s.coinsBalance}',
        )),
      ],
    );
  }

  Widget _buildPlayButton(BlocksDailyStatus s) {
    final canPlay = s.hasFreePlay;
    return GestureDetector(
      onTap: canPlay ? () => _launchPlay(isPaid: false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: canPlay
              ? const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                )
              : null,
          color: canPlay ? null : const Color(0xFF2D1060).withValues(alpha: 0.4),
          boxShadow: canPlay
              ? [const BoxShadow(
                  color: Color(0x558B5CF6), blurRadius: 18, offset: Offset(0, 8))]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          canPlay
              ? (_ar ? '▶ ابدأ اللعب' : '▶ Start Playing')
              : (_ar ? 'انتهت الجولات المجانية' : 'No Free Plays Left'),
          style: TextStyle(
            color: canPlay ? Colors.white : Colors.white38,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _buildExtraPlayButton(BlocksDailyStatus s) {
    final canBuy = s.canBuyPlay;
    return GestureDetector(
      onTap: canBuy ? () => _showBuyPlayDialog(s) : null,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: canBuy
                ? const Color(0xFFF0C15A).withValues(alpha: 0.7)
                : Colors.white12,
          ),
          color: canBuy
              ? const Color(0xFFF0C15A).withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        alignment: Alignment.center,
        child: Text(
          _ar
              ? 'جولة إضافية مقابل ${s.extraPlayCost} 🪙'
              : 'Extra play for ${s.extraPlayCost} 🪙',
          style: TextStyle(
            color: canBuy ? const Color(0xFFF0C15A) : Colors.white24,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<void> _showBuyPlayDialog(BlocksDailyStatus s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A0533),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          _ar ? 'جولة إضافية' : 'Extra Play',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          _ar
              ? 'هل تريد شراء جولة إضافية مقابل ${s.extraPlayCost} عملة؟'
              : 'Buy an extra play for ${s.extraPlayCost} coins?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_ar ? 'إلغاء' : 'Cancel',
                style: const TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_ar ? 'شراء' : 'Buy',
                style: const TextStyle(color: Color(0xFFF0C15A), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _launchPlay(isPaid: true);
    }
  }

  Widget _buildRules() {
    final rules = _ar
        ? [
            '⬅️ اسحب يساراً/يميناً للتحريك',
            '⬆️ اضغط للتدوير',
            '⬇️ اسحب للأسفل للتسريع',
            '⭐ اكسب XP مع كل جولة',
            '🚫 لا تكسب عملات من اللعب',
          ]
        : [
            '⬅️ Swipe left/right to move',
            '⬆️ Tap to rotate',
            '⬇️ Swipe down to drop faster',
            '⭐ Earn XP every round',
            '🚫 Coins are never earned from play',
          ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _ar ? 'كيف تلعب' : 'How to Play',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 10),
          for (final r in rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(r, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Widget _buildLeaderboard() {
    if (_loadingLeaderboard) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)));
    }
    final lb = _leaderboard;
    if (lb == null || lb.isEmpty) {
      return Center(
        child: Text(
          _ar ? 'لا توجد بيانات هذا الأسبوع' : 'No scores this week yet',
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 100),
      itemCount: lb.length,
      itemBuilder: (ctx, i) {
        final e = lb[i];
        final isTop3 = e.rank <= 3;
        final medals = ['🥇', '🥈', '🥉'];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: isTop3
                ? LinearGradient(
                    colors: [
                      const Color(0xFF6D28D9).withValues(alpha: 0.3),
                      const Color(0xFF4C1D95).withValues(alpha: 0.2),
                    ],
                  )
                : null,
            color: isTop3 ? null : Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: isTop3
                  ? const Color(0xFF8B5CF6).withValues(alpha: 0.4)
                  : Colors.white12,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  isTop3 ? medals[e.rank - 1] : '#${e.rank}',
                  style: TextStyle(
                    fontSize: isTop3 ? 22 : 14,
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 12),
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFF4C1D95),
                backgroundImage: e.avatarUrl != null
                    ? NetworkImage(e.avatarUrl!)
                    : null,
                child: e.avatarUrl == null
                    ? Text(
                        e.displayName.isNotEmpty ? e.displayName[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.displayName,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                    Text(
                      _ar
                          ? '${e.totalLines} سطر'
                          : '${e.totalLines} lines cleared',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${e.bestScore}',
                    style: const TextStyle(
                      color: Color(0xFFF0C15A),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    _ar ? 'نقطة' : 'pts',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Game screen ───────────────────────────────────────────────────────────────

class _BlocksGameScreen extends StatefulWidget {
  const _BlocksGameScreen({required this.isArabic});
  final bool isArabic;

  @override
  State<_BlocksGameScreen> createState() => _BlocksGameState();
}

class _BlocksGameState extends State<_BlocksGameScreen> {
  // board: null = empty, int = piece type index (0-6)
  late List<List<int?>> _board;
  _Piece? _current;
  _Piece? _next;
  _Piece? _held;
  bool _holdUsed = false;

  _GamePhase _phase = _GamePhase.playing;
  int _score = 0;
  int _lines = 0;
  int _level = 1;
  Timer? _ticker;
  final math.Random _rng = math.Random();

  final _stopwatch = Stopwatch();
  // swipe detection
  Offset? _swipeStart;

  @override
  void initState() {
    super.initState();
    _initBoard();
    _spawnPiece();
    _startTicker();
    _stopwatch.start();
  }

  void _initBoard() {
    _board = List.generate(_kRows, (_) => List.filled(_kCols, null));
  }

  _Piece _randomPiece() {
    final type = _rng.nextInt(_kPieces.length);
    return _Piece(type: type, row: 0, col: _kCols ~/ 2 - 2);
  }

  void _spawnPiece() {
    _current = _next ?? _randomPiece();
    _next    = _randomPiece();
    _holdUsed = false;
    if (!_isValid(_current!)) {
      _gameOver();
    }
  }

  void _startTicker() {
    final ms = math.max(100, 800 - (_level - 1) * 60);
    _ticker = Timer.periodic(Duration(milliseconds: ms), (_) => _tick());
  }

  void _restartTicker() {
    _ticker?.cancel();
    _startTicker();
  }

  void _tick() {
    if (_phase != _GamePhase.playing) return;
    _tryMove(dr: 1);
  }

  bool _isValid(_Piece p) {
    for (final c in p.worldCells) {
      final r = c[0], col = c[1];
      if (r < 0 || r >= _kRows || col < 0 || col >= _kCols) return false;
      if (_board[r][col] != null) return false;
    }
    return true;
  }

  void _tryMove({int dr = 0, int dc = 0}) {
    if (_current == null) return;
    final moved = _current!.copyWith(row: _current!.row + dr, col: _current!.col + dc);
    if (_isValid(moved)) {
      setState(() => _current = moved);
    } else if (dr == 1) {
      _lock();
    }
  }

  void _rotate() {
    if (_current == null) return;
    final rotated = _current!.copyWith(
      rotation: (_current!.rotation + 1) % 4,
    );
    // wall kicks
    for (final kick in [0, 1, -1, 2, -2]) {
      final kicked = rotated.copyWith(col: rotated.col + kick);
      if (_isValid(kicked)) {
        setState(() => _current = kicked);
        return;
      }
    }
  }

  void _hardDrop() {
    if (_current == null) return;
    var p = _current!;
    while (true) {
      final next = p.copyWith(row: p.row + 1);
      if (_isValid(next)) {
        p = next;
      } else {
        break;
      }
    }
    _score += (p.row - _current!.row) * 2;
    setState(() => _current = p);
    _lock();
  }

  void _lock() {
    if (_current == null) return;
    for (final c in _current!.worldCells) {
      if (c[0] >= 0) _board[c[0]][c[1]] = _current!.type;
    }
    _clearLines();
    _spawnPiece();
    setState(() {});
  }

  void _clearLines() {
    final cleared = <int>[];
    for (int r = 0; r < _kRows; r++) {
      if (_board[r].every((c) => c != null)) cleared.add(r);
    }
    if (cleared.isEmpty) return;
    for (final r in cleared) {
      _board.removeAt(r);
      _board.insert(0, List.filled(_kCols, null));
    }
    final n = cleared.length;
    final points = [0, 100, 300, 500, 800][math.min(n, 4)] * _level;
    _lines += n;
    _score += points;
    _level = (_lines ~/ 10) + 1;
    _restartTicker();
  }

  void _holdPiece() {
    if (_holdUsed || _current == null) return;
    setState(() {
      if (_held == null) {
        _held = _Piece(type: _current!.type);
        _current = _next;
        _next = _randomPiece();
      } else {
        final tmp = _Piece(type: _held!.type);
        _held = _Piece(type: _current!.type);
        _current = tmp;
      }
      _holdUsed = true;
    });
    if (!_isValid(_current!)) _gameOver();
  }

  void _gameOver() {
    _ticker?.cancel();
    _stopwatch.stop();
    _phase = _GamePhase.over;
    setState(() {});
    _submitScore();
  }

  Future<void> _submitScore() async {
    try {
      final result = await SroodBlocksService.submitScore(
        score:       _score,
        lines:       _lines,
        level:       _level,
        durationSec: math.max(30, _stopwatch.elapsed.inSeconds),
      );
      if (mounted) {
        _showGameOverDialog(result);
      }
    } catch (_) {
      if (mounted) _showGameOverDialog(null);
    }
  }

  void _showGameOverDialog(BlocksSubmitResult? result) {
    final ar = widget.isArabic;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A0533),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          ar ? 'انتهت اللعبة!' : 'Game Over!',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$_score',
              style: const TextStyle(
                color: Color(0xFFF0C15A),
                fontSize: 48,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(ar ? 'نقطة' : 'points',
                style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 12),
            if (result != null && result.xpEarned > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFF6D28D9).withValues(alpha: 0.3),
                  border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.5)),
                ),
                child: Text(
                  ar ? '+${result.xpEarned} XP ⭐' : '+${result.xpEarned} XP earned ⭐',
                  style: const TextStyle(
                      color: Color(0xFFA78BFA), fontWeight: FontWeight.w700),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              ar ? 'سطور: $_lines   مستوى: $_level' : 'Lines: $_lines   Level: $_level',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
        actions: [
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop(result);
              },
              child: Text(
                ar ? 'العودة' : 'Back',
                style: const TextStyle(
                    color: Color(0xFF8B5CF6), fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _pause() {
    if (_phase == _GamePhase.playing) {
      _ticker?.cancel();
      _stopwatch.stop();
      setState(() => _phase = _GamePhase.paused);
    } else if (_phase == _GamePhase.paused) {
      _startTicker();
      _stopwatch.start();
      setState(() => _phase = _GamePhase.playing);
    }
  }

  void _onPanStart(DragStartDetails d) {
    _swipeStart = d.localPosition;
  }

  void _onPanEnd(DragEndDetails d) {
    if (_swipeStart == null || _phase != _GamePhase.playing) return;
    _swipeStart = null;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_swipeStart == null || _phase != _GamePhase.playing) return;
    final delta = d.localPosition - _swipeStart!;
    if (delta.dx.abs() > 20 || delta.dy.abs() > 20) {
      if (delta.dy > delta.dx.abs() && delta.dy > 30) {
        // swipe down → drop
        _hardDrop();
        _swipeStart = null;
      } else if (delta.dx.abs() > 20) {
        _tryMove(dc: delta.dx > 0 ? 1 : -1);
        _swipeStart = d.localPosition;
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final boardWidth  = size.width - 36;
    final cellSize    = boardWidth / _kCols;
    final boardHeight = cellSize * _kRows;

    return Scaffold(
      backgroundColor: const Color(0xFF08030F),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: 10),
                  _buildSidePanel(cellSize),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onPanStart:  _onPanStart,
                      onPanUpdate: _onPanUpdate,
                      onPanEnd:    _onPanEnd,
                      onTap:       _rotate,
                      child: CustomPaint(
                        size: Size(boardWidth * 0.72, boardHeight),
                        painter: _BoardPainter(
                          board:   _board,
                          current: _current,
                          cellSize: cellSize * 0.72,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildRightPanel(cellSize),
                  const SizedBox(width: 10),
                ],
              ),
            ),
            _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final ar = widget.isArabic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          _ScoreTile(label: ar ? 'النقاط' : 'Score', value: '$_score'),
          const SizedBox(width: 10),
          _ScoreTile(label: ar ? 'السطور' : 'Lines',  value: '$_lines'),
          const SizedBox(width: 10),
          _ScoreTile(label: ar ? 'المستوى' : 'Level',  value: '$_level'),
          const Spacer(),
          GestureDetector(
            onTap: _pause,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _phase == _GamePhase.paused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidePanel(double cellSize) {
    final ar = widget.isArabic;
    return SizedBox(
      width: 58,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(ar ? 'احتج' : 'Hold',
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 4),
          Container(
            width: 54, height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: Colors.white12),
            ),
            child: _held != null
                ? CustomPaint(painter: _MiniPiecePainter(type: _held!.type))
                : null,
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: _holdPiece,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: _holdUsed
                    ? Colors.white.withValues(alpha: 0.04)
                    : const Color(0xFF6D28D9).withValues(alpha: 0.5),
              ),
              child: Text(
                ar ? 'احفظ' : 'Hold',
                style: TextStyle(
                  color: _holdUsed ? Colors.white24 : Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel(double cellSize) {
    final ar = widget.isArabic;
    return SizedBox(
      width: 58,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(ar ? 'التالي' : 'Next',
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 4),
          Container(
            width: 54, height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: Colors.white12),
            ),
            child: _next != null
                ? CustomPaint(painter: _MiniPiecePainter(type: _next!.type))
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CtrlBtn(icon: Icons.arrow_back_rounded,      onTap: () => _tryMove(dc: -1)),
          _CtrlBtn(icon: Icons.rotate_right_rounded,    onTap: _rotate),
          _CtrlBtn(icon: Icons.keyboard_double_arrow_down_rounded, onTap: _hardDrop),
          _CtrlBtn(icon: Icons.arrow_forward_rounded,   onTap: () => _tryMove(dc: 1)),
        ],
      ),
    );
  }
}

// ── Custom painters ───────────────────────────────────────────────────────────

class _BoardPainter extends CustomPainter {
  const _BoardPainter({
    required this.board,
    required this.current,
    required this.cellSize,
  });

  final List<List<int?>> board;
  final _Piece?          current;
  final double           cellSize;

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke;

    // grid lines
    for (int r = 0; r <= _kRows; r++) {
      canvas.drawLine(
        Offset(0, r * cellSize),
        Offset(_kCols * cellSize, r * cellSize),
        borderPaint,
      );
    }
    for (int c = 0; c <= _kCols; c++) {
      canvas.drawLine(
        Offset(c * cellSize, 0),
        Offset(c * cellSize, _kRows * cellSize),
        borderPaint,
      );
    }

    // locked cells
    for (int r = 0; r < _kRows; r++) {
      for (int c = 0; c < _kCols; c++) {
        final t = board[r][c];
        if (t != null) _drawCell(canvas, r, c, _kPieceColors[t]);
      }
    }

    // ghost piece
    if (current != null) {
      var ghost = current!;
      while (true) {
        final next = ghost.copyWith(row: ghost.row + 1);
        bool valid = true;
        for (final cell in next.worldCells) {
          final gr = cell[0], gc = cell[1];
          if (gr >= _kRows || gc < 0 || gc >= _kCols ||
              (gr >= 0 && board[gr][gc] != null)) {
            valid = false; break;
          }
        }
        if (!valid) break;
        ghost = next;
      }
      for (final c in ghost.worldCells) {
        if (c[0] >= 0) {
          _drawCell(canvas, c[0], c[1],
              _kPieceColors[current!.type].withValues(alpha: 0.2));
        }
      }

      // active piece
      for (final c in current!.worldCells) {
        if (c[0] >= 0) _drawCell(canvas, c[0], c[1], _kPieceColors[current!.type]);
      }
    }
  }

  void _drawCell(Canvas canvas, int row, int col, Color color) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        col * cellSize + 1,
        row * cellSize + 1,
        cellSize - 2,
        cellSize - 2,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(rect, Paint()..color = color);
    // highlight
    canvas.drawRRect(
      rect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}

class _MiniPiecePainter extends CustomPainter {
  const _MiniPiecePainter({required this.type});
  final int type;

  @override
  void paint(Canvas canvas, Size size) {
    final cells = _kPieces[type][0];
    final color = _kPieceColors[type];
    final cs = size.width / 4;
    final minR = cells.map((c) => c[0]).reduce(math.min);
    final minC = cells.map((c) => c[1]).reduce(math.min);
    final maxR = cells.map((c) => c[0]).reduce(math.max);
    final maxC = cells.map((c) => c[1]).reduce(math.max);
    final offsetX = (size.width  - (maxC - minC + 1) * cs) / 2;
    final offsetY = (size.height - (maxR - minR + 1) * cs) / 2;

    for (final c in cells) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          offsetX + (c[1] - minC) * cs + 1,
          offsetY + (c[0] - minR) * cs + 1,
          cs - 2, cs - 2,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(r, Paint()..color = color);
      canvas.drawRRect(r, Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(_MiniPiecePainter old) => old.type != type;
}

// ── Small widgets ─────────────────────────────────────────────────────────────

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool   selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: selected
              ? const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)])
              : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white54,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value});
  final String icon, label, value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ScoreTile extends StatelessWidget {
  const _ScoreTile({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: Color(0xFFF0C15A), fontWeight: FontWeight.w900, fontSize: 18)),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ],
    );
  }
}

class _CtrlBtn extends StatelessWidget {
  const _CtrlBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 62,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF6D28D9).withValues(alpha: 0.3),
          border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }
}
