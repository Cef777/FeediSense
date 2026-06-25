import 'dart:io'; // Fixes 'File'
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart'; // Fixes 'getApplicationDocumentsDirectory'
import 'package:csv/csv.dart'; // Fixes 'ListToCsvConverter'
import 'package:share_plus/share_plus.dart'; // Fixes 'Share' and 'XFile'

import 'sms_handler.dart';
import 'models.dart';
// Import centralized styles to reuse the shared colour palette and card styles.
import 'app_styles.dart';
import 'database_helper.dart';

enum RiskLevel { low, medium, high }

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  late ValueNotifier<int> _updateNotifier;

  @override
  void initState() {
    super.initState();
    _updateNotifier = SmsHandler.updateNotifier;
    _updateNotifier.addListener(_onDataChanged);

    SmsHandler.loadLocalData();
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _updateNotifier.removeListener(_onDataChanged);
    super.dispose();
  }

  // --- DATA EXPORT METHOD ---
  // --- DATA EXPORT METHOD (NORMALIZED LEDGER) ---
  Future<void> _exportDataToCSV() async {
    try {
      // 1. Fetch ALL data from the database
      final sensorData = await DatabaseHelper.instance.fetchHistory();
      final feedData = await DatabaseHelper.instance.fetchFeedEvents();
      final notifications = await DatabaseHelper.instance.fetchNotifications();

      // 2. Prepare the Ledger headers
      List<List<dynamic>> rows = [];
      rows.add([
        'Timestamp',
        'Transaction Type',
        'Feeding Mode',
        'Status',
        'Grams Dispensed',
        'Temp (°C)',
        'pH Level',
        'DO (mg/L)',
        'Remarks/Reason'
      ]);

      // 3. Create a unified list to sort chronologically
      List<Map<String, dynamic>> unifiedLedger = [];

      // Map Sensor Data
      for (var s in sensorData) {
        unifiedLedger.add({
          'time': s.timestamp,
          'type': 'Water Reading',
          'mode': 'N/A',
          'status': 'Logged',
          'grams': 0,
          'temp': s.temp,
          'ph': s.ph,
          'doLevel': s.doLevel,
          'remarks': 'Routine check'
        });
      }

      // Map Feed Events (Including Partial, Reduced, Aborted)
      for (var f in feedData) {
        unifiedLedger.add({
          'time': f.timestamp,
          'type': 'Feeding Event',
          'mode': f.mode,
          'status': f.status,
          'grams': f.grams,
          'temp': f.temp == 0.0
              ? 'N/A'
              : f.temp, // Arduino doesn't always send water data on aborts
          'ph': f.ph == 0.0 ? 'N/A' : f.ph,
          'doLevel': f.doLevel == 0.0 ? 'N/A' : f.doLevel,
          'remarks': f.reason
        });
      }

      // Map System Notifications / Alerts
      for (var n in notifications) {
        unifiedLedger.add({
          'time': n.timestamp,
          'type': 'System Alert',
          'mode': 'N/A',
          'status': n.level,
          'grams': 'N/A',
          'temp': 'N/A',
          'ph': 'N/A',
          'doLevel': 'N/A',
          'remarks': n.message
        });
      }

      // 4. Sort everything chronologically from Day 1 to End
      unifiedLedger.sort(
          (a, b) => (a['time'] as DateTime).compareTo(b['time'] as DateTime));

      // 5. Populate rows
      for (var item in unifiedLedger) {
        DateTime dt = item['time'];
        String formattedDate =
            "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";

        rows.add([
          formattedDate,
          item['type'],
          item['mode'],
          item['status'],
          item['grams'],
          item['temp'],
          item['ph'],
          item['doLevel'],
          item['remarks']
        ]);
      }

      // 6. Convert to CSV and Save
      String csvData = const ListToCsvConverter().convert(rows);
      final directory = await getApplicationDocumentsDirectory();
      final path =
          "${directory.path}/FeediSense_Ledger_${DateTime.now().millisecondsSinceEpoch}.csv";
      final file = File(path);
      await file.writeAsString(csvData);

      // 7. Trigger Share/Download Prompt
      await Share.shareXFiles([XFile(path)],
          text: 'FeediSense Complete Transaction Ledger');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating ledger: $e')),
        );
      }
    }
  }

  // --- Helper to format dates cleanly without external packages ---
  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    String month = months[date.month - 1];
    int hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    String minute = date.minute.toString().padLeft(2, '0');
    String period = date.hour < 12 ? 'AM' : 'PM';
    return '$month ${date.day}, ${date.year}, $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    // ==========================================
    // DATA PROCESSING LOGIC
    // ==========================================
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    // 1. Today's Feed Metrics
    int totalFeedToday = 0;
    int feedingsToday = 0;
    FeedEvent? lastFeedToday;

    for (var feed in SmsHandler.feedHistory) {
      // CHANGED: Use !isBefore to strictly capture all data for today
      if (!feed.timestamp.isBefore(startOfDay)) {
        totalFeedToday += feed.grams;
        feedingsToday++;
        lastFeedToday = feed; // Relies on history being chronologically ordered
      }
    }

    // 2. Today's Risk Metrics
    int highestRiskToday = 1;
    for (var reading in SmsHandler.history) {
      // CHANGED: Use !isBefore here as well
      if (!reading.timestamp.isBefore(startOfDay)) {
        int risk = WaterQualityEvaluator.evaluateRisk(
            reading.temp, reading.ph, reading.doLevel);
        if (risk > highestRiskToday) highestRiskToday = risk;
      }
    }

    String riskTodayStr = highestRiskToday == 3
        ? 'HIGH'
        : (highestRiskToday == 2 ? 'MEDIUM' : 'LOW');
    Color riskTodayColor = highestRiskToday == 3
        ? kHighRiskColor
        : (highestRiskToday == 2 ? kMediumRiskColor : kLowRiskColor);

    // 3. Historical Averages & Windows
    int lowRiskCount = 0, medRiskCount = 0, highRiskCount = 0;
    int lowRiskGrams = 0, medRiskGrams = 0, highRiskGrams = 0;
    int totalFeedsAllTime = SmsHandler.feedHistory.length;
    int totalGramsAllTime = 0;

    for (var feed in SmsHandler.feedHistory) {
      int risk =
          WaterQualityEvaluator.evaluateRisk(feed.temp, feed.ph, feed.doLevel);
      totalGramsAllTime += feed.grams;
      if (risk == 1) {
        lowRiskCount++;
        lowRiskGrams += feed.grams;
      } else if (risk == 2) {
        medRiskCount++;
        medRiskGrams += feed.grams;
      } else if (risk == 3) {
        highRiskCount++;
        highRiskGrams += feed.grams;
      }
    }

    int avgLow = lowRiskCount > 0 ? (lowRiskGrams / lowRiskCount).round() : 0;
    int avgMed = medRiskCount > 0 ? (medRiskGrams / medRiskCount).round() : 0;
    int avgHigh =
        highRiskCount > 0 ? (highRiskGrams / highRiskCount).round() : 0;
    int avgTotal = totalFeedsAllTime > 0
        ? (totalGramsAllTime / totalFeedsAllTime).round()
        : 0;

    // 4. Chart Timeline Generation (Merging Sensor + Feed events chronologically)
    List<dynamic> combinedTimeline = [
      ...SmsHandler.history,
      ...SmsHandler.feedHistory
    ];
    combinedTimeline.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Cap at the last 45 events so the chart doesn't get infinitely long
    if (combinedTimeline.length > 45) {
      combinedTimeline = combinedTimeline.sublist(combinedTimeline.length - 45);
    }

    List<RiskLevel> chartRisks = [];
    Map<int, double> chartBars = {};
    List<int> chartMarkers = [];

    // Fallback labels
    String leftLabel = '--';
    String midLabel = '--';
    String rightLabel = '--';
    double maxFeedAmount = 100.0; // Minimum scale

    if (combinedTimeline.isNotEmpty) {
      leftLabel = _formatDate(combinedTimeline.first.timestamp);
      rightLabel = _formatDate(combinedTimeline.last.timestamp);
      midLabel =
          _formatDate(combinedTimeline[combinedTimeline.length ~/ 2].timestamp);

      int currentRisk = 1; // Default to low

      for (int i = 0; i < combinedTimeline.length; i++) {
        var event = combinedTimeline[i];

        if (event is SensorReading) {
          currentRisk = WaterQualityEvaluator.evaluateRisk(
              event.temp, event.ph, event.doLevel);
          chartRisks.add(currentRisk == 3
              ? RiskLevel.high
              : (currentRisk == 2 ? RiskLevel.medium : RiskLevel.low));
        } else if (event is FeedEvent) {
          // If a feed event, capture the risk at that exact moment
          currentRisk = WaterQualityEvaluator.evaluateRisk(
              event.temp, event.ph, event.doLevel);
          chartRisks.add(currentRisk == 3
              ? RiskLevel.high
              : (currentRisk == 2 ? RiskLevel.medium : RiskLevel.low));

          chartBars[i] = event.grams.toDouble();
          chartMarkers.add(i);
          if (event.grams > maxFeedAmount)
            maxFeedAmount = event.grams.toDouble();
        }
      }
    }

    // Safety fallback if no data exists
    if (chartRisks.length < 2) {
      chartRisks = [RiskLevel.low, RiskLevel.low];
    }
    // Add a 20% buffer to the top of the chart so the highest bar doesn't touch the edge
    maxFeedAmount = maxFeedAmount * 1.2;

    // ==========================================
    // UI BUILD
    // ==========================================
    final cards = <Widget>[
      SummaryCard(
        title: 'TOTAL FEED DISPENSED TODAY',
        minHeight: 128,
        child: PrimaryMetricContent(
          value: '${totalFeedToday}g',
          subtitle: '$feedingsToday feedings',
        ),
      ),
      SummaryCard(
        title: 'HIGHEST RISK LEVEL TODAY',
        minHeight: 128,
        child: PrimaryMetricContent(
          value: SmsHandler.history.isEmpty && SmsHandler.feedHistory.isEmpty
              ? '—'
              : riskTodayStr,
          subtitle: SmsHandler.history.isEmpty && SmsHandler.feedHistory.isEmpty
              ? 'No data today'
              : 'Based on latest sensors',
          valueColor:
              SmsHandler.history.isEmpty && SmsHandler.feedHistory.isEmpty
                  ? kMutedText
                  : riskTodayColor,
        ),
      ),
      SummaryCard(
        title: 'LAST FEED EVENT TODAY',
        minHeight: 168,
        child: PrimaryMetricContent(
          value: lastFeedToday != null ? '${lastFeedToday.grams}g' : '—',
          subtitle: lastFeedToday != null
              ? _formatDate(lastFeedToday.timestamp)
              : 'No feeds today',
        ),
      ),
      SummaryCard(
        title: 'WINDOW OUTCOMES',
        minHeight: 168,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$totalFeedsAllTime total',
                style: const TextStyle(
                    color: kPrimaryText,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1)),
            const SizedBox(height: 14),
            LabelValueRow(
                label: 'Stable (Low Risk)',
                value: '$lowRiskCount',
                valueColor: kLowRiskColor),
            const SizedBox(height: 8),
            LabelValueRow(
                label: 'Escalated (Med/High)',
                value: '${medRiskCount + highRiskCount}',
                valueColor: kHighRiskColor),
            const SizedBox(height: 8),
            LabelValueRow(
                label: 'Recovered',
                value: '--',
                valueColor:
                    kRecoveredColor), // Requires complex historical tracking
          ],
        ),
      ),
      SummaryCard(
        title: 'AVG FEED PER RISK WINDOW',
        minHeight: 168,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RiskAverageRow(
                label: 'Low Risk',
                value: avgLow > 0 ? '${avgLow}g' : '—',
                color: kLowRiskColor),
            const SizedBox(height: 8),
            RiskAverageRow(
                label: 'Medium Risk',
                value: avgMed > 0 ? '${avgMed}g' : '—',
                color: kMediumRiskColor),
            const SizedBox(height: 8),
            RiskAverageRow(
                label: 'High Risk',
                value: avgHigh > 0 ? '${avgHigh}g' : '—',
                color: kHighRiskColor),
            const SizedBox(height: 12),
            Text('$totalFeedsAllTime total feeding windows',
                style: const TextStyle(
                    color: kMutedText,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
      SummaryCard(
        title: 'AVG FEED PER WINDOW',
        minHeight: 168,
        child: PrimaryMetricContent(
          value: avgTotal > 0 ? '${avgTotal}g' : '—',
          subtitle: 'Across all $totalFeedsAllTime feeding events',
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Analytics Dashboard',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Tooltip(
              message: 'Download Transaction Ledger',
              child: IconButton(
                icon: const Icon(Icons.file_download_outlined, size: 28),
                onPressed: _exportDataToCSV,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  const double spacing = 12;
                  // Determine how many columns to show based on available width.
                  final int columns = constraints.maxWidth >= 900 ? 3 : 2;
                  final List<Widget> rowWidgets = [];

                  // Break the cards into chunks equal to the number of columns.
                  for (int i = 0; i < cards.length; i += columns) {
                    final int end = (i + columns > cards.length)
                        ? cards.length
                        : i + columns;
                    final List<Widget> slice = cards.sublist(i, end);

                    rowWidgets.add(
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (int j = 0; j < slice.length; j++)
                              Expanded(
                                child: Container(
                                  // Apply right margin except for the last item to create horizontal spacing.
                                  margin: EdgeInsets.only(
                                      right:
                                          j < slice.length - 1 ? spacing : 0),
                                  child: slice[j],
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                    // Add vertical spacing between rows except after the last row.
                    if (end < cards.length) {
                      rowWidgets.add(const SizedBox(height: spacing));
                    }
                  }

                  return Column(children: rowWidgets);
                },
              ),
              const SizedBox(height: 16),

              // Custom Chart UI
              FeedCorrelationCard(
                riskLevels: chartRisks,
                feedBars: chartBars,
                eventMarkers: chartMarkers,
                leftLabel: leftLabel,
                midLabel: midLabel,
                rightLabel: rightLabel,
                maxFeed: maxFeedAmount,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// UI COMPONENTS
// ============================================================================

class SummaryCard extends StatelessWidget {
  final String title;
  final Widget child;
  final double minHeight;

  const SummaryCard(
      {super.key,
      required this.title,
      required this.child,
      this.minHeight = 140});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kCardBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: kTitleText,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class PrimaryMetricContent extends StatelessWidget {
  final String value;
  final String subtitle;
  final Color valueColor;

  const PrimaryMetricContent(
      {super.key,
      required this.value,
      required this.subtitle,
      this.valueColor = kPrimaryText});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(
                color: valueColor,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1)),
        const SizedBox(height: 8),
        Text(subtitle,
            style: const TextStyle(
                color: kMutedText, fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class LabelValueRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const LabelValueRow(
      {super.key,
      required this.label,
      required this.value,
      required this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: kTitleText,
                    fontSize: 14,
                    fontWeight: FontWeight.w500))),
        Text(value,
            style: TextStyle(
                color: valueColor, fontSize: 14, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class RiskAverageRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const RiskAverageRow(
      {super.key,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: kTitleText,
                    fontSize: 14,
                    fontWeight: FontWeight.w500))),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ============================================================================
// CUSTOM CHART & PAINTER
// ============================================================================

class FeedCorrelationCard extends StatelessWidget {
  final List<RiskLevel> riskLevels;
  final Map<int, double> feedBars;
  final List<int> eventMarkers;
  final String leftLabel;
  final String midLabel;
  final String rightLabel;
  final double maxFeed;

  const FeedCorrelationCard({
    super.key,
    required this.riskLevels,
    required this.feedBars,
    required this.eventMarkers,
    required this.leftLabel,
    required this.midLabel,
    required this.rightLabel,
    required this.maxFeed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: kCardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kCardBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Feed Amount–Water Risk Correlation',
              style: TextStyle(
                  color: Colors.black,
                  fontSize: 17,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
              'Historical trend of risk levels with feed dispensed per event',
              style: TextStyle(
                  color: kTitleText,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
          const Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              LegendDot(label: 'Low Risk', color: kLowRiskColor),
              LegendDot(label: 'Medium Risk', color: kMediumRiskColor),
              LegendDot(label: 'High Risk', color: kHighRiskColor),
              LegendLine(label: 'Risk line'),
              LegendBar(label: 'Feed dispensed (g)'),
              LegendMarker(label: 'Feed event marker'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 330,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double chartWidth =
                    constraints.maxWidth < 920 ? 920 : constraints.maxWidth;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: chartWidth,
                    height: 330,
                    child: CustomPaint(
                      painter: FeedRiskChartPainter(
                        riskLevels: riskLevels,
                        feedBars: feedBars,
                        eventMarkers: eventMarkers,
                        leftLabel: leftLabel,
                        midLabel: midLabel,
                        rightLabel: rightLabel,
                        maxFeedLimit: maxFeed,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class LegendDot extends StatelessWidget {
  final String label;
  final Color color;
  const LegendDot({super.key, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => _LegendBase(
      label: label,
      icon: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)));
}

class LegendLine extends StatelessWidget {
  final String label;
  const LegendLine({super.key, required this.label});
  @override
  Widget build(BuildContext context) => _LegendBase(
      label: label,
      icon: Container(width: 24, height: 2, color: const Color(0xFF424A57)));
}

class LegendBar extends StatelessWidget {
  final String label;
  const LegendBar({super.key, required this.label});
  @override
  Widget build(BuildContext context) => _LegendBase(
      label: label,
      icon: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
              color: const Color(0xFFD8DDE4),
              border: Border.all(color: const Color(0xFF97A2AE)),
              borderRadius: BorderRadius.circular(3))));
}

class LegendMarker extends StatelessWidget {
  final String label;
  const LegendMarker({super.key, required this.label});
  @override
  Widget build(BuildContext context) => _LegendBase(
      label: label,
      icon: Container(width: 2, height: 14, color: kEventMarkerColor));
}

class _LegendBase extends StatelessWidget {
  final String label;
  final Widget icon;
  const _LegendBase({required this.label, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                color: kTitleText, fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class FeedRiskChartPainter extends CustomPainter {
  final List<RiskLevel> riskLevels;
  final Map<int, double> feedBars;
  final List<int> eventMarkers;
  final String leftLabel;
  final String midLabel;
  final String rightLabel;
  final double maxFeedLimit;

  FeedRiskChartPainter({
    required this.riskLevels,
    required this.feedBars,
    required this.eventMarkers,
    required this.leftLabel,
    required this.midLabel,
    required this.rightLabel,
    required this.maxFeedLimit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double leftPadding = 58;
    const double rightPadding = 48;
    const double topPadding = 10;
    const double bottomPadding = 42;

    final double chartLeft = leftPadding;
    final double chartRight = size.width - rightPadding;
    final double chartTop = topPadding;
    final double chartBottom = size.height - bottomPadding;
    final double chartWidth = chartRight - chartLeft;
    final double slotGap = riskLevels.length > 1
        ? chartWidth / (riskLevels.length - 1)
        : chartWidth;
    final double chartHeight = chartBottom - chartTop;

    double xForIndex(int index) => chartLeft + (index * slotGap);

    double yForValue(double value) {
      final normalized = value / maxFeedLimit;
      return chartBottom - (normalized * chartHeight);
    }

    double yForRisk(RiskLevel level) {
      switch (level) {
        case RiskLevel.low:
          return yForValue(maxFeedLimit * 0.1);
        case RiskLevel.medium:
          return yForValue(maxFeedLimit * 0.45);
        case RiskLevel.high:
          return yForValue(maxFeedLimit * 0.8);
      }
    }

    Color colorForRisk(RiskLevel level) {
      switch (level) {
        case RiskLevel.low:
          return kLowRiskColor;
        case RiskLevel.medium:
          return kMediumRiskColor;
        case RiskLevel.high:
          return kHighRiskColor;
      }
    }

    final gridPaint = Paint()
      ..color = const Color(0xFFE6EAF0)
      ..strokeWidth = 1;
    final markerPaint = Paint()
      ..color = kEventMarkerColor
      ..strokeWidth = 2;
    final barFillPaint = Paint()
      ..color = const Color(0xFFD8DDE4)
      ..style = PaintingStyle.fill;
    final barBorderPaint = Paint()
      ..color = const Color(0xFF97A2AE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = const Color(0xFF424A57)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.3;
    final axisTextStyle = const TextStyle(
        color: kTitleText, fontSize: 12, fontWeight: FontWeight.w500);

    TextPainter buildTextPainter(String text, TextStyle style) {
      return TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1)
        ..layout();
    }

    final double yHigh = yForRisk(RiskLevel.high);
    final double yMed = yForRisk(RiskLevel.medium);
    final double yLow = yForRisk(RiskLevel.low);

    // Horizontal grid lines
    for (final y in [yHigh, yMed, yLow, chartBottom]) {
      canvas.drawLine(Offset(chartLeft, y), Offset(chartRight, y), gridPaint);
    }

    // Event markers
    for (final marker in eventMarkers) {
      final x = xForIndex(marker);
      canvas.drawLine(Offset(x, chartTop), Offset(x, chartBottom), markerPaint);
    }

    // Feed bars
    for (final entry in feedBars.entries) {
      final x = xForIndex(entry.key);
      final y = yForValue(entry.value);
      const double barWidth = 7;
      final rect =
          Rect.fromLTWH(x - (barWidth / 2), y, barWidth, chartBottom - y);
      final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(2));
      canvas.drawRRect(rRect, barFillPaint);
      canvas.drawRRect(rRect, barBorderPaint);
    }

    // Step risk line
    if (riskLevels.isNotEmpty) {
      final path = Path()..moveTo(xForIndex(0), yForRisk(riskLevels.first));
      for (int i = 1; i < riskLevels.length; i++) {
        final x = xForIndex(i);
        path.lineTo(x, yForRisk(riskLevels[i - 1]));
        path.lineTo(x, yForRisk(riskLevels[i]));
      }
      canvas.drawPath(path, linePaint);

      // Risk dots
      for (int i = 0; i < riskLevels.length; i++) {
        final level = riskLevels[i];
        canvas.drawCircle(
            Offset(xForIndex(i), yForRisk(level)),
            4.8,
            Paint()
              ..color = colorForRisk(level)
              ..style = PaintingStyle.fill);
      }
    }

    // Left axis labels
    final highPainter = buildTextPainter('High', axisTextStyle);
    final medPainter = buildTextPainter('Med', axisTextStyle);
    final lowPainter = buildTextPainter('Low', axisTextStyle);
    highPainter.paint(canvas, Offset(18, yHigh - (highPainter.height / 2)));
    medPainter.paint(canvas, Offset(20, yMed - (medPainter.height / 2)));
    lowPainter.paint(canvas, Offset(20, yLow - (lowPainter.height / 2)));

    // Right axis labels (Dynamic scaling based on maxFeedLimit)
    double step = maxFeedLimit / 5;
    for (int i = 0; i <= 5; i++) {
      int val = (step * i).round();
      final painter = buildTextPainter('$val', axisTextStyle);
      final y = yForValue(val.toDouble()) - (painter.height / 2);
      painter.paint(canvas, Offset(chartRight + 10, y));
    }

    // X-axis labels (Dynamic Dates)
    final leftDatePainter = buildTextPainter(leftLabel, axisTextStyle);
    final midDatePainter = buildTextPainter(midLabel, axisTextStyle);
    final rightDatePainter = buildTextPainter(rightLabel, axisTextStyle);

    leftDatePainter.paint(canvas, Offset(chartLeft - 54, chartBottom + 12));
    midDatePainter.paint(
        canvas,
        Offset(chartLeft + (chartWidth / 2) - (midDatePainter.width / 2),
            chartBottom + 12));
    rightDatePainter.paint(canvas,
        Offset(chartRight - rightDatePainter.width + 22, chartBottom + 12));
  }

  @override
  bool shouldRepaint(covariant FeedRiskChartPainter oldDelegate) {
    return oldDelegate.riskLevels != riskLevels ||
        oldDelegate.feedBars != feedBars ||
        oldDelegate.eventMarkers != eventMarkers;
  }
}
