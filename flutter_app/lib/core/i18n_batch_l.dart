// driver_merchant_register_screen.dart's new email field — needed so
// driver/merchant accounts have an email on file for the email-based OTP
// login/password-reset (db/security-90), which previously always failed
// for them (their registration never collected one, unlike the customer
// flow). Kept as its own file per the established parallel-batch pattern.
const Map<String, Map<String, String>> batchLStrings = {
  'driver_reg_label_email': {'ar': 'البريد الإلكتروني', 'en': 'Email address'},
};
