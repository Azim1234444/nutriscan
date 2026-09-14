/// Single configuration point for NutriScan's server-side HTTP API.
abstract final class ApiConfig {
  /// Supply at build/run time, for example:
  /// `--dart-define=NUTRISCAN_API_BASE_URL=http://10.0.2.2:3000`.
  static const String baseUrl = String.fromEnvironment(
    'NUTRISCAN_API_BASE_URL',
  );

  static Uri get analyzeFoodEndpoint {
    final String configured = baseUrl.trim();
    if (configured.isEmpty) {
      throw const FormatException('NUTRISCAN_API_BASE_URL is not configured');
    }
    final Uri base = Uri.parse(
      configured.endsWith('/') ? configured : '$configured/',
    );
    if (!base.hasScheme || base.host.isEmpty) {
      throw const FormatException('NUTRISCAN_API_BASE_URL is invalid');
    }
    return base.resolve('api/analyze-food');
  }
}
