import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../app/creation_flow.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../data/models.dart';
import '../../../state/app_state.dart';
import 'voice_sheet.dart';

/// "Type your idea" card from the home screen: free-text prompt plus the three
/// ways to give us a face — camera, photo library, or voice.
class PromptComposer extends StatefulWidget {
  const PromptComposer({super.key, this.compact = false});

  final bool compact;

  @override
  State<PromptComposer> createState() => _PromptComposerState();
}

class _PromptComposerState extends State<PromptComposer> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickFromLibrary() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 92,
    );
    if (file == null || !mounted) return;
    await context.read<AppState>().setFacePhoto(file.path);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.s.photoUpdated),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _dictate() async {
    final spoken = await VoiceSheet.show(context);
    if (spoken == null || !mounted) return;
    _controller.text = spoken;
    await _submit(source: CreationSource.voice);
  }

  Future<void> _submit({CreationSource source = CreationSource.prompt}) async {
    final text = _controller.text.trim();
    if (text.isEmpty || _submitting) return;

    setState(() => _submitting = true);
    await CreationFlow.start(
      context,
      customPrompt: text,
      source: source,
    );
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.hairline, width: 1.4),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            minLines: widget.compact ? 1 : 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            style: AppTypography.body.copyWith(color: AppColors.ink),
            decoration: InputDecoration(
              hintText: context.s.promptHint,
              hintStyle: AppTypography.body.copyWith(
                color: AppColors.inkMuted,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 6,
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // The chips scroll rather than overflow — their widths change
              // with locale and the user's text-size setting.
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _ComposerAction(
                        icon: Icons.photo_camera_rounded,
                        label: 'Camera',
                        onPressed: () => CreationFlow.retakePhoto(context),
                      ),
                      const SizedBox(width: 8),
                      _ComposerAction(
                        icon: Icons.add_photo_alternate_rounded,
                        label: 'Add image',
                        onPressed: _pickFromLibrary,
                      ),
                      const SizedBox(width: 8),
                      _ComposerAction(
                        icon: Icons.mic_rounded,
                        label: 'Voice',
                        onPressed: _dictate,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) => PressableScale(
                  scale: 0.9,
                  onPressed: value.text.trim().isEmpty || _submitting
                      ? null
                      : _submit,
                  child: Container(
                    height: 44,
                    width: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFE11D28), AppColors.primaryDark],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: AppShadows.button,
                    ),
                    child: _submitting
                        ? const Padding(
                            padding: EdgeInsets.all(13),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor:
                                  AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Icon(Icons.arrow_upward_rounded,
                            size: 21, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComposerAction extends StatelessWidget {
  const _ComposerAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scale: 0.94,
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: AppColors.primaryBright),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.caption.copyWith(color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}
