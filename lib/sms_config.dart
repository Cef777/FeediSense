/// Stores the prototype’s phone number and selected SIM ID.
///
/// When the user enters a phone number and selects a SIM in the About page,
/// these static fields are updated.  All SMS commands use these values.
class SmsConfig {
  static String phoneNumber = '+639087100831'; // default prototype number
  static int? subscriptionId; // SIM slot identifier (null means default)
}