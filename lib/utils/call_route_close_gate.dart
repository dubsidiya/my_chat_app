/// Coordinates terminal call-route closure with a permission dialog.
///
/// A route pop while the dialog is open only dismisses the dialog. This gate
/// remembers that the underlying call route still needs to close afterwards.
class CallRouteCloseGate {
  bool _dialogOpen = false;
  bool _closePending = false;

  bool get isDialogOpen => _dialogOpen;

  bool beginDialog() {
    if (_dialogOpen) return false;
    _dialogOpen = true;
    return true;
  }

  /// Returns true when the route may be closed immediately.
  bool requestClose() {
    if (!_dialogOpen) return true;
    _closePending = true;
    return false;
  }

  /// Returns true when a deferred route close should now run.
  bool endDialog() {
    _dialogOpen = false;
    final shouldClose = _closePending;
    _closePending = false;
    return shouldClose;
  }
}
