// Default entry point (used by plain `flutter run` / `flutter build` with
// no --target) — delegates to the customer flavor. Use main_customer.dart,
// main_driver.dart, or main_merchant.dart directly (or the matching
// `flutter run --flavor <name> -t lib/main_<name>.dart`) to build a
// specific app.
import 'app.dart';
import 'core/flavor.dart';

Future<void> main() => runWslhaApp(FlavorConfig.customer);
