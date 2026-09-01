import 'dart:async';

import '../data/models.dart';

class PurchaseResult {
  const PurchaseResult({
    required this.success,
    required this.creditsGranted,
    this.cancelled = false,
    this.error,
  });

  const PurchaseResult.cancelled()
      : success = false,
        creditsGranted = 0,
        cancelled = true,
        error = null;

  final bool success;
  final int creditsGranted;
  final bool cancelled;
  final String? error;
}

/// StoreKit sits behind this interface so the paywall UI never imports a
/// payment SDK directly. To go live, implement this with `in_app_purchase`
/// and register it in `ServiceLocator` — no screen changes required.
abstract interface class PurchaseService {
  List<PricingPlan> get plans;

  Future<PurchaseResult> purchase(PricingPlan plan);

  Future<PurchaseResult> restore();
}

class MockPurchaseService implements PurchaseService {
  @override
  List<PricingPlan> get plans => const [
        PricingPlan(
          productId: 'com.funnyyou.video.single',
          title: '1 video',
          priceLabel: '39 kr',
          videoCount: 1,
          subtitle: 'Try it once',
          perVideoLabel: '39 kr per video',
        ),
        PricingPlan(
          productId: 'com.funnyyou.video.pack5',
          title: '5 videos',
          priceLabel: '129 kr',
          videoCount: 5,
          subtitle: 'Our most popular pack',
          badge: 'Save 34%',
          perVideoLabel: '26 kr per video',
          isBestValue: true,
        ),
        PricingPlan(
          productId: 'com.funnyyou.video.pack15',
          title: '15 videos',
          priceLabel: '299 kr',
          videoCount: 15,
          subtitle: 'Best for the whole family',
          badge: 'Save 49%',
          perVideoLabel: '20 kr per video',
        ),
      ];

  @override
  Future<PurchaseResult> purchase(PricingPlan plan) async {
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    return PurchaseResult(success: true, creditsGranted: plan.videoCount);
  }

  @override
  Future<PurchaseResult> restore() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return const PurchaseResult(success: true, creditsGranted: 0);
  }
}
