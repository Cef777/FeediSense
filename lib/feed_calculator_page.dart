import 'package:flutter/material.dart';

/// A page that allows farmers to calculate the daily feed requirement for
/// their fish stock based on fish count, average weight and pond dimensions.
///
/// Logic and functionality are unchanged.
/// Only UI alignment and consistency were improved:
/// - blue top app bar with white back arrow/title
/// - cleaner page background
/// - consistent result card width and height
/// - better alignment of result cards
class FeedCalculatorPage extends StatefulWidget {
  const FeedCalculatorPage({super.key});

  @override
  FeedCalculatorPageState createState() => FeedCalculatorPageState();
}

class FeedCalculatorPageState extends State<FeedCalculatorPage> {
  final TextEditingController _fishCountController = TextEditingController();
  final TextEditingController _avgWeightController = TextEditingController();
  final TextEditingController _lengthController = TextEditingController();
  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();

  double? _dailyFeed;
  int? _frequency;
  double? _feedPerSession;
  double? _feedDensity;
  String? _classification;
  bool? _isDensitySafe;

  void _calculateFeed() {
    final int? count = int.tryParse(_fishCountController.text);
    final double? weight = double.tryParse(_avgWeightController.text);
    final double? length = double.tryParse(_lengthController.text);
    final double? width = double.tryParse(_widthController.text);
    final double? height = double.tryParse(_heightController.text);

    if (count == null ||
        weight == null ||
        length == null ||
        width == null ||
        height == null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Invalid input'),
          content: const Text(
            'Please enter valid numeric values for all fields.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    String stage;
    double rate;
    int freq;
    final double weightGrams = weight;

    if (weightGrams <= 1.0) {
      stage = 'Fry';
      rate = 0.15;
      freq = 4;
    } else if (weightGrams <= 10.0) {
      stage = 'Fingerlings';
      rate = 0.10;
      freq = 2;
    } else if (weightGrams <= 25.0) {
      stage = 'Juveniles';
      rate = 0.05;
      freq = 2;
    } else {
      stage = 'Adults';
      rate = 0.03;
      freq = 2;
    }

    final double biomass = count * weightGrams;
    final double daily = biomass * rate;
    final double perSession = daily / freq;
    final double volume = length * width * height;
    final double density = volume > 0 ? daily / volume : 0.0;
    final bool safe = density <= 20.0;

    setState(() {
      _classification = stage;
      _dailyFeed = daily;
      _frequency = freq;
      _feedPerSession = perSession;
      _feedDensity = density;
      _isDensitySafe = safe;
    });
  }

  @override
  void dispose() {
    _fishCountController.dispose();
    _avgWeightController.dispose();
    _lengthController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        title: const Text(
          'Feed Calculator',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Fish Population',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2D2D),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildNumberField(
                    controller: _fishCountController,
                    label: 'Fish Count',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildNumberField(
                    controller: _avgWeightController,
                    label: 'Average Weight (g)',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Pond Dimension',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2D2D),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildNumberField(
                    controller: _lengthController,
                    label: 'Length (m)',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildNumberField(
                    controller: _widthController,
                    label: 'Width (m)',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildNumberField(
                    controller: _heightController,
                    label: 'Height (m)',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _calculateFeed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Calculate Feed Amount',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Calculation Results',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2D2D),
              ),
            ),
            const SizedBox(height: 12),
            _buildResultCard(
              title: 'Daily Recommended Feeds',
              value: _dailyFeed != null
                  ? '${_dailyFeed!.toStringAsFixed(0)} g'
                  : '-- g',
            ),
            const SizedBox(height: 12),
            _buildResultCard(
              title: 'Feeding Frequency',
              value: _frequency != null
                  ? '$_frequency times/day'
                  : '-- times/day',
              subtitle: _classification != null
                  ? 'Based on fish classification: $_classification'
                  : 'Awaiting input data...',
            ),
            const SizedBox(height: 12),
            _buildResultCard(
              title: 'Feed per Session',
              value: _feedPerSession != null
                  ? '${_feedPerSession!.toStringAsFixed(2)} g'
                  : '-- g',
            ),
            const SizedBox(height: 12),
            _buildResultCard(
              title: 'Feed Density',
              value: _feedDensity != null
                  ? '${_feedDensity!.toStringAsFixed(2)} g/m³'
                  : '-- g/m³',
              subtitle: _isDensitySafe == null
                  ? 'Awaiting input data...'
                  : (_isDensitySafe! ? 'Safe Range' : 'Exceeds Safe Range'),
              subtitleColor: _isDensitySafe == null
                  ? Colors.grey
                  : (_isDensitySafe! ? Colors.green : Colors.red),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Color(0xFF8A94A6),
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE6EAEE)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2563EB)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _buildResultCard({
    required String title,
    required String value,
    String? subtitle,
    Color subtitleColor = Colors.grey,
  }) {
    final bool isPlaceholder = value.contains('--');

    return SizedBox(
      width: double.infinity,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: 112,
        ),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE6EAEE)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF5E6878),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isPlaceholder
                    ? const Color(0xFF2563EB).withOpacity(0.4)
                    : const Color(0xFF2563EB),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: subtitleColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}