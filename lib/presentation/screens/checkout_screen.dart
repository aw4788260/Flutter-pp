import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import 'home_screen.dart';

class CheckoutScreen extends StatefulWidget {
  final double amount;

  const CheckoutScreen({super.key, this.amount = 1200});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  bool hasImage = false;
  bool isSuccess = false;
  final TextEditingController _noteController = TextEditingController();

  void _handleSubmit() {
    setState(() => isSuccess = true);
    Timer(const Duration(seconds: 3), () {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (r) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isSuccess) return _buildSuccessView();

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundSecondary,
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                          ),
                          child: const Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow, size: 18),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        "CHECKOUT PORTAL",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  const Icon(LucideIcons.shield, color: AppColors.accentYellow, size: 18),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Amount Banner
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        border: const Border(bottom: BorderSide(color: Colors.white10)),
                        // ✅ Fix: Removed inset: true
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                      ),
                      child: Column(
                        children: [
                          const Text(
                            "PAYABLE AMOUNT",
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 2.0),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "\$${widget.amount}",
                            style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -1.0),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.accentYellow.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(50),
                              border: Border.all(color: AppColors.accentYellow.withOpacity(0.2)),
                            ),
                            child: const Text("VERIFIED", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.accentYellow, letterSpacing: 1.5)),
                          ),
                        ],
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Step 1
                          _buildSectionTitle("STEP 1: CASH TRANSFER"),
                          Container(
                            padding: const EdgeInsets.all(24),
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: AppColors.backgroundSecondary,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withOpacity(0.05)),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: AppColors.backgroundPrimary,
                                            borderRadius: BorderRadius.circular(12),
                                            // ✅ Fix: Removed inset: true
                                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                                          ),
                                          child: const Icon(LucideIcons.smartphone, color: AppColors.accentYellow, size: 24),
                                        ),
                                        const SizedBox(width: 16),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text("CASH NUMBER", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.textSecondary.withOpacity(0.5), letterSpacing: 1.5)),
                                            const Text("010 1234 5678", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontFamily: 'monospace')),
                                          ],
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.backgroundPrimary,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                                      ),
                                      child: const Icon(LucideIcons.copy, color: AppColors.accentYellow, size: 18),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                const Text.rich(
                                  TextSpan(
                                    text: "Pay with InstaPay App: ",
                                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                    children: [
                                      TextSpan(text: "@medo7as", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                                    ]
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),

                          // Step 2
                          _buildSectionTitle("STEP 2: PAYMENT PROVE SCREENSHOT"),
                          if (hasImage)
                            Stack(
                              children: [
                                Container(
                                  height: 200,
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 24),
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Icon(LucideIcons.image, size: 48, color: Colors.white24),
                                ),
                                Positioned(
                                  top: 10, right: 10,
                                  child: GestureDetector(
                                    onTap: () => setState(() => hasImage = false),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(LucideIcons.x, color: Colors.white, size: 16),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            GestureDetector(
                              onTap: () => setState(() => hasImage = true),
                              child: Container(
                                height: 160,
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 24),
                                decoration: BoxDecoration(
                                  color: AppColors.backgroundSecondary.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: AppColors.accentYellow.withOpacity(0.3), style: BorderStyle.solid),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(LucideIcons.upload, size: 32, color: AppColors.accentYellow),
                                    SizedBox(height: 12),
                                    Text("ADD SCREENSHOT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1.5)),
                                  ],
                                ),
                              ),
                            ),

                          // Step 3
                          _buildSectionTitle("STEP 3: OPTIONAL NOTES"),
                          Container(
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: AppColors.backgroundSecondary,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withOpacity(0.05)),
                              // ✅ Fix: Removed inset: true
                              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
                            ),
                            child: TextField(
                              controller: _noteController,
                              maxLines: 4,
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: "Write any additional info here...",
                                hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.6)),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.all(20),
                              ),
                            ),
                          ),

                          // Notice
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.backgroundSecondary,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.05)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text("NOTICE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1.5)),
                                SizedBox(height: 4),
                                Text(
                                  "Manual verification usually takes several hours. You can track your request status in the profile section.",
                                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.5),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: hasImage ? _handleSubmit : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentYellow,
              foregroundColor: AppColors.backgroundPrimary,
              disabledBackgroundColor: AppColors.backgroundSecondary,
              disabledForegroundColor: AppColors.textSecondary.withOpacity(0.5),
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: hasImage ? 10 : 0,
              shadowColor: AppColors.accentYellow.withOpacity(0.3),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (hasImage) const Icon(LucideIcons.checkCircle2, size: 18),
                if (hasImage) const SizedBox(width: 12),
                const Text("SUBMIT PROVE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.accentYellow.withOpacity(0.8), letterSpacing: 1.5),
      ),
    );
  }

  Widget _buildSuccessView() {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accentYellow.withOpacity(0.2)),
                  boxShadow: const [BoxShadow(color: AppColors.accentYellow, blurRadius: 20, spreadRadius: -5)],
                ),
                child: const Icon(LucideIcons.checkCircle, size: 50, color: AppColors.accentYellow),
              ),
              const SizedBox(height: 32),
              const Text(
                "SUBMISSION COMPLETE",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -0.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                "Our finance department will verify your proof within several hours.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 48),
              
              // Progress Line
              Column(
                children: [
                  Container(
                    width: 160, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 100,
                        decoration: BoxDecoration(
                          color: AppColors.accentYellow,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: const [BoxShadow(color: AppColors.accentYellow, blurRadius: 8)],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text("PROCESSING...", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.accentYellow.withOpacity(0.5), letterSpacing: 2.0)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
