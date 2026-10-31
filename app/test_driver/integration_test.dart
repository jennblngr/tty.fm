// Driver for `flutter drive` (lets Android builds target one ABI:
// -P target-platform=android-x64 on an emulator).
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
