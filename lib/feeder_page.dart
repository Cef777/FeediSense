import 'package:flutter/material.dart';
import 'package:another_telephony/telephony.dart';
import 'sms_config.dart';
import 'database_helper.dart';
import 'sms_handler.dart';
import 'models.dart';

class FeederPage extends StatefulWidget {
  const FeederPage({super.key});

  @override
  State<FeederPage> createState() => _FeederPageState();
}

class _FeederPageState extends State<FeederPage> {
  final Telephony _telephony = Telephony.instance;
  final List<TimeOfDay?> _times = List<TimeOfDay?>.filled(4, null);
  final List<TextEditingController> _feedAmountControllers =
      List.generate(4, (_) => TextEditingController());

  final TextEditingController _manualFeedController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Load any previously saved schedules from the local database so the
    // schedule fields persist across app sessions.  This call is
    // asynchronous and returns a Future, but initState cannot be
    // declared async.  We therefore trigger it without awaiting; it will
    // populate the UI once the records are available.
    _loadSavedSchedules();
  }

  // Helper for consistent padding (e.g., 9 becomes '09')
  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  // Load schedules from SQLite and prepopulate the time pickers and
  // amount fields.  The schedules table stores the time in "HH:mm" format
  // and grams as a string.  If a schedule has no time (null), the slot
  // remains empty.  This method safely handles parsing failures and does
  // nothing if an error occurs.
  Future<void> _loadSavedSchedules() async {
    try {
      final saved = await DatabaseHelper.instance.fetchSchedules();
      if (!mounted) return;
      setState(() {
        for (final row in saved) {
          final int id = row['id'] as int;
          final String? timeStr = row['time'] as String?;
          final String grams = row['grams'] as String? ?? '';
          // Update grams text field
          _feedAmountControllers[id].text = grams;
          // Parse the time if available
          if (timeStr != null && timeStr.isNotEmpty) {
            final parts = timeStr.split(':');
            if (parts.length == 2) {
              final int? hh = int.tryParse(parts[0]);
              final int? mm = int.tryParse(parts[1]);
              if (hh != null && mm != null) {
                _times[id] = TimeOfDay(hour: hh, minute: mm);
              }
            }
          }
        }
      });
    } catch (_) {
      // If fetching schedules fails, leave fields empty. Errors are
      // intentionally ignored here to avoid crashing the UI.
    }
  }

  void _syncTime() async {
    final now = DateTime.now();
    // Removed leading zeros to shrink the string length.
    final syncCommand =
        'SYNC:${now.year},${now.month},${now.day},${now.hour},${now.minute},${now.second}';

    await _telephony.sendSms(
      to: SmsConfig.phoneNumber,
      message: syncCommand,
    );

    // Persist a log entry for the manual action.
    await SmsHandler.saveNotification(
      AppNotification(
        level: 'Info',
        message: 'User initiated time synchronization.',
        timestamp: DateTime.now(),
      ),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Time Sync Command Sent: Waiting for RTC_SYNC_OK...'),
        ),
      );
    }
  }

  void _saveSingleSchedule(int index) async {
    if (_times[index] == null || _feedAmountControllers[index].text.isEmpty) {
      _showSnackBar("Please set both time and amount");
      return;
    }

    String hh = _twoDigits(_times[index]!.hour);
    String mm = _twoDigits(_times[index]!.minute);
    String weight = _feedAmountControllers[index].text;

    // Creates the command: S1:1430,10
    String command = 'S${index + 1}:$hh$mm,$weight';

    await _telephony.sendSms(
      to: SmsConfig.phoneNumber,
      message: command,
    );
    // Update our local SQLite schedules table with the new value.
    await DatabaseHelper.instance.updateSchedule(index, '$hh:$mm', weight);

    // Log the save action
    await SmsHandler.saveNotification(
      AppNotification(
        level: 'Info',
        message:
            'User saved schedule slot ${index + 1}: $hh:$mm at $weight g.',
        timestamp: DateTime.now(),
      ),
    );

    _showSnackBar(
        'Sent to Slot ${index + 1}: Waiting for confirmation...');
  }

  void _clearSingleSchedule(int index) async {
    setState(() {
      _times[index] = null;
      _feedAmountControllers[index].clear();
    });

    // Creates the clear command: S1:CLEAR
    String command = 'S${index + 1}:CLEAR';

    await _telephony.sendSms(
      to: SmsConfig.phoneNumber,
      message: command,
    );

    // Remove the schedule from local database by setting both fields to null/empty
    await DatabaseHelper.instance.updateSchedule(index, null, '');

    // Log the clear action
    await SmsHandler.saveNotification(
      AppNotification(
        level: 'Info',
        message: 'User cleared schedule slot ${index + 1}.',
        timestamp: DateTime.now(),
      ),
    );

    _showSnackBar(
        'Cleared Slot ${index + 1}: Waiting for confirmation...');
  }

  void _triggerManualFeed() async {
    String amountText = _manualFeedController.text.trim();

    // Validation: Ensure input is not empty and is a number
    if (amountText.isEmpty) {
      _showSnackBar("Please enter grams first");
      return;
    }

    int? grams = int.tryParse(amountText);
    if (grams == null || grams <= 0) {
      _showSnackBar("Please enter a valid amount");
      return;
    }

    // This sends "CMD_10" if the user typed 10
    final command = 'CMD_$grams';

    await _telephony.sendSms(
      to: SmsConfig.phoneNumber,
      message: command,
    );

    // Log the manual feed request
    await SmsHandler.saveNotification(
      AppNotification(
        level: 'Info',
        message: 'User requested manual feed: $grams g.',
        timestamp: DateTime.now(),
      ),
    );

    _showSnackBar("Manual Feed Command Sent: $grams grams");
  }

  void _triggerDrainOpen() async {
    await _telephony.sendSms(
      to: SmsConfig.phoneNumber,
      message: 'CMD_OPEN',
    );
    await SmsHandler.saveNotification(
      AppNotification(
        level: 'Info',
        message: 'User requested to OPEN drain servos.',
        timestamp: DateTime.now(),
      ),
    );
    _showSnackBar("Open Drain Command Sent: Waiting for hardware confirmation...");
  }

  void _triggerDrainClose() async {
    await _telephony.sendSms(
      to: SmsConfig.phoneNumber,
      message: 'CMD_CLOSE',
    );
    await SmsHandler.saveNotification(
      AppNotification(
        level: 'Info',
        message: 'User requested to CLOSE drain servos.',
        timestamp: DateTime.now(),
      ),
    );
    _showSnackBar("Close Drain Command Sent: Waiting for hardware confirmation...");
  }

  // Helper for snackbars
  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _selectTime(BuildContext context, int index) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _times[index] ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _times[index] = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feeder Control',
            style:
                TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              child: ListTile(
                leading: const Icon(Icons.sync,
                    color: Color(0xFF2563EB)),
                title: const Text('Synchronize RTC Time'),
                subtitle:
                    const Text('Send app time to Arduino DS3231'),
                trailing: ElevatedButton(
                  onPressed: _syncTime,
                  style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFF2563EB)),
                  child: const Text('Sync Time',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Card(
              elevation: 2,
              child: ListTile(
                leading: Icon(Icons.miscellaneous_services,
                    color: Color(0xFF2563EB)),
                title: Text('Manual Feed'),
                subtitle: Text('Feed a specific amount now'),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualFeedController,
                        decoration: const InputDecoration(
                          labelText: 'Amount (g)',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _triggerManualFeed,
                      icon: const Icon(Icons.water_drop,
                          color: Colors.white, size: 18),
                      label: const Text('Feed',
                          style:
                              TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color(0xFF2563EB),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Daily Feeding Schedules',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            for (int i = 0; i < 4; i++)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextButton.icon(
                              onPressed: () =>
                                  _selectTime(context, i),
                              icon: const Icon(Icons.access_time),
                              label: Text(
                                _times[i]?.format(context) ??
                                    'Set Time',
                                style: TextStyle(
                                    color: _times[i] != null
                                        ? Colors.black87
                                        : Colors.grey),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller:
                                  _feedAmountControllers[i],
                              decoration: const InputDecoration(
                                labelText: 'Amt (g)',
                                border: OutlineInputBorder(),
                                contentPadding:
                                    EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 8),
                              ),
                              keyboardType:
                                  TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Dedicated Save and Clear buttons for each session
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () =>
                                _clearSingleSchedule(i),
                            icon: const Icon(Icons.delete,
                                color: Colors.redAccent,
                                size: 18),
                            label: const Text('Clear',
                                style: TextStyle(
                                    color: Colors.redAccent)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () =>
                                _saveSingleSchedule(i),
                            icon: const Icon(Icons.save,
                                color: Colors.white,
                                size: 18),
                            label: Text('Save S${i + 1}',
                                style: const TextStyle(
                                    color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFF10B981),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 20),
            const Text('Hardware Maintenance',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 24),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.build_circle, color: Color(0xFF2563EB)),
                        SizedBox(width: 8),
                        Text('Drain & Clean System', 
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Manually open both the hopper and scale servos to drain leftover feeds or perform maintenance. Remember to close them when done. Remove the tube and provide container for draining.',
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _triggerDrainOpen,
                            icon: const Icon(Icons.lock_open, color: Colors.white, size: 18),
                            label: const Text('Open Servos', style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange, 
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _triggerDrainClose,
                            icon: const Icon(Icons.lock, color: Colors.white, size: 18),
                            label: const Text('Close Servos', style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981), 
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),    
          ],
          
        ),
      ),
    );
  }
}