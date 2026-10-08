import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../services/photo_check_service.dart';
import 'live_light_meter.dart';
import 'photo_quality.dart';
import 'widgets/face_guide.dart';

/// Full-screen camera with a face guide, then a review step.
///
/// Pops with the captured file path, or null if the user backs out.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool _initialising = true;
  bool _capturing = false;
  String? _error;
  String? _reviewPath;
  /// Everything the checks found, which the review screen lists in full.
  /// The client asked to see the lighting and angle checks, and a check
  /// nobody can see is indistinguishable from one that was never built.
  PhotoReport? _report;

  /// Answers the half of the check the phone cannot: where the face is
  /// and which way it points. Silent when no backend is configured.
  final _photoCheck = PhotoCheckService();
  bool _inspecting = false;

  /// Reads the camera's own frames so the light can be fixed before the
  /// shutter rather than explained after it.
  late final _light = LiveLightMeter(
    onChanged: (reading) {
      if (mounted) setState(() => _light1 = reading);
    },
  );
  LightReading _light1 = LightReading.fine;

  bool get _cameraAvailable => _controller?.value.isInitialized ?? false;

  /// Whether [controller] is still the one this screen is using.
  ///
  /// A capture already in flight when the camera is torn down -- the app going
  /// to the background, a flip, the screen closing -- is left holding a
  /// controller nobody can use any more. Touching it throws a FlutterError
  /// rather than a CameraException, so it sails past the catch below and
  /// crashes the shutter. Checked after every await that could let the
  /// teardown run.
  bool _stillLive(CameraController controller) =>
      mounted && identical(_controller, controller);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setUpCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _light.detach(_controller);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      _setUpCamera();
    }
  }

  Future<void> _setUpCamera() async {
    setState(() {
      _initialising = true;
      _error = null;
    });

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw CameraException('no_camera', 'No camera found on this device.');
      }

      // Prefer the front camera — this is a selfie flow.
      final front = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      _cameraIndex = front >= 0 ? front : 0;
      await _startController();
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.description ?? context.s.cameraUnavailable);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = context.s.cameraNotOnDevice);
    } finally {
      if (mounted) setState(() => _initialising = false);
    }
  }

  Future<void> _startController() async {
    await _light.detach(_controller);
    await _controller?.dispose();

    final controller = CameraController(
      _cameras[_cameraIndex],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
    await _light.attach(controller);
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2) return;
    setState(() => _cameraIndex = (_cameraIndex + 1) % _cameras.length);
    await _startController();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }

    setState(() => _capturing = true);
    HapticFeedback.mediumImpact();
    try {
      // The plugin cannot stream frames and take a picture at the same time,
      // and leaving the stream running turns the shutter into a silent
      // failure on some devices.
      await _light.detach(controller);
      if (!_stillLive(controller)) return;

      final file = await controller.takePicture();
      if (!mounted) return;
      setState(() {
        _reviewPath = file.path;
        _report = null;
        _inspecting = true;
      });
      // Exposure and focus, read off the pixels here: instant, and it works
      // with no signal. Advisory only, and it runs after the photo is already
      // on screen so the review never waits on it.
      // Exposure and focus first, read off the pixels here: instant, and it
      // works with no signal.
      final local = await PhotoQuality.inspect(file.path);
      if (!mounted) return;

      // Then the part the phone cannot answer -- is there a face, and which
      // way is it pointing. Fails open: no backend or no signal leaves the
      // photo accepted, with the phone's own reading still shown.
      final remote = await _photoCheck.inspect(file.path);
      if (!mounted) return;

      setState(() {
        _report = remote ??
            PhotoReport(issues: [?local]);
        _inspecting = false;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.description ?? context.s.couldNotTakePhoto);
    } catch (error) {
      // The camera can be torn down while takePicture is still in flight, and
      // what comes back then is not a CameraException. Losing the shot is
      // fine; crashing on the client's phone is not.
      debugPrint('CaptureScreen: the shutter was interrupted ($error)');
      if (!mounted) return;
      setState(() => _error = context.s.couldNotTakePhoto);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemOverlayLight,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _reviewPath != null
            ? _ReviewView(
                path: _reviewPath!,
                report: _report,
                checking: _inspecting,
                onRetake: () {
                  setState(() {
                    _reviewPath = null;
                    _report = null;
                  });
                  final controller = _controller;
                  if (controller != null) _light.attach(controller);
                },
                onConfirm: () => Navigator.of(context).pop(_reviewPath),
              )
            : _CameraView(
                controller: _controller,
                light: _light1,
                initialising: _initialising,
                capturing: _capturing,
                error: _error,
                canFlip: _cameras.length > 1,
                available: _cameraAvailable,
                onCapture: _capture,
                onFlip: _flipCamera,
                onClose: () => Navigator.of(context).pop(),
              ),
      ),
    );
  }
}

