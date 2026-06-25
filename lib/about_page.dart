import 'package:flutter/material.dart';
import 'sms_config.dart';

/// About page shows app and developer info, and lets users set the
/// prototype’s phone number.  This version does not attempt to select
/// a SIM card because the `another_telephony` plugin does not expose
/// subscription information on all devices.  All SMS commands will be
/// sent using the default SIM.
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final TextEditingController _numberController;
  String _selectedCountryCode = '+63';

  @override
  void initState() {
    super.initState();
    final initial = SmsConfig.phoneNumber;
    String digits;
    if (initial.startsWith('+63') || initial.startsWith('+1')) {
      _selectedCountryCode = initial.substring(0, 3);
      digits = initial.substring(3);
    } else {
      digits = initial;
    }
    _numberController = TextEditingController(text: digits);
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  void _updatePhoneNumber() {
    final String digits = _numberController.text.trim();
    // Validate that the user entered exactly 10 digits.
    if (digits.length != 10 || !RegExp(r'^\d{10}$').hasMatch(digits)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Number must be exactly 10 numeric digits.')),
      );
      return;
    }
    final String formatted = _selectedCountryCode + digits;
    setState(() {
      SmsConfig.phoneNumber = formatted;
      SmsConfig.subscriptionId = null; // use default SIM
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Prototype number updated')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSection(
              title: 'Application Information',
              content:
                  'FeediSense is an intelligent fish feeding management app designed to optimise feeding schedules and monitor water quality. '
                  'The system uses sensors to measure temperature, pH and dissolved oxygen and communicates via SMS with a hardware prototype. '
                  'By analysing these data, it improves fish health and farming efficiency.',
            ),
            const SizedBox(height: 20),
            _buildSection(
              title: 'Developer Information',
              content:
                  'Developed by students of the Polytechnic University of the Philippines - Sta. Mesa Campus.\n\n'
                  'Team Members:\n• BALADAD, Kier Niño C.\n• BUBOS, Cefren Pao M.\n• GERONA, Geonell C.\n• LAZONA, John Karlo B.',
            ),
            const SizedBox(height: 20),
            _buildPhoneSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required String content}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(content, style: const TextStyle(fontSize: 14, height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildPhoneSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Prototype Mobile Number',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              DropdownButton<String>(
                value: _selectedCountryCode,
                items: const [
                  DropdownMenuItem(value: '+63', child: Text('+63')),
                  DropdownMenuItem(value: '+1', child: Text('+1')),
                ],
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() => _selectedCountryCode = newValue);
                  }
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _numberController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'XXXXXXXXXX',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _updatePhoneNumber,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Update', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}