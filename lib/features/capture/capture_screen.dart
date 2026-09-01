import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/i18n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
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

  bool get _cameraAvailable => _controller?.value.isInitialized ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setUpCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      final file = await controller.takePicture();
      if (!mounted) return;
      setState(() => _reviewPath = file.path);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.description ?? context.s.couldNotTakePhoto);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _pickFromLibrary() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 92,
    );
    if (file == null || !mounted) return;
    setState(() => _reviewPath = file.path);
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
                onRetake: () => setState(() => _reviewPath = null),
                onConfirm: () => Navigator.of(context).pop(_reviewPath),
              )
            : _CameraView(
                controller: _controller,
                initialising: _initialising,
                capturing: _capturing,
                error: _error,
                canFlip: _cameras.length > 1,
                available: _cameraAvailable,
                onCapture: _capture,
                onFlip: _flipCamera,
                onPickLibrary: _pickFromLibrary,
                onClose: () => Navigator.of(context).pop(),
              ),
      ),
    );
  }
}

class _CameraView extends StatelessWidget {
  const _CameraView({
    required this.controller,
    required this.initialising,
    required this.capturing,
    required this.error,
    required this.canFlip,
    required this.available,
    required this.onCapture,
    required this.onFlip,
    required this.onPickLibrary,
    required this.onClose,
  });

  final CameraController? controller;
  final bool initialising;
  final bool capturing;
  final String? error;
  final bool canFlip;
  final bool available;
  final VoidCallback onCapture;
  final VoidCallback onFlip;
  final VoidCallback onPickLibrary;
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
          _CameraUnavailable(message: error, onPickLibrary: onPickLibrary),

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
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      context.s.faceInCircle,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              if (available)
                _ShutterBar(
                  capturing: capturing,
                  onCapture: onCapture,
                  onPickLibrary: onPickLibrary,
                ),
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
    required this.onPickLibrary,
  });

  final bool capturing;
  final VoidCallback onCapture;
  final VoidCallback onPickLibrary;

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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 68,
            child: PressableScale(
              onPressed: onPickLibrary,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 46,
                    width: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.photo_library_rounded,
                        size: 22, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.s.photosLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
          const SizedBox(width: 68),
        ],
      ),
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({
    required this.message,
    required this.onPickLibrary,
  });

  final String? message;
  final VoidCallback onPickLibrary;

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
            const SizedBox(height: 24),
            SecondaryButton(
              label: context.s.chooseAPhotoInstead,
              icon: Icons.photo_library_rounded,
              expand: false,
              onPressed: onPickLibrary,
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
    required this.onRetake,
    required this.onConfirm,
  });

  final String path;
  final VoidCallback onRetake;
  final VoidCallback onConfirm;

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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  context.s.happyWithPhoto,
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
                    Expanded(
                      child: PressableScale(
                        onPressed: onRetake,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 18),
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
                      flex: 2,
                      child: PrimaryButton(
                        label: context.s.continueLabel,
                        icon: Icons.check_rounded,
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
