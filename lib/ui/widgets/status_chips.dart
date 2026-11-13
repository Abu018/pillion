import 'package:flutter/material.dart';

import '../../core/models.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class TrackChip extends StatelessWidget {
  const TrackChip(this.status, {super.key});
  final TrackReadiness status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      TrackReadiness.ready => (Colors.green, Icons.check_circle),
      TrackReadiness.missing => (Colors.orange, Icons.help),
      TrackReadiness.mismatch => (Colors.red, Icons.error),
      TrackReadiness.unknown => (Colors.grey, Icons.hourglass_empty),
    };
    return StatusChip(label: status.label, color: color, icon: icon);
  }
}

class SyncChip extends StatelessWidget {
  const SyncChip(this.status, {super.key, this.driftMs});
  final SyncStatus status;
  final int? driftMs;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      SyncStatus.synced => Colors.green,
      SyncStatus.adjusting => Colors.amber.shade800,
      SyncStatus.outOfSync => Colors.red,
      SyncStatus.idle => Colors.grey,
    };
    final drift = driftMs;
    final label = drift == null || status == SyncStatus.idle
        ? status.label
        : '${status.label} (${drift > 0 ? '+' : ''}$drift ms)';
    return StatusChip(label: label, color: color, icon: Icons.sync);
  }
}
