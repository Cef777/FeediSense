class SensorReading {
  final double temp;
  final double ph;
  final double doLevel;
  final DateTime timestamp;

  SensorReading({
    required this.temp,
    required this.ph,
    required this.doLevel,
    required this.timestamp,
  });
}

class AppNotification {
  final String level;
  final String message;
  final DateTime timestamp;

  AppNotification({
    required this.level, 
    required this.message, 
    required this.timestamp
  });
}

class FeedEvent {
  final int grams;
  final double temp;
  final double ph;
  final double doLevel;
  final DateTime timestamp;
  
  // NEW LEDGER FIELDS
  final String mode;   // 'Manual' or 'Scheduled'
  final String status; // 'Success', 'Partial', 'Reduced', 'Aborted'
  final String reason; // e.g., 'Hopper Empty', 'Water Warning', or 'None'

  FeedEvent({
    required this.grams,
    required this.temp,
    required this.ph,
    required this.doLevel,
    required this.timestamp,
    this.mode = 'Unknown',
    this.status = 'Success',
    this.reason = 'None',
  });

  Map<String, dynamic> toMap() {
    return {
      'grams': grams,
      'temp': temp,
      'ph': ph,
      'doLevel': doLevel,
      'timestamp': timestamp.toIso8601String(),
      'mode': mode,
      'status': status,
      'reason': reason,
    };
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