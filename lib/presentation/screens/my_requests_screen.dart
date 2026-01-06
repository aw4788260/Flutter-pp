import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';

// Types
enum OrderStatus { progressing, accepted, denied }

class OrderRequest {
  final String id;
  final String courseTitle;
  final String date;
  final OrderStatus status;
  final int amount;
  final String? reason;

  OrderRequest({required this.id, required this.courseTitle, required this.date, required this.status, required this.amount, this.reason});
}

// Mock Data
final List<OrderRequest> mockOrders = [
  OrderRequest(id: 'REQ-98210', courseTitle: 'Modern UI Design', date: '2023-11-15', status: OrderStatus.progressing, amount: 500),
  OrderRequest(id: 'REQ-77412', courseTitle: 'Advanced React Architecture', date: '2023-11-10', status: OrderStatus.accepted, amount: 800),
  OrderRequest(id: 'REQ-41002', courseTitle: 'Graphic Design Masterclass', date: '2023-11-05', status: OrderStatus.denied, amount: 300, reason: 'Receipt image not clear. Please rescan.'),
];

class MyRequestsScreen extends StatelessWidget {
  const MyRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
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
                      child: const Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow, size: 20),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    "ORDER REQUESTS",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),

            // List
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                itemCount: mockOrders.length,
                itemBuilder: (context, index) {
                  final order = mockOrders[index];
                  return _buildOrderCard(order);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(OrderRequest order) {
    // Style logic
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (order.status) {
      case OrderStatus.progressing:
        statusColor = AppColors.accentYellow;
        statusIcon = LucideIcons.clock;
        statusText = "Still Progressing";
        break;
      case OrderStatus.accepted:
        statusColor = AppColors.success;
        statusIcon = LucideIcons.checkCircle;
        statusText = "Accepted";
        break;
      case OrderStatus.denied:
        statusColor = AppColors.accentOrange; // or Error color
        statusIcon = LucideIcons.xCircle;
        statusText = "Denied";
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(20), // rounded-m3-xl
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.hash, size: 12, color: AppColors.accentYellow),
                  const SizedBox(width: 4),
                  Text(order.id, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1.5)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.backgroundPrimary,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, inset: true)],
                ),
                child: Row(
                  children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 6),
                    Text(statusText.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: statusColor, letterSpacing: 1.0)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Title
          Text(
            order.courseTitle.toUpperCase(),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary, letterSpacing: -0.5),
          ),
          const SizedBox(height: 16),

          // Footer info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(order.date, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary.withOpacity(0.5), letterSpacing: 1.5)),
              Text("\$${order.amount}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.accentYellow)),
            ],
          ),

          // Denied Reason
          if (order.status == OrderStatus.denied && order.reason != null)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.backgroundPrimary,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, inset: true)],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(LucideIcons.alertCircle, size: 16, color: AppColors.accentOrange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("REASON FOR REJECTION", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.accentOrange, letterSpacing: 1.5)),
                        const SizedBox(height: 4),
                        Text(order.reason!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
                      ],
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
