import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../app/services_scope.dart';
import '../../services/anonymous_data.dart';
import '../auth/anonymous_rescue_dialog.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Three swipeable slides that explain what NutriScan does before the user
/// fills in their profile.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const List<_OnboardingPageData> _pages = <_OnboardingPageData>[
    _OnboardingPageData(
      icon: Icons.photo_camera_outlined,
      title: 'Scan any meal',
      description:
          'Point your camera at your plate and let NutriScan do the typing '
          'for you. No more searching through long food lists.',
    ),
    _OnboardingPageData(
      icon: Icons.insights_outlined,
      title: 'See the full picture',
      description:
          'Calories, protein, carbohydrates and fat are broken down for every '
          'meal, so you always know what you are eating.',
    ),
    _OnboardingPageData(
      icon: Icons.flag_outlined,
      title: 'Reach your goal',
      description:
          'Tell us about yourself and NutriScan sets daily targets that match '
          'your body and whether you want to lose, maintain or gain weight.',
    ),
  ];

  bool get _isLastPage => _currentPage == _pages.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToNextPage() {
    if (_isLastPage) {
      _startProfileSetup();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _startProfileSetup() {
    Navigator.of(context).pushReplacementNamed(AppRoutes.profileSetup);
  }

  /// For someone who already has an account and wants it back.
  ///
  /// Onboarding is the first thing a device with no session shows, so this is
  /// where recovering an existing account has to be offered - by the time the
  /// profile form has been filled in, an anonymous account already exists.
  Future<void> _openSignIn() async {
    // Onboarding is reached with no session, or with a brand new one, so
    // there is normally nothing to protect and this goes straight through.
    // The check is made rather than assumed: if somebody does arrive here
    // with saved data, they get the same offer as anywhere else.
    final ServicesScope services = ServicesScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final AnonymousData data = await readAnonymousData(
      auth: services.authService,
      appState: AppScope.of(context),
      meals: services.mealRepository,
    );
    if (!mounted) return;

    if (data.isWorthKeeping) {
      final RescueChoice? choice = await showAnonymousRescueDialog(
        context,
        data: data,
      );
      if (!mounted) return;

      switch (choice) {
        case RescueChoice.createAccount:
          await navigator.pushNamed<bool>(AppRoutes.createAccount);
          return;
        case RescueChoice.signInAnyway:
          break;
        case RescueChoice.cancel:
        case null:
          return;
      }
    }

    await navigator.pushNamed(AppRoutes.signIn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: TextButton(
                  onPressed: _startProfileSetup,
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (int index) =>
                    setState(() => _currentPage = index),
                itemBuilder: (BuildContext context, int index) {
                  return _OnboardingPage(data: _pages[index]);
                },
              ),
            ),
            _PageDots(count: _pages.length, activeIndex: _currentPage),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                children: <Widget>[
                  FilledButton(
                    onPressed: _goToNextPage,
                    child: Text(_isLastPage ? 'Get started' : 'Next'),
                  ),
                  TextButton(
                    onPressed: _openSignIn,
                    child: const Text('Already have an account? Sign in'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Content of a single onboarding slide.
class _OnboardingPageData {
  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.data});

  final _OnboardingPageData data;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            height: 180,
            width: 180,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(data.icon, size: 76, color: AppColors.primary),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text(
            data.title,
            style: text.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            data.description,
            style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Small dots that show which slide is visible.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.activeIndex});

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int index = 0; index < count; index++)
          Container(
            height: 8,
            width: index == activeIndex ? 24 : 8,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            decoration: BoxDecoration(
              color: index == activeIndex
                  ? AppColors.primary
                  : AppColors.outline,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
      ],
    );
  }
}
