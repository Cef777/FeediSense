import 'database_helper.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'sms_handler.dart';
import 'models.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  void _clearNotifications() async {
    // Clear from RAM
    SmsHandler.notifications.clear();
    // Clear from Database
    await DatabaseHelper.instance.clearNotifications();

    SmsHandler.updateNotifier.value++;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notifications cleared.')),
      );
    }
  }

  Future<void> _exportData() async {
    final List<SensorReading> data = SmsHandler.history;

    if (data.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No sensor data to export.')),
      );
      return;
    }

    StringBuffer csv = StringBuffer();
    csv.writeln('Timestamp,Temperature(C),pH,DO(mg/L)');
    for (var reading in data) {
      csv.writeln(
          '${reading.timestamp.toIso8601String()},${reading.temp},${reading.ph},${reading.doLevel}');
    }

    try {
      final directory = await getTemporaryDirectory();
      final String path = '${directory.path}/pond_data_export.csv';
      final File file = File(path);
      await file.writeAsString(csv.toString());

      await Share.shareXFiles(
        [XFile(path)],
        subject: 'FeediSense Water Quality Data',
        text: 'Sharing historical sensor data from my pond.',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('History & Data',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          backgroundColor: const Color(0xFF2563EB),
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Notifications', icon: Icon(Icons.notifications)),
              Tab(text: 'Sensor Data', icon: Icon(Icons.analytics)),
            ],
          ),
        ),
        body: ValueListenableBuilder<int>(
            valueListenable: SmsHandler.updateNotifier,
            builder: (context, value, child) {
              return TabBarView(
                children: [
                  // TAB 1: NOTIFICATIONS (Newest First)
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: SmsHandler.notifications.isEmpty
                                ? null
                                : _clearNotifications,
                            icon: const Icon(Icons.clear_all),
                            label: const Text('Clear All'),
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.red),
                          ),
                        ),
                      ),
                      Expanded(
                        child: SmsHandler.notifications.isEmpty
                            ? const Center(
                                child: Text('No notifications history.'))
                            : ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: SmsHandler.notifications.length,
                                separatorBuilder: (_, __) => const Divider(),
                                itemBuilder: (context, index) {
                                  // REVERSE INDEX: Newest at the top
                                  final reversedIndex =
                                      SmsHandler.notifications.length -
                                          1 -
                                          index;
                                  final item =
                                      SmsHandler.notifications[reversedIndex];
                                  return ListTile(
                                    leading: Icon(
                                      Icons.circle,
                                      color: item.level == 'High'
                                          ? Colors.red
                                          : item.level == 'Medium'
                                              ? Colors.orange
                                              : item.level == 'Low'
                                                  ? Colors
                                                      .green // <-- Success events are now Green!
                                                  : Colors
                                                      .blue, // <-- Info/general events stay Blue
                                      size: 16,
                                    ),
                                    title: Text(item.message,
                                        style: const TextStyle(fontSize: 14)),
                                    subtitle:
                                        Text(_formatTimestamp(item.timestamp)),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),

                  // TAB 2: SENSOR DATA (Newest First)
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            onPressed:
                                SmsHandler.history.isEmpty ? null : _exportData,
                            icon: const Icon(Icons.download),
                            label: const Text('Export CSV'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: SmsHandler.history.isEmpty
                            ? const Center(
                                child: Text('No sensor data available.'))
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: SmsHandler.history.length,
                                itemBuilder: (context, index) {
                                  // REVERSE INDEX: Newest at the top
                                  final reversedIndex =
                                      SmsHandler.history.length - 1 - index;
                                  final data =
                                      SmsHandler.history[reversedIndex];
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              'Time: ${_formatTimestamp(data.timestamp)}',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.grey)),
                                          const SizedBox(height: 8),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text('Temp: ${data.temp}°C'),
                                              Text('pH: ${data.ph}'),
                                              Text('DO: ${data.doLevel} mg/L'),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ],
              );
            }),
      ),
    );
  }

  static String _formatTimestamp(DateTime time) {
    final String month = time.month.toString().padLeft(2, '0');
    final String day = time.day.toString().padLeft(2, '0');
    final int hourInt = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final String hour = hourInt.toString();
    final String minute = time.minute.toString().padLeft(2, '0');
    final String period = time.hour < 12 ? 'AM' : 'PM';
    return '$month/$day/${time.year} $hour:$minute $period';
  }
}
