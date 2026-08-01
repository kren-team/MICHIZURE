import '../domain/auth_failure.dart';

String authFailureMessage(Object error) {
  if (error is! AuthFailure) {
    return '処理に失敗しました。時間をおいてもう一度お試しください。';
  }

  return switch (error.kind) {
    AuthFailureKind.invalidEmail => 'メールアドレスの形式を確認してください。',
    AuthFailureKind.weakPassword => 'より強いパスワードを設定してください。',
    AuthFailureKind.emailAlreadyInUse => 'このメールアドレスはすでに登録されています。',
    AuthFailureKind.invalidCredential => 'メールアドレスまたはパスワードが正しくありません。',
    AuthFailureKind.networkUnavailable => 'ネットワークに接続できません。接続を確認してください。',
    AuthFailureKind.rateLimited => '試行回数が多すぎます。時間をおいて再試行してください。',
    AuthFailureKind.unknown => '処理に失敗しました。時間をおいてもう一度お試しください。',
  };
}
