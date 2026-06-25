import 'package:flutter/material.dart';

/// Centralized styling constants used across the FeediSense app.
///
/// This file defines a consistent color palette and basic text styles
/// derived from the Analytics page.  Import this file in any UI screen
/// to ensure fonts, backgrounds and card decorations remain uniform.
///
/// Usage:
///   import 'app_styles.dart';
///   Container(
///     decoration: BoxDecoration(
///       color: kCardBackground,
///       borderRadius: BorderRadius.circular(18),
///       border: Border.all(color: kCardBorder),
///       boxShadow: [kCardShadow],
///     ),
///     child: ...,
///   );

// Page backgrounds and surfaces
const Color kPageBackground = Color(0xFFF3F5F7);
const Color kCardBackground = Colors.white;
const Color kCardBorder = Color(0xFFE6EAEE);

// Typography colours
const Color kMutedText = Color(0xFF8A94A6);
const Color kTitleText = Color(0xFF5E6878);
const Color kPrimaryText = Color(0xFF0F172A);

// Primary branding colours
const Color kPrimaryColor = Color(0xFF2563EB);
const Color kSecondaryColor = Color(0xFF10B981);

// Risk indicator colours (re-exported from analytics for convenience)
const Color kLowRiskColor = Color(0xFF21A453);
const Color kMediumRiskColor = Color(0xFFD79A08);
const Color kHighRiskColor = Color(0xFFE53935);
const Color kRecoveredColor = Color(0xFF3D67FF);
const Color kEventMarkerColor = Color(0xFF8FB5FF);

/// Shadow used for cards and panels throughout the app.
final BoxShadow kCardShadow = BoxShadow(
  color: Colors.black.withValues(alpha: 0.04),
  blurRadius: 14,
  offset: const Offset(0, 4),
);
/// Text style for section titles (e.g. "Fish Population").
const TextStyle kSectionTitleStyle = TextStyle(
  color: kTitleText,
  fontSize: 18,
  fontWeight: FontWeight.bold,
);

/// Text style for primary values (e.g. numbers in result cards).
TextStyle primaryValueStyle({Color colour = kPrimaryColor, double fontSize = 24}) => TextStyle(
  color: colour,
  fontSize: fontSize,
  fontWeight: FontWeight.bold,
);

/// Standard decoration for cards.  Apply using BoxDecoration and adjust
/// borderRadius and padding as needed.
BoxDecoration cardDecoration({double radius = 18}) => BoxDecoration(
  color: kCardBackground,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: kCardBorder),
  boxShadow: [kCardShadow],
);