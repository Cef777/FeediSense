import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:another_telephony/telephony.dart';
import 'database_helper.dart';
import 'models.dart';
import 'sms_config.dart';

@pragma('vm:entry-point')
void backgroundMessageHandler(SmsMessage message) async {
  SmsHandler.handleIncomingSms(message, isBackground: true);
}

class SmsHandler {
  static List<SensorReading> history = [];
  static List<AppNotification> notifications = [];
  static List<FeedEvent> feedHistory = [];
  static int? lastCommandedFeed;

  static final ValueNotifier<int> updateNotifier = ValueNotifier(0);
  static final Telephony _telephony = Telephony.instance;

  static final List<Map<String, dynamic>> _smsQueue = [];
  static bool _isProcessingQueue = false;

  static Future<void> loadLocalData() async {
    history = await DatabaseHelper.instance.fetchHistory();
    notifications = await DatabaseHelper.instance.fetchNotifications();
    feedHistory = await DatabaseHelper.instance.fetchFeedEvents();
    updateNotifier.value++;
  }

  static Future<void> saveNotification(
    AppNotification note, {
    bool isBackground = false,
  }) async {
    if (!isBackground) notifications.add(note);
    await DatabaseHelper.instance.insertNotification(note);
    if (!isBackground) updateNotifier.value++;
  }

  static bool _isFromPrototype(String? senderAddress) {
    if (senderAddress == null) return false;

    final String target =
        SmsConfig.phoneNumber.replaceAll(RegExp(r'\D'), '');
    final String incoming =
        senderAddress.replaceAll(RegExp(r'\D'), '');

    if (target.isEmpty) return true;

    if (incoming.length >= 10 && target.length >= 10) {
      return incoming
          .endsWith(target.substring(target.length - 10));
    }

    return incoming == target;
  }

  static void handleIncomingSms(
    SmsMessage message, {
    bool isBackground = false,
  }) {
    if (!_isFromPrototype(message.address)) {
      developer.log(
        'Ignored SMS from unknown number: ${message.address}',
        name: 'SmsHandler',
      );
      return;
    }

    if (message.body == null || message.body!.trim().isEmpty)
      return;

    _smsQueue.add({
      'body': message.body!.trim(),
      'isBackground': isBackground,
    });
    _processNextInQueue();
  }

