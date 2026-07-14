import 'package:flutter/material.dart';
import '../models/crash_v3_bet.dart';

class CrashV3BetPanel extends StatefulWidget {
  const CrashV3BetPanel({
    required this.slot,
    required this.minimum,
    required this.maximum,
    required this.pending,
    required this.canBet,
    required this.currentBet,
    required this.onBet,
    required this.onCashout,
    super.key,
  });
  final int slot, minimum, maximum;
  final bool pending, canBet;
  final CrashV3Bet? currentBet;
  final void Function(int, double?) onBet;
  final VoidCallback onCashout;
  @override
  State<CrashV3BetPanel> createState() => _CrashV3BetPanelState();
}

class _CrashV3BetPanelState extends State<CrashV3BetPanel> {
  late final TextEditingController amount, auto;
  @override
  void initState() {
    super.initState();
    amount = TextEditingController(text: '${widget.minimum}');
    auto = TextEditingController(text: '2.00');
  }

  @override
  void dispose() {
    amount.dispose();
    auto.dispose();
    super.dispose();
  }

  void scale(double value) {
    final current = int.tryParse(amount.text) ?? widget.minimum;
    amount.text = (current * value)
        .round()
        .clamp(widget.minimum, widget.maximum)
        .toString();
  }

  @override
  Widget build(BuildContext context) {
    final bet = widget.currentBet;
    final accepted = bet?.canCashout ?? false;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF180D29),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF6D28D9)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'BET ${widget.slot}',
                style: const TextStyle(
                  color: Color(0xFFE879F9),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              if (bet != null)
                Text(
                  bet.status.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFFFC857),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _field(amount, 'Coins')),
              const SizedBox(width: 8),
              Expanded(child: _field(auto, 'Auto ×', decimal: true)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final value in [100, 500, 1000, 5000])
                ActionChip(
                  label: Text('$value'),
                  onPressed: widget.pending
                      ? null
                      : () {
                          amount.text = value
                              .clamp(widget.minimum, widget.maximum)
                              .toString();
                        },
                ),
              ActionChip(
                label: const Text('½'),
                onPressed: widget.pending ? null : () => scale(.5),
              ),
              ActionChip(
                label: const Text('2×'),
                onPressed: widget.pending ? null : () => scale(2),
              ),
              ActionChip(
                label: const Text('MAX'),
                onPressed: widget.pending
                    ? null
                    : () {
                        amount.text = '${widget.maximum}';
                      },
              ),
            ],
          ),
          const SizedBox(height: 9),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: widget.pending
                  ? null
                  : accepted
                  ? widget.onCashout
                  : widget.canBet
                  ? () {
                      final value = int.tryParse(amount.text);
                      if (value != null) {
                        widget.onBet(value, double.tryParse(auto.text));
                      }
                    }
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: accepted
                    ? const Color(0xFF35E59A)
                    : const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: Text(
                widget.pending
                    ? 'PLEASE WAIT'
                    : accepted
                    ? 'CASH OUT'
                    : 'PLACE BET',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool decimal = false,
  }) => TextField(
    controller: controller,
    keyboardType: TextInputType.numberWithOptions(decimal: decimal),
    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
    decoration: InputDecoration(
      isDense: true,
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: Colors.black26,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
