import 'package:material_ui/material_ui.dart';

import '../online/session.dart';
import 'app_update.dart';
import 'theme.dart';

/// "Update available" toast pinned to the top of every screen.
class UpdateToast extends StatefulWidget {
  const UpdateToast({super.key, this.onUpdate = applyUpdate});

  final VoidCallback onUpdate;

  @override
  State<UpdateToast> createState() => _UpdateToastState();
}

class _UpdateToastState extends State<UpdateToast> {
  bool _dismissed = false;
  bool _updating = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: updateReady,
      builder: (context, ready, _) {
        final show = ready && !_dismissed;
        return AnimatedSlide(
          offset: show ? Offset.zero : const Offset(0, -1.6),
          duration: const Duration(milliseconds: 320),
          curve: show ? Curves.easeOutBack : Curves.easeIn,
          child: AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !show,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: _card(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _card() {
    return Material(
      color: Palette.surfaceHigh,
      elevation: 8,
      shadowColor: Colors.black,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Palette.brand.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.system_update_alt_rounded,
                color: Palette.brand,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Update available', style: font(15, weight: 650)),
                  Text(
                    // Online you come straight back to the room; a game
                    // against bots lives only in this tab.
                    OnlineSession.instance.inRoom
                        ? 'You rejoin your room right after.'
                        : 'A game against bots will restart.',
                    style: font(12.5, color: Palette.muted),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _updating
                  ? null
                  : () => setState(() => _dismissed = true),
              style: TextButton.styleFrom(foregroundColor: Palette.muted),
              child: Text('Later', style: font(14, weight: 600)),
            ),
            const SizedBox(width: 2),
            FilledButton(
              onPressed: _updating
                  ? null
                  : () {
                      setState(() => _updating = true);
                      widget.onUpdate();
                    },
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _updating
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text('Update', style: font(14, weight: 650)),
            ),
          ],
        ),
      ),
    );
  }
}
