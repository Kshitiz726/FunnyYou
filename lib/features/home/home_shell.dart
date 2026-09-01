import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/glass.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'profile_screen.dart';

/// Bottom-tab container. Only three destinations on purpose — anything more
/// gets confusing for the target audience.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final PageController _controller = PageController();

  /// The *continuous* page offset, not the settled index. Driving the tab bar
  /// from this is what makes the highlight travel with the page instead of
  /// blinking to its destination — and it keeps following a half-finished
  /// swipe, which an index alone cannot express.
  double _page = 0;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final page = _controller.page;
      if (page == null || page == _page) return;
      setState(() => _page = page);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int index) {
    if (_index == index) return;
    HapticFeedback.selectionClick();
    _controller.animateToPage(
      index,
      duration: AppDuration.base,
      // Apple's tab transitions decelerate hard at the end and never overshoot;
      // easeOutCubic is the closest standard curve to that.
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The tab bar is frosted, so the content has to actually pass underneath
      // it — otherwise there is nothing for it to blur.
      extendBody: true,
      body: PageView(
        controller: _controller,
        physics: const ClampingScrollPhysics(),
        onPageChanged: (index) {
          if (_index == index) return;
          HapticFeedback.selectionClick();
          setState(() => _index = index);
        },
        children: [
          const _KeepAlive(child: HomeScreen()),
          _KeepAlive(child: LibraryScreen(onCreate: () => _go(0))),
          const _KeepAlive(child: ProfileScreen()),
        ],
      ),
      bottomNavigationBar: _TabBar(page: _page, onChanged: _go),
    );
  }
}

/// A [PageView] tears down pages it has scrolled past, which would throw away
/// each tab's scroll position and re-run its first build on every visit.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.page, required this.onChanged});

  /// Continuous, so the pill can sit between two tabs mid-transition.
  final double page;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final items = [
      (Icons.auto_awesome_rounded, s.tabCreate),
      (Icons.video_library_rounded, s.tabVideos),
      (Icons.person_rounded, s.tabMe),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        MediaQuery.paddingOf(context).bottom + 10,
      ),
      child: GlassPanel(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        opacity: 0.62,
        padding: const EdgeInsets.all(6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slot = constraints.maxWidth / items.length;
            return SizedBox(
              height: 58,
              child: Stack(
                children: [
                  // One pill that moves, rather than three that fade. The
                  // travel is what reads as "smooth" — a cross-fade in place
                  // looks like a hard cut no matter how long you make it.
                  Positioned(
                    left: page.clamp(0, items.length - 1) * slot,
                    top: 0,
                    bottom: 0,
                    width: slot,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        boxShadow: AppShadows.button,
                      ),
                    ),
                  ),
                  Row(
                    // Stretch so each tab's hit area is the full pill height,
                    // not just the icon and label.
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: _Tab(
                            icon: items[i].$1,
                            label: items[i].$2,
                            // 1 when the pill is centred here, 0 once it has
                            // fully left — so the label crossfades in step
                            // with the pill sliding under it.
                            selection: (1 - (page - i).abs()).clamp(0.0, 1.0),
                            onPressed: () => onChanged(i),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.label,
    required this.selection,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final double selection;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = Color.lerp(AppColors.inkMuted, Colors.white, selection)!;
    return PressableScale(
      scale: 0.93,
      onPressed: onPressed,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
