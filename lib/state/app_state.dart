import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/i18n/strings.dart';
import '../data/models.dart';
import '../data/templates.dart';
import '../services/service_locator.dart';

/// App-wide session + persisted state.
///
/// Small enough that a single [ChangeNotifier] beats pulling in a heavier
/// state-management dependency, and it keeps the iOS build lean.
class AppState extends ChangeNotifier {
  AppState(this._prefs);

  static const _kOnboarded = 'onboarding_complete';
  static const _kFacePhoto = 'face_photo_path';
  static const _kCredits = 'video_credits';
  static const _kCreations = 'creations';
  static const _kHasPurchased = 'has_purchased';
  static const _kLang = 'app_language';

  final SharedPreferences _prefs;

  static Future<AppState> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppState(prefs)
      .._resumePreviews()
      .._checkBackend();
  }

  /// Fill in previews for a photo taken before a backend existed.
  ///
  /// Without this, anyone who already has a saved photo never gets previews —
  /// [_refreshPreviews] otherwise only runs when the photo *changes*, so
  /// connecting a backend to an existing install would appear to do nothing.
  void _resumePreviews() {
    final path = facePhotoPath;
    if (path == null || !ServiceLocator.instance.previewStore.isEmpty) return;
    unawaited(_refreshPreviews(path));
  }

  // ── What the backend can render ───────────────────────────────────────
  void _checkBackend() {
    final backend = ServiceLocator.instance.backend;
    backend.addListener(notifyListeners);
    unawaited(backend.refresh());
  }

  /// False only when the backend has definitely said it has no clip for this
  /// scenario. See [BackendStatus.canRender].
  bool canRender(String templateId) =>
      ServiceLocator.instance.backend.canRender(templateId);

  // ── Language ──────────────────────────────────────────────────────────
  /// Defaults to English rather than the phone's locale: the client sells in
  /// Denmark but demos in English, and a silent locale switch is worse than a
  /// visible toggle the user controls.
  AppLang get lang => AppLang.fromCode(_prefs.getString(_kLang));

  Future<void> setLang(AppLang value) async {
    if (value == lang) return;
    await _prefs.setString(_kLang, value.name);
    notifyListeners();
  }

  // ── Onboarding ────────────────────────────────────────────────────────
  bool get hasOnboarded => _prefs.getBool(_kOnboarded) ?? false;

  Future<void> completeOnboarding() async {
    await _prefs.setBool(_kOnboarded, true);
    notifyListeners();
  }

  // ── The user's face photo ─────────────────────────────────────────────
  String? get facePhotoPath => _prefs.getString(_kFacePhoto);

  bool get hasFacePhoto => (facePhotoPath ?? '').isNotEmpty;

  Future<void> setFacePhoto(String? path) async {
    if (path == null) {
      await _prefs.remove(_kFacePhoto);
    } else {
      await _prefs.setString(_kFacePhoto, path);
    }
    // Cached previews show the *old* face — always discard them alongside.
    await ServiceLocator.instance.previewStore.clear();
    notifyListeners();

    if (path != null) unawaited(_refreshPreviews(path));
  }

  // ── Style previews ────────────────────────────────────────────────────
  double _previewProgress = 1;
  bool _previewsRunning = false;

  /// 0..1 across the whole catalogue. 1 when idle.
  double get previewProgress => _previewProgress;
  bool get previewsRunning => _previewsRunning;

  /// Generate a still of this user in every scenario, in the background.
  ///
  /// Free (Gemini) and entirely optional — a failure just leaves the designed
  /// gradient artwork in place, so nothing in the flow blocks on it.
  Future<void> _refreshPreviews(String facePhotoPath) async {
    final service = ServiceLocator.instance.previews;
    if (!service.enabled || _previewsRunning) return;

    _previewsRunning = true;
    _previewProgress = 0;
    notifyListeners();

    try {
      await for (final batch in service.generate(
        facePhotoPath: facePhotoPath,
        // Only the tiles visible before scrolling. Generating all 40 costs
        // real money per user for art most of them never scroll to.
        templates: TemplateCatalog.previewSet,
      )) {
        _previewProgress = batch.progress;
        notifyListeners();
      }
    } catch (error, stack) {
      debugPrint('Preview generation stopped: $error\n$stack');
    } finally {
      _previewsRunning = false;
      _previewProgress = 1;
      notifyListeners();
    }
  }

  // ── Credits ───────────────────────────────────────────────────────────
  int get credits => _prefs.getInt(_kCredits) ?? 0;

  bool get canGenerate => credits > 0;

  /// Whether the full catalogue is unlocked.
  ///
  /// Keyed on *having ever bought*, not on the current balance: re-locking the
  /// catalogue the moment someone spends their last credit reads as a bug, and
  /// punishes exactly the people who already paid.
  bool get hasUnlockedAll => _prefs.getBool(_kHasPurchased) ?? false;

  /// Free users see real generated art on the handful of tiles visible without
  /// scrolling; the rest are padlocked until they buy.
  bool isTemplateLocked(String templateId) =>
      !hasUnlockedAll && !TemplateCatalog.isFreePreview(templateId);

  Future<void> addCredits(int amount) async {
    await _prefs.setInt(_kCredits, credits + amount);
    // Buying once unlocks the catalogue permanently.
    await _prefs.setBool(_kHasPurchased, true);
    notifyListeners();
  }

  Future<bool> consumeCredit() async {
    if (credits <= 0) return false;
    await _prefs.setInt(_kCredits, credits - 1);
    notifyListeners();
    return true;
  }

  // ── Draft (the video currently being set up) ──────────────────────────
  VideoTemplate? _selectedTemplate;
  String? _customPrompt;
  CreationSource _draftSource = CreationSource.template;

  VideoTemplate? get selectedTemplate => _selectedTemplate;
  String? get customPrompt => _customPrompt;
  CreationSource get draftSource => _draftSource;

  String get draftTitle =>
      _selectedTemplate?.title ??
      (_customPrompt?.isNotEmpty ?? false
          ? _customPrompt!
          : S(lang).yourVideo);

  String get draftPrompt {
    final base = _selectedTemplate?.prompt ?? '';
    final custom = _customPrompt?.trim() ?? '';
    if (base.isEmpty) return custom;
    if (custom.isEmpty) return base;
    return '$base. $custom';
  }

  void selectTemplate(VideoTemplate? template) {
    _selectedTemplate = template;
    _draftSource = CreationSource.template;
    notifyListeners();
  }

  void setCustomPrompt(String? prompt, {CreationSource? source}) {
    _customPrompt = prompt;
    if (source != null) _draftSource = source;
    notifyListeners();
  }

  void clearDraft() {
    _selectedTemplate = null;
    _customPrompt = null;
    _draftSource = CreationSource.template;
    notifyListeners();
  }

  // ── Library ───────────────────────────────────────────────────────────
  List<Creation> get creations {
    final raw = _prefs.getStringList(_kCreations) ?? const [];
    return raw
        .map((e) => Creation.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> addCreation(Creation creation) async {
    final raw = _prefs.getStringList(_kCreations) ?? <String>[];
    raw.add(jsonEncode(creation.toJson()));
    await _prefs.setStringList(_kCreations, raw);
    notifyListeners();
  }

  Future<void> removeCreation(String id) async {
    final kept = creations
        .where((c) => c.id != id)
        .map((c) => jsonEncode(c.toJson()))
        .toList();
    await _prefs.setStringList(_kCreations, kept);
    notifyListeners();
  }
}