class _CameraView extends StatelessWidget {
  const _CameraView({
    required this.controller,
    required this.light,
    required this.initialising,
    required this.capturing,
    required this.error,
    required this.canFlip,
    required this.available,
    required this.onCapture,
    required this.onFlip,
    required this.onClose,
  });

  final CameraController? controller;

  /// How the light looks right now, read off the live preview.
  final LightReading light;
  final bool initialising;
  final bool capturing;
  final String? error;
  final bool canFlip;
  final bool available;
  final VoidCallback onCapture;
  final VoidCallback onFlip;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (available)
          _FittedPreview(controller: controller!)
        else
          const ColoredBox(color: Color(0xFF141414)),

        if (available) const FaceGuideOverlay(),

        if (initialising)
          const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(Colors.white),
            ),
          ),

        if (!initialising && !available)
          _CameraUnavailable(message: error),

        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    CircleIconButton(
                      icon: Icons.close_rounded,
                      background: Colors.white.withValues(alpha: 0.16),
                      foreground: Colors.white,
                      onPressed: onClose,
                    ),
                    const Spacer(),
                    if (canFlip)
                      CircleIconButton(
                        icon: Icons.flip_camera_ios_rounded,
                        background: Colors.white.withValues(alpha: 0.16),
                        foreground: Colors.white,
                        onPressed: onFlip,
                      ),
                  ],
                ),
              ),
              if (available)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: AnimatedSwitcher(
                    duration: AppDuration.base,
                    child: Container(
                      // Keyed on the reading so the pill cross-fades when the
                      // light changes instead of the text swapping under it.
                      key: ValueKey(light),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        // Amber, not red: this is a nudge while there is still
                        // time to fix it, not a rejection.
                        color: light == LightReading.fine
                            ? Colors.black.withValues(alpha: 0.42)
                            : const Color(0xFFB4690E).withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Always shown, including when the light is fine.
                          // The meter is reading every frame either way, and
                          // a check that only appears to complain looks like
                          // nagging rather than help.
                          Icon(
                            light == LightReading.fine
                                ? Icons.check_circle_rounded
                                : Icons.wb_sunny_rounded,
                            size: 18,
                            color: light == LightReading.fine
                                ? const Color(0xFF4ADE80)
                                : Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            switch (light) {
                              LightReading.tooDark => context.s.liveTooDark,
                              LightReading.tooBright => context.s.liveTooBright,
                              LightReading.fine => context.s.liveLightGood,
                            },
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              if (available)
                _ShutterBar(capturing: capturing, onCapture: onCapture),
            ],
          ),
        ),
      ],
    );
  }
}

