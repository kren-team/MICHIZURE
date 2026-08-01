import '../domain/profile_failure.dart';

String profileFailureMessage(Object error) {
  if (error is ProfileFailure &&
      error.kind == ProfileFailureKind.invalidDisplayName) {
    return '表示名は制御文字を含めず、1〜40文字で入力してください。';
  }
  return 'プロフィールを保存できませんでした。再試行してください。';
}
