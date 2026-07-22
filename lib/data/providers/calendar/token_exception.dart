/// Бросается, когда refresh-токен протух/отозван (нужно переподключить аккаунт).
/// Синк-движок классифицирует это как `needsReconnect`, а не сетевую ошибку.
class TokenExpiredException implements Exception {
  TokenExpiredException(this.message);
  final String message;
  @override
  String toString() => message;
}