  static Future<void> syncMissedMessages() async {
    developer.log('Running Catch-up Sync...', name: 'SmsHandler');

    DateTime? latestRecord;
    if (notifications.isNotEmpty) {
      latestRecord = notifications.last.timestamp; 
    }

    final List<SmsMessage> inboxMessages = await _telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      filter: SmsFilter.where(SmsColumn.ADDRESS).equals(SmsConfig.phoneNumber),
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.ASC)],
    );

    int recoveredCount = 0;
    for (var msg in inboxMessages) {
      if (msg.date != null && msg.body != null) {
        DateTime msgDate = DateTime.fromMillisecondsSinceEpoch(msg.date!);
        
        if (latestRecord == null || msgDate.isAfter(latestRecord)) {
          _smsQueue.add({
            'body': msg.body!.trim(),
            'isBackground': false, 
          });
          recoveredCount++;
        }
      }
    }
    
    if (recoveredCount > 0) {
      developer.log('Recovered $recoveredCount missed messages!', name: 'SmsHandler');
      _processNextInQueue();
    }
  }

  static Future<void> _processNextInQueue() async {
    if (_isProcessingQueue || _smsQueue.isEmpty) return;

    _isProcessingQueue = true;
    try {
      final task = _smsQueue.removeAt(0);
      await _processSms(
        task['body'] as String,
        isBackground: task['isBackground'] as bool,
      );
    } catch (e) {
      developer.log('Error processing SMS queue: $e',
          name: 'SmsHandler');
    } finally {
      _isProcessingQueue = false;
      if (_smsQueue.isNotEmpty) {
        _processNextInQueue();
      }
    }
  }

  static Future<void> _recordFeedEvent(
    int grams,
    DateTime now, {
    required bool isBackground,
    String mode = 'Unknown',
    String status = 'Success',
    String reason = 'None',
  }) async {
    final double t = history.isNotEmpty ? history.last.temp : 0;
    final double p = history.isNotEmpty ? history.last.ph : 0;
    final double d = history.isNotEmpty ? history.last.doLevel : 0;

    final event = FeedEvent(
      grams: grams,
      temp: t,
      ph: p,
      doLevel: d,
      timestamp: now,
      mode: mode,       
      status: status,   
      reason: reason,   
    );

    if (!isBackground) feedHistory.add(event);
    await DatabaseHelper.instance.insertFeedEvent(event);
  }

  static Future<void> _processFeedMessage(
    List<String> parts,
    DateTime now, {
    required bool isBackground,
  }) async {
    if (parts.length < 2) {
      await saveNotification(
        AppNotification(
            level: 'Info',
            message: parts.join(','),
            timestamp: now),
        isBackground: isBackground,
      );
      return;
    }

    final String action = parts[1].toUpperCase().trim();
    final String rawMode = parts.length > 2 ? parts[2].toUpperCase().trim() : 'UNKNOWN';

    // --- SMART MODE DETECTION ---
    // Evaluates the raw SMS mode or deduces it from the app state if the hardware omitted it.
    String evaluatedMode = 'Unknown';
    if (rawMode == 'SCHED') {
      evaluatedMode = 'Scheduled';
    } else if (rawMode == 'MANUAL') {
      evaluatedMode = 'Manual';
    } else {
      if (lastCommandedFeed != null) {
        evaluatedMode = 'Manual';
      } else {
        evaluatedMode = 'Scheduled';
      }
    }

    // --- 1. REDUCED FEEDING ---
    if (action == 'REDUCED') {
      if (rawMode == 'SCHED' && parts.length >= 7) {
        final String session = parts[3];
        final String time = parts[4];
        final String original = parts[5];
        final int reduced = int.tryParse(parts[6]) ?? 0;
        
        await _recordFeedEvent(reduced, now, isBackground: isBackground, mode: evaluatedMode, status: 'Reduced', reason: 'Water risk medium');
        await saveNotification(
          AppNotification(level: 'Medium', message: 'Scheduled feeding adjusted: Session $session at $time reduced from $original g to $reduced g because water risk is medium.', timestamp: now),
          isBackground: isBackground,
        );
        return;
      }

      if (rawMode == 'MANUAL' && parts.length >= 5) {
        final String original = parts[3];
        final int reduced = int.tryParse(parts[4]) ?? 0;
        
        await _recordFeedEvent(reduced, now, isBackground: isBackground, mode: evaluatedMode, status: 'Reduced', reason: 'Water risk medium');
        await saveNotification(
          AppNotification(level: 'Medium', message: 'Manual feeding adjusted from $original g to $reduced g because water risk is medium.', timestamp: now),
          isBackground: isBackground,
        );
        return;
      }
    }

    // --- 2. DONE (SUCCESS) FEEDING ---
    if (action == 'DONE') {
      if (rawMode == 'SCHED' && parts.length >= 6) {
        final String session = parts[3];
        final String time = parts[4];
        final int grams = int.tryParse(parts[5]) ?? 0;

        await _recordFeedEvent(grams, now, isBackground: isBackground, mode: evaluatedMode, status: 'Success', reason: 'None');
        await saveNotification(
          AppNotification(level: 'Low', message: 'Scheduled feeding done: Session $session at $time, $grams g dispensed.', timestamp: now),
          isBackground: isBackground,
        );
        lastCommandedFeed = null;
        return;
      }

      if (rawMode == 'MANUAL' && parts.length >= 4) {
        final int grams = int.tryParse(parts[3]) ?? lastCommandedFeed ?? 0;
        await _recordFeedEvent(grams, now, isBackground: isBackground, mode: evaluatedMode, status: 'Success', reason: 'None');
        await saveNotification(
          AppNotification(level: 'Low', message: 'Manual feeding done: $grams g dispensed.', timestamp: now),
          isBackground: isBackground,
        );
        lastCommandedFeed = null;
        return;
      }
    }

    // --- 3. PARTIAL FEEDING ---
    if (action == 'PARTIAL') {
      if (rawMode == 'SCHED' && parts.length >= 8) {
        final String session = parts[3];
        final String time = parts[4];
        final String target = parts[5];
        final int dispensed = int.tryParse(parts[6]) ?? 0;
        final String reason = parts[7].replaceAll('_', ' ');

        await _recordFeedEvent(dispensed, now, isBackground: isBackground, mode: evaluatedMode, status: 'Partial', reason: reason);
        await saveNotification(
          AppNotification(level: 'Medium', message: 'Scheduled feed partial: Session $session at $time. Dispensed $dispensed g of $target g. Reason: $reason.', timestamp: now),
          isBackground: isBackground,
        );
        return;
      }

      if (rawMode == 'MANUAL' && parts.length >= 6) {
        final String target = parts[3];
        final int dispensed = int.tryParse(parts[4]) ?? 0;
        final String reason = parts[5].replaceAll('_', ' ');

        await _recordFeedEvent(dispensed, now, isBackground: isBackground, mode: evaluatedMode, status: 'Partial', reason: reason);
        await saveNotification(
          AppNotification(level: 'Medium', message: 'Manual feed partial. Dispensed $dispensed g of $target g. Reason: $reason.', timestamp: now),
          isBackground: isBackground,
        );
        lastCommandedFeed = null;
        return;
      }
    }

    // --- 4. ABORTED FEEDING ---
    if (action == 'ABORTED') {
      if (rawMode == 'SCHED' && parts.length >= 6) {
        final String session = parts[3];
        final String time = parts[4];
        final String rawReason = parts[5];
        final String reason = rawReason == 'MAINTENANCE_MODE_ACTIVE' ? 'Hardware Open' : rawReason.replaceAll('_', ' ');

        await _recordFeedEvent(0, now, isBackground: isBackground, mode: evaluatedMode, status: 'Aborted', reason: reason);
        await saveNotification(
          AppNotification(level: rawReason == 'MAINTENANCE_MODE_ACTIVE' ? 'Medium' : 'High', message: 'Scheduled feeding aborted: Session $session at $time. Reason: $reason.', timestamp: now),
          isBackground: isBackground,
        );
        return;
      }

      if (rawMode == 'MANUAL' && parts.length >= 4) {
        final String rawReason = parts[3];
        final String reason = rawReason == 'MAINTENANCE_MODE_ACTIVE' ? 'Hardware Open' : rawReason.replaceAll('_', ' ');

        await _recordFeedEvent(0, now, isBackground: isBackground, mode: evaluatedMode, status: 'Aborted', reason: reason);
        await saveNotification(
          AppNotification(level: rawReason == 'MAINTENANCE_MODE_ACTIVE' ? 'Medium' : 'High', message: 'Manual feeding aborted. Reason: $reason.', timestamp: now),
          isBackground: isBackground,
        );
        return;
      }
    }

    // --- 5. FAILED FEEDING ---
    if (action == 'FAIL') {
      if (rawMode == 'SCHED' && parts.length >= 6) {
        final String session = parts[3];
        final String time = parts[4];
        final String reason = parts[5].replaceAll('_', ' ');
        
        await _recordFeedEvent(0, now, isBackground: isBackground, mode: evaluatedMode, status: 'Failed', reason: reason);
        await saveNotification(
          AppNotification(level: 'High', message: 'Scheduled feeding failed: Session $session at $time. Reason: $reason.', timestamp: now),
          isBackground: isBackground,
        );
        return;
      }

      if (rawMode == 'MANUAL' && parts.length >= 4) {
        final String reason = parts[3].replaceAll('_', ' ');
        
        await _recordFeedEvent(0, now, isBackground: isBackground, mode: evaluatedMode, status: 'Failed', reason: reason);
        await saveNotification(
          AppNotification(level: 'High', message: 'Manual feeding failed. Reason: $reason.', timestamp: now),
          isBackground: isBackground,
        );
        return;
      }
    }

    // --- 6. FALLBACK FOR MISSING HARDWARE DATA ---
    // If the Arduino sends a truncated message like "FEED,DONE,20" 
    if (action == 'DONE' && parts.length == 3) {
      final int grams = int.tryParse(parts[2]) ?? lastCommandedFeed ?? 0;
      await _recordFeedEvent(grams, now, isBackground: isBackground, mode: evaluatedMode, status: 'Success', reason: 'None');
      await saveNotification(
        AppNotification(level: 'Low', message: 'Feeding done: $grams g dispensed.', timestamp: now),
        isBackground: isBackground,
      );
      lastCommandedFeed = null;
      return;
    }

    // Catch-all
    await saveNotification(
      AppNotification(level: 'Info', message: parts.join(','), timestamp: now),
      isBackground: isBackground,
    );
  }
  
  static Future<void> _processSms(
    String message, {
    bool isBackground = false,
  }) async {
    final DateTime now = DateTime.now();
    final String msgUpper = message.toUpperCase();

    if (msgUpper.startsWith('RTC,OK,')) {
      await saveNotification(
        AppNotification(
          level: 'Info',
          message:
              'RTC synchronized successfully: ${message.substring(7)}',
          timestamp: now,
        ),
        isBackground: isBackground,
      );
      return;
    }

    if (msgUpper.startsWith('RTC,ERR,')) {
      await saveNotification(
        AppNotification(
          level: 'High',
          message:
              'RTC synchronization failed: ${message.substring(8)}',
          timestamp: now,
        ),
        isBackground: isBackground,
      );
      return;
    }

    if (msgUpper.startsWith('SCHED,SAVED,')) {
      final String count = message.split(',').length >= 3
          ? message.split(',')[2]
          : '?';
      await saveNotification(
        AppNotification(
          level: 'Info',
          message:
              'Prototype stored daily schedule successfully. Active sessions: $count.',
          timestamp: now,
        ),
        isBackground: isBackground,
      );
      return;
    }

    if (msgUpper.startsWith('SCHED,SAVED,S')) {
      final List<String> tokens = message.split(',');
      final String slot =
          tokens.length >= 3 ? tokens[2] : '?';
      await saveNotification(
        AppNotification(
          level: 'Info',
          message:
              'Prototype confirmed save for schedule slot $slot.',
          timestamp: now,
        ),
        isBackground: isBackground,
      );
      return;
    }

    if (msgUpper.startsWith('SCHED,CLEARED,')) {
      final List<String> tokens = message.split(',');
      final String slot =
          tokens.length >= 3 ? tokens[2] : '?';
      await saveNotification(
        AppNotification(
          level: 'Info',
          message:
              'Prototype cleared schedule slot $slot.',
          timestamp: now,
        ),
        isBackground: isBackground,
      );
      return;
    }

    if (msgUpper.startsWith('SCHED,ERR,')) {
      await saveNotification(
        AppNotification(
          level: 'High',
          message:
              'Schedule save failed: ${message.substring(10)}',
          timestamp: now,
        ),
        isBackground: isBackground,
      );
      return;
    }

    if (msgUpper.startsWith('DRAIN,OPENED')) {
      await saveNotification(
        AppNotification(
          level: 'Medium', 
          message: 'Hardware Confirmation: Servos are now OPENED for draining/maintenance.',
          timestamp: now,
        ),
        isBackground: isBackground,
      );
      return;
    }

    if (msgUpper.startsWith('DRAIN,CLOSED')) {
      await saveNotification(
        AppNotification(
          level: 'Low', 
          message: 'Hardware Confirmation: Servos are now CLOSED and secured.',
          timestamp: now,
        ),
        isBackground: isBackground,
      );
      return;
    }

    if (msgUpper.startsWith('FEED,')) {
      await _processFeedMessage(
        message.split(','),
        now,
        isBackground: isBackground,
      );
      return;
    }

    try {
      final List<String> parts = message.split(',');
      final bool isSensorData =
          parts.length >= 3 &&
              double.tryParse(parts[0].trim()) != null;

      if (isSensorData) {
        final double t =
            double.parse(parts[0].trim());
        final double p =
            double.parse(parts[1].trim());
        final double d =
            double.parse(parts[2].trim());

        final reading = SensorReading(
          temp: t,
          ph: p,
          doLevel: d,
          timestamp: now,
        );

        if (!isBackground) history.add(reading);
        await DatabaseHelper.instance
            .insertReading(reading);

        final int riskLevel =
            WaterQualityEvaluator.evaluateRisk(
                t, p, d);

        if (riskLevel == 3) {
          await saveNotification(
            AppNotification(
              level: 'High',
              message:
                  'CRITICAL ALERT: Automatic reading received. Parameters dangerous (Temp:$t, pH:$p, DO:$d).',
              timestamp: now,
            ),
            isBackground: isBackground,
          );
        } else if (riskLevel == 2) {
          await saveNotification(
            AppNotification(
              level: 'Medium',
              message:
                  'WARNING: Automatic reading received. Parameters drifting (Temp:$t, pH:$p, DO:$d).',
              timestamp: now,
            ),
            isBackground: isBackground,
          );
        } else {
          await saveNotification(
            AppNotification(
              level: 'Low',
              message:
                  'System Update: Water returned to safe levels.',
              timestamp: now,
            ),
            isBackground: isBackground,
          );
        }
      } else {
        await saveNotification(
          AppNotification(
            level: 'Info',
            message: message,
            timestamp: now,
          ),
          isBackground: isBackground,
        );
      }
    } catch (e) {
      await saveNotification(
        AppNotification(
          level: 'Info',
          message: message,
          timestamp: now,
        ),
        isBackground: isBackground,
      );
      developer.log(
        'Saved unrecognized SMS as notification: $message',
        name: 'SmsHandler',
      );
    }

    if (!isBackground) updateNotifier.value++;
  }

  static Future<void> init() async {
    await loadLocalData();
  

    await _telephony.requestPhoneAndSmsPermissions;

    await syncMissedMessages();
    
    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) {
        handleIncomingSms(message, isBackground: false);
      },
      onBackgroundMessage: backgroundMessageHandler,
      listenInBackground: true,
    );
  }
}