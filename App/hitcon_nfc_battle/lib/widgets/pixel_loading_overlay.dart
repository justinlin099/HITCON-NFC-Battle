import 'package:flutter/material.dart';

import '../pages/user/pixel_theme.dart';

Future<T> runWithPixelLoadingOverlay<T>(
  BuildContext context, {
  required String label,
  required Future<T> Function() action,
}) async {
  final OverlayState overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => PixelLoadingOverlay(label: label));
  overlay.insert(entry);
  await WidgetsBinding.instance.endOfFrame;
  try {
    return await action();
  } finally {
    entry.remove();
    entry.dispose();
  }
}

class PixelLoadingOverlay extends StatelessWidget {
  const PixelLoadingOverlay({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.72),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: PixelTheme.bgMid,
                border: Border.all(color: PixelTheme.accent, width: 3),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Colors.black,
                    blurRadius: 0,
                    offset: Offset(5, 5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const _PixelLoadingBlocks(),
                  const SizedBox(height: 14),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: PixelTheme.textWhite,
                      fontFamily: 'Unifont',
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PixelLoadingBlocks extends StatefulWidget {
  const _PixelLoadingBlocks();

  @override
  State<_PixelLoadingBlocks> createState() => _PixelLoadingBlocksState();
}

class _PixelLoadingBlocksState extends State<_PixelLoadingBlocks>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final int active = (_controller.value * 4).floor() % 4;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(4, (int index) {
            return Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              color: index == active ? PixelTheme.accent : PixelTheme.border,
            );
          }),
        );
      },
    );
  }
}
