import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../core/constants/app_colors.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;
  
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("App Started - Splash Screen");

    // 1. Bounce Animation for Icon (animate-bounce equivalent)
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _bounceAnimation = Tween<double>(begin: 0.0, end: 15.0).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );

    // 2. Progress Bar Animation (2 seconds)
    _progressController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..forward();

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeInOut),
    );

    // Navigate after 2.5 seconds (matching React timer)
    Timer(const Duration(milliseconds: 2500), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    });
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Center Content
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Bouncing Icon Container
              AnimatedBuilder(
                animation: _bounceAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, -_bounceAnimation.value),
                    child: child,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(32), // p-8
                  margin: const EdgeInsets.only(bottom: 32), // mb-8
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(24), // rounded-m3-xl
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 25,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    LucideIcons.graduationCap,
                    size: 80,
                    color: AppColors.accentYellow,
                    // Note: Flutter standard shadows on Icon are tricky, implied by design
                  ),
                ),
              ),

              // Title "MeD O7aS"
              const Text(
                "MeD O7aS",
                style: TextStyle(
                  fontSize: 36, // text-4xl
                  fontWeight: FontWeight.w900, // font-black
                  color: AppColors.textPrimary,
                  letterSpacing: -1.0, // tracking-tighter
                ),
              ),
              const SizedBox(height: 8),

              // Subtitle
              const Text(
                "EMPOWERING YOUR GROWTH",
                style: TextStyle(
                  fontSize: 10, // text-[10px]
                  fontWeight: FontWeight.bold,
                  color: AppColors.accentOrange,
                  letterSpacing: 4.0, // tracking-[0.4em]
                ),
              ),
            ],
          ),

          // Bottom Progress
          Positioned(
            bottom: 80, // bottom-20
            child: Column(
              children: [
                // Custom Progress Bar
                Container(
                  width: 160, // w-40
                  height: 4,  // h-1
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: AnimatedBuilder(
                    animation: _progressAnimation,
                    builder: (context, child) {
                      return FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: 0.4 + (0.6 * _progressAnimation.value), // Simulating movement
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.accentYellow,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accentYellow.withOpacity(0.6),
                                blurRadius: 12,
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                
                // Loading Text
                Text(
                  "LOADING SYSTEM",
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900, // font-black
                    letterSpacing: 6.0, // tracking-[0.6em]
                    color: AppColors.textSecondary.withOpacity(0.3),
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
