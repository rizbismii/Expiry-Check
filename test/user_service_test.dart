import 'package:expiry_check/services/user_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UserService username/password sign-in', () {
    test('admin signs in with admin555777', () async {
      expect(await UserService.instance.signIn('admin', 'admin555777'), isTrue);
      expect(await UserService.instance.username, 'admin');
      expect(await UserService.instance.isAdmin, isTrue);
      expect(await UserService.instance.isSignedIn, isTrue);
    });

    test('admin username is case/space tolerant', () async {
      expect(
          await UserService.instance.signIn(' Admin ', 'admin555777'), isTrue);
    });

    test('admin with wrong password is rejected without touching the DB',
        () async {
      expect(await UserService.instance.signIn('admin', 'wrong'), isFalse);
      expect(await UserService.instance.isSignedIn, isFalse);
    });

    test('sign out clears the session', () async {
      await UserService.instance.signIn('admin', 'admin555777');
      await UserService.instance.signOut();
      expect(await UserService.instance.isSignedIn, isFalse);
      expect(await UserService.instance.isAdmin, isFalse);
    });
  });
}
