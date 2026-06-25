import 'package:flutter/material.dart';
import 'package:another_telephony/telephony.dart';
import 'sms_config.dart';
import 'sms_handler.dart';
import 'models.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final Telephony _telephony = Telephony.instance;
  bool _isUpdating = false;

  Future<void> _requestUpdate() async {
    bool? granted = await _telephony.requestPhoneAndSmsPermissions;
    
    if (!mounted) return;

    if (granted != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SMS permission required.')),
      );
      return;
    }

    setState(() => _isUpdating = true);

    try {
      await _telephony.sendSms(
        to: SmsConfig.phoneNumber,
        message: "CMD_0000",
        // We removed subscriptionId entirely so Android handles the SIM routing safely
        statusListener: (dynamic status) {
          if (status.toString().toLowerCase().contains('sent') && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Update request sent.')),
            );
          }
        },
      );

      // CHANGED: Use the new saveNotification method to store in SQLite persistently
      await SmsHandler.saveNotification(AppNotification(
        level: 'Info',
        message: 'Requested latest sensor readings',
        timestamp: DateTime.now(),
      ));
      
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Water Quality Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: SmsHandler.updateNotifier,
        builder: (context, value, child) {
          bool hasData = SmsHandler.history.isNotEmpty;
          SensorReading? latest = hasData ? SmsHandler.history.last : null;
          
          int risk = hasData ? WaterQualityEvaluator.evaluateRisk(latest!.temp, latest.ph, latest.doLevel) : 1;

          String tempDisplay = hasData ? '${latest!.temp.toStringAsFixed(1)}°C' : '--';
          String phDisplay = hasData ? latest!.ph.toStringAsFixed(1) : '--';
          String doDisplay = hasData ? latest!.doLevel.toStringAsFixed(1) : '--';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                _buildStatusCard(hasData, risk),
                const SizedBox(height: 24),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  children: [
                    _buildDetailItem(Icons.thermostat, 'Temp', tempDisplay),
                    _buildDetailItem(Icons.opacity, 'pH', phDisplay),
                    _buildDetailItem(Icons.waves, 'Oxygen', doDisplay),
                  ],
                ),
                const SizedBox(height: 24),
                if (hasData) _buildNotesSection(risk),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isUpdating ? null : _requestUpdate,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: Text(
                      _isUpdating ? 'Requesting...' : 'Request Latest Readings',
                      style: const TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  Widget _buildStatusCard(bool hasData, int risk) {
    Color statusColor = !hasData ? Colors.grey : (risk == 3 ? Colors.red : (risk == 2 ? Colors.orange : Colors.green));
    IconData statusIcon = !hasData ? Icons.sync : (risk == 3 ? Icons.warning : (risk == 2 ? Icons.info_outline : Icons.check_circle));
    String statusText = !hasData ? 'Awaiting Prototype Data' : WaterQualityEvaluator.getStatusString(risk);

    return Container(
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withValues(alpha: 0.5))
      ),
      child: Column(
        children: [
          Icon(statusIcon, color: statusColor, size: 48),
          const SizedBox(height: 8),
          Text(statusText, style: TextStyle(fontWeight: FontWeight.bold, color: statusColor, fontSize: 16), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildNotesSection(int risk) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6, 
            offset: const Offset(0, 4)
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.notes, color: Colors.blue, size: 20),
              SizedBox(width: 8),
              Text('System Assessment & Notes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            WaterQualityEvaluator.getFarmerAdvice(risk),
            style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(IconData icon, String title, String value) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.blue),
          Text(title, style: const TextStyle(fontSize: 12)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }
}

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