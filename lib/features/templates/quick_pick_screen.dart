import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/backdrop.dart';
import '../../data/templates.dart';
import '../../services/service_locator.dart';
import '../../state/app_state.dart';
import 'template_picker_screen.dart';
import 'widgets/template_tile.dart';

/// The first thing shown after the ad: six scenarios, and a way to see the
/// rest.
///
/// The full catalogue is forty tiles in six categories with a hero preview and
/// a filter rail. That is the right screen for someone browsing and the wrong
/// one for someone who has just been told to pick. So this shows a handful,
/// each with the user's own face already swapped in where a preview exists,
/// and puts the catalogue one tap away under **More scenarios**.
///
/// Pops with the chosen [VideoTemplate], or null if the user backs out.
class QuickPickScreen extends StatefulWidget {
  const QuickPickScreen({super.key});

  /// How many scenarios get a tile here. Six fills a 2x3 grid on every phone
  /// we support without scrolling, which is the point of the screen.
  static const int shortlistLength = 6;

  @override
  State<QuickPickScreen> createState() => _QuickPickScreenState();
}

class _QuickPickScreenState extends State<QuickPickScreen> {
  @override
  void initState() {
    super.initState();
    // The catalogue may know by now which scenarios the renderer can actually
    // produce; asking again here costs nothing and keeps dead tiles off the
    // one screen where every tile is a real offer.
    unawaited(ServiceLocator.instance.backend.refreshIfUnknown());
  }

  /// Prefer scenarios we already have a preview of the user's own face for.
  ///
  /// Those are the tiles that sell the product: seeing your face as an
  /// astronaut is the whole pitch, and a gradient placeholder is not. The rest
  /// of the slots are filled from the front of the catalogue, which is
  /// hand-ordered with the strongest scenarios first.
  List<VideoTemplate> _shortlist() {
    final previews = ServiceLocator.instance.previewStore;
    final withPreview = <VideoTemplate>[];
    final rest = <VideoTemplate>[];

    for (final template in TemplateCatalog.all) {
      if (previews.pathFor(template.id) != null) {
        withPreview.add(template);
      } else {
        rest.add(template);
      }
    }

    return [...withPreview, ...rest].take(QuickPickScreen.shortlistLength).toList();
  }

  void _choose(VideoTemplate template) {
    HapticFeedback.selectionClick();
    context.read<AppState>().selectTemplate(template);
    Navigator.of(context).pop(template);
  }

  Future<void> _openFullCatalogue() async {
    final picked = await Navigator.of(context).push<VideoTemplate>(
      MaterialPageRoute(builder: (_) => const TemplatePickerScreen()),
    );
    if (picked == null || !mounted) return;
    Navigator.of(context).pop(picked);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final facePhoto = context.select<AppState, String?>((s) => s.facePhotoPath);
    final previews = ServiceLocator.instance.previewStore;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemOverlayLight,
      child: Scaffold(
        body: AuroraBackdrop(
          baseColor: AppColors.cream,
          child: SafeArea(
            child: Column(
              children: [
                // The back button shares the title's row rather than taking
                // one of its own. iOS has no hardware back and this route has
                // no nav bar, so the button has to exist -- but a whole extra
                // row of chrome pushed the third tile row's labels under the
                // More scenarios button, and six tiles fitting without
                // scrolling is the entire point of this screen.
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, AppSpacing.sm),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Navigator.of(context).canPop()
                            ? CircleIconButton(
                                icon: Icons.arrow_back_ios_new_rounded,
                                onPressed: () => Navigator.of(context).pop(),
                              )
                            : null,
                      ),
                      Expanded(
                        child: Text(
                          s.chooseYourScenario,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.display.copyWith(fontSize: 26),
                        ),
                      ),
                      // Balances the button so the title is centred on the
                      // screen rather than on the space left over.
                      const SizedBox(width: 44),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    // Previews arrive one at a time after the selfie, and
                    // each arrival can change which six scenarios lead, so the
                    // shortlist is rebuilt whenever the store moves.
                    child: AnimatedBuilder(
                      animation: previews,
                      builder: (context, _) {
                        final shortlist = _shortlist();
                        return GridView.builder(
                          padding:
                              const EdgeInsets.only(bottom: AppSpacing.md),
                          physics: const BouncingScrollPhysics(),
                          itemCount: shortlist.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: AppSpacing.md,
                            crossAxisSpacing: AppSpacing.md,
                            childAspectRatio: 0.78,
                          ),
                          itemBuilder: (context, index) {
                            final template = shortlist[index];
                            return TemplateTile(
                              template: template,
                              facePhotoPath: facePhoto,
                              selected: false,
                              onTap: () => _choose(template),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: SecondaryButton(
                    label: s.moreScenarios,
                    icon: Icons.grid_view_rounded,
                    onPressed: _openFullCatalogue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
