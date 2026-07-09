import 'package:expiry_check/services/user_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UserService passcode flow', () {
    test('generates 6-digit codes', () {
      for (var i = 0; i < 20; i++) {
        expect(UserService.generatePasscode(), matches(RegExp(r'^\d{6}$')));
      }
    });

    test('correct passcode signs the user in', () async {
      SharedPreferences.setMockInitialValues({
        'pending_username': 'Riz',
        'pending_email': 'riz@example.com',
        'pending_passcode': '123456',
        'pending_passcode_expiry': DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
      });
      expect(await UserService.instance.verifyPasscode('123456'), isTrue);
      expect(await UserService.instance.username, 'Riz');
      expect(await UserService.instance.email, 'riz@example.com');
      expect(await UserService.instance.isSignedIn, isTrue);
    });

    test('wrong or expired passcode is rejected', () async {
      SharedPreferences.setMockInitialValues({
        'pending_username': 'Riz',
        'pending_email': 'riz@example.com',
        'pending_passcode': '123456',
        'pending_passcode_expiry': DateTime.now()
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      });
      expect(await UserService.instance.verifyPasscode('654321'), isFalse);
      expect(await UserService.instance.verifyPasscode('123456'), isFalse,
          reason: 'expired codes must be rejected');
      expect(await UserService.instance.isSignedIn, isFalse);
    });

    test('sign out clears the profile', () async {
      SharedPreferences.setMockInitialValues({
        'profile_username': 'Riz',
        'profile_email': 'riz@example.com',
      });
      await UserService.instance.signOut();
      expect(await UserService.instance.isSignedIn, isFalse);
    });
  });
}
