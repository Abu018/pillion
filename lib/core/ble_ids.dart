/// GATT layout shared by host (peripheral) and participants (central).
abstract final class BleIds {
  static const service = 'b5a1f000-6f1e-4c4a-9d3e-2a7c5e0f1a01';

  /// Read: room metadata and session state.
  static const roomInfo = 'b5a1f001-6f1e-4c4a-9d3e-2a7c5e0f1a01';

  /// Indicate (host -> peers): playback commands and room state.
  static const control = 'b5a1f002-6f1e-4c4a-9d3e-2a7c5e0f1a01';

  /// Write (peer -> host) clock probes and position reports; indicate replies.
  static const sync = 'b5a1f003-6f1e-4c4a-9d3e-2a7c5e0f1a01';

  /// Write/indicate: optional group-ducking voice events.
  static const voiceState = 'b5a1f004-6f1e-4c4a-9d3e-2a7c5e0f1a01';

  /// Write (join/leave/track readiness); indicate roster updates.
  static const participantState = 'b5a1f005-6f1e-4c4a-9d3e-2a7c5e0f1a01';

  /// 0xFFFF is reserved by the Bluetooth SIG for testing/internal use.
  static const manufacturerId = 0xFFFF;

  static const downlinkCharacteristics = [
    control,
    sync,
    voiceState,
    participantState,
  ];
}
