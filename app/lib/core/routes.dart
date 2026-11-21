/// Every screen's path, in one place so features link to each other by
/// path without importing each other.
abstract final class Routes {
  static const signIn = '/sign-in';
  static const lobby = '/';
  static const shop = '/shop';
  static const profile = '/profile';
  static String room(String roomId) => '/room/$roomId';
}
