import 'package:flutter/material.dart';
import 'feed_calculator_page.dart';
import 'feeder_page.dart';
import 'report_page.dart';
import 'notifications_page.dart';
import 'analytics_page.dart';
import 'about_page.dart';
import 'sms_handler.dart';

void main() async {
  // Ensure Flutter bindings are initialized before any plugin interaction
  WidgetsFlutterBinding.ensureInitialized(); 

  await SmsHandler.init();
  
  runApp(const FeediSenseApp());
}

class FeediSenseApp extends StatelessWidget {
  const FeediSenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FeediSense',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          primary: const Color(0xFF2563EB),
          secondary: const Color(0xFF10B981),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      ),
      home: const MainMenuPage(),
    );
  }
}

class MainMenuPage extends StatefulWidget {
  const MainMenuPage({super.key});

  @override
  State<MainMenuPage> createState() => _MainMenuPageState();
}

class _MainMenuPageState extends State<MainMenuPage> {
  
  @override
  void initState() {
    super.initState();
    // Initialize SMS listening
    SmsHandler.init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220.0,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Image.asset(
                        'assets/4206 LOGO FEEDISENSE-modified.png',
                        height: 80,
                        errorBuilder: (context, error, stackTrace) => 
                          const Icon(Icons.water_drop, size: 60, color: Color(0xFF2563EB)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'FeediSense',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildQuickStatus(),
                  const SizedBox(height: 24),
                  const Text(
                    'Management Menu',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.1,
                    children: [
                      _MenuCard(
                        icon: Icons.calculate_outlined,
                        label: 'Feed Calculator',
                        color: Colors.blue,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const FeedCalculatorPage())),
                      ),
                      _MenuCard(
                        icon: Icons.settings_input_component,
                        label: 'Feeder Control',
                        color: Colors.orange,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const FeederPage())),
                      ),
                      _MenuCard(
                        icon: Icons.assignment_outlined,
                        label: 'Water Report',
                        color: Colors.teal,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const ReportPage())),
                      ),
                      _MenuCard(
                        icon: Icons.insights_outlined,
                        label: 'Analytics',
                        color: Colors.purple,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AnalyticsPage())),
                      ),
                      _MenuCard(
                        icon: Icons.notifications_active_outlined,
                        label: 'Notifications',
                        color: Colors.redAccent,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const NotificationsPage())),
                      ),
                      _MenuCard(
                        icon: Icons.info_outline,
                        label: 'About System',
                        color: Colors.grey,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AboutPage())),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatus() {
    return ValueListenableBuilder<int>(
      valueListenable: SmsHandler.updateNotifier,
      builder: (context, value, child) {
        bool hasData = SmsHandler.history.isNotEmpty;
        int risk = 1;
        
        if (hasData) {
          final latest = SmsHandler.history.last;
          risk = WaterQualityEvaluator.evaluateRisk(latest.temp, latest.ph, latest.doLevel);
        }

        Color statusColor = !hasData ? Colors.grey : (risk == 3 ? Colors.red : (risk == 2 ? Colors.orange : Colors.green));
        IconData statusIcon = !hasData ? Icons.sync : (risk == 3 ? Icons.warning : (risk == 2 ? Icons.info_outline : Icons.check_circle));
        String statusText = !hasData ? 'Waiting for Data...' : WaterQualityEvaluator.getStatusString(risk);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
          ),
          child: Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 30),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Prototype Connection', style: TextStyle(color: Colors.black54, fontSize: 12)),
                    Text(statusText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ),
              Text(hasData ? 'ACTIVE' : 'PENDING', style: TextStyle(color: statusColor, fontWeight: FontWeight.w900)),
            ],
          ),
        );
      }
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MenuCard({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(height: 12),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper class to evaluate water quality risk levels
class WaterQualityEvaluator {
  static int evaluateRisk(double temp, double ph, double doLevel) {
    // 1. Evaluate DO Risk
    int doRisk = (doLevel > 5.0) ? 1 : (doLevel < 3.0) ? 3 : 2;
    
    // 2. Evaluate pH Risk
    int phRisk = (ph < 5.5 || ph > 10.0) ? 3 : 
                 ((ph >= 5.5 && ph <= 6.4) || (ph >= 8.6 && ph <= 10.0)) ? 2 : 1;
                 
    // 3. Evaluate Temp Risk
    int tRisk = (temp < 20.0 || temp > 35.0) ? 3 : 
                (temp >= 24.0 && temp <= 32.0) ? 1 : 2;

    // 4. Combine just like the Arduino
    if (doRisk == 3 || phRisk == 3 || tRisk == 3) {
      return 3; // Critical
    } else if (doRisk == 2 || phRisk == 2 || tRisk == 2) {
      return 2; // Warning
    } else {
      return 1; // Safe
    }
  }

  static String getStatusString(int risk) {
    switch (risk) {
      case 3: return 'Critical Condition';
      case 2: return 'Caution Required';
      default: return 'Optimal Conditions';
    }
  }

  static String getFarmerAdvice(int risk) {
    switch (risk) {
      case 3:
        return "CRITICAL: Water parameters have reached dangerous levels. Feeding is aborted. Immediate intervention required.";
      case 2:
        return "WARNING: Water parameters are drifting from the ideal range. Feeds are reduced by 20% to prevent further degradation.";
      default:
        return "The water quality is currently within optimal ranges for fish health. Standard feeding schedule active.";
    }
  }
}