/// Fills the screen without distorting the preview's aspect ratio.
class _FittedPreview extends StatelessWidget {
  const _FittedPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return ClipRect(
      child: OverflowBox(
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.width,
            height: size.width * controller.value.aspectRatio,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

class _ShutterBar extends StatelessWidget {
  const _ShutterBar({
    required this.capturing,
    required this.onCapture,
  });

  final bool capturing;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.6),
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PressableScale(
            scale: 0.9,
            onPressed: capturing ? null : onCapture,
            child: Container(
              height: 84,
              width: 84,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.55),
                  width: 4,
                ),
              ),
              child: AnimatedContainer(
                duration: AppDuration.fast,
                decoration: BoxDecoration(
                  color: capturing ? Colors.white70 : Colors.white,
                  shape: BoxShape.circle,
                ),
                child: capturing
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor:
                              AlwaysStoppedAnimation(AppColors.primary),
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({
    required this.message,
  });

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_rounded,
                size: 54, color: Colors.white54),
            const SizedBox(height: 18),
            Text(
              message ?? context.s.cameraUnavailable,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewView extends StatelessWidget {
  const _ReviewView({
    required this.path,
    required this.report,
    required this.checking,
    required this.onRetake,
    required this.onConfirm,
  });

  final String path;

  /// Everything the checks found, or null while they are still running.
  final PhotoReport? report;

  /// The check has not come back yet.
  final bool checking;

  final VoidCallback onRetake;
  final VoidCallback onConfirm;

  PhotoFinding? get _headline => report?.headline;

  /// The one finding that means the render cannot work at all.
  bool get _noFace => report?.has(PhotoIssue.noFace) ?? false;

  String _issueText(S s) {
    final finding = _headline;
    return finding == null ? '' : photoIssueMessage(s, finding);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(File(path), fit: BoxFit.cover),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.75),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              const Spacer(),
              // A warning, never a block. The check reads brightness and
              // sharpness, not faces, so it can be wrong about a photo that is
              // perfectly usable. The user gets the last word.
              // The whole check, passes included. Someone who took a good
              // photo should still see that the light and the angle were
              // looked at -- otherwise the feature only ever appears when it
              // is complaining, which reads as nagging rather than help.
              if (report != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: _CheckPanel(report: report!),
                ),
              if (_headline != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: _QualityWarning(text: _issueText(context.s)),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _headline == null
                      ? context.s.happyWithPhoto
                      : context.s.useItAnyway,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 26),
                child: Row(
                  children: [
                    // With no face in the frame the render cannot work at
                    // all: the swap has nothing to swap, the previews come
                    // back as stock art and the video is of somebody else.
                    // It stays the user's choice -- the check can be wrong --
                    // but the obvious button becomes the one that helps.
                    Expanded(
                      flex: _noFace ? 2 : 1,
                      child: _noFace
                          ? PrimaryButton(
                              label: context.s.retake,
                              icon: Icons.refresh_rounded,
                              onPressed: onRetake,
                            )
                          : PressableScale(
                              onPressed: onRetake,
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 18),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.md),
                                ),
                                child: Center(
                                  child: Text(
                                    context.s.retake,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: _noFace ? 1 : 2,
                      child: _noFace
                          ? PressableScale(
                              onPressed: onConfirm,
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 18),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.md),
                                ),
                                child: Center(
                                  child: Text(
                                    context.s.continueLabel,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color:
                                          Colors.white.withValues(alpha: 0.82),
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : PrimaryButton(
                        label: context.s.continueLabel,
                        icon: Icons.check_rounded,
                        loading: checking,
                        onPressed: onConfirm,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The exposure or focus suggestion, shown over the photo it is about.
class _QualityWarning extends StatelessWidget {
  const _QualityWarning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_rounded, size: 20, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The photo check, listed line by line over the review photo.
class _CheckPanel extends StatelessWidget {
  const _CheckPanel({required this.report});

  final PhotoReport report;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final lines = photoCheckLines(s, report);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            s.checkTitle.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: Colors.white.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    switch (line.state) {
                      CheckState.good => Icons.check_circle_rounded,
                      CheckState.warning => Icons.error_rounded,
                      CheckState.unknown => Icons.remove_circle_outline_rounded,
                    },
                    size: 17,
                    color: switch (line.state) {
                      CheckState.good => const Color(0xFF4ADE80),
                      CheckState.warning => const Color(0xFFFBBF24),
                      CheckState.unknown => Colors.white54,
                    },
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      line.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.86),
                      ),
                    ),
                  ),
                  Text(
                    line.value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: line.state == CheckState.warning
                          ? const Color(0xFFFBBF24)
                          : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
