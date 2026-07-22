import 'package:url_launcher/url_launcher.dart';

/// Картографический провайдер (FR-L). По умолчанию — **Yandex Maps** (FR-L2).
enum MapProvider { yandex, google, apple }

/// Открытие мест в картах и (позже) геокодирование.
class MapsService {
  /// Дефолт — Yandex Maps (FR-L2). Сменяемо в настройках (FR-L5, Later).
  static MapProvider provider = MapProvider.yandex;

  /// Открыть место в выбранных картах (FR-L4).
  static Future<void> openLocation(String query) async {
    final q = Uri.encodeQueryComponent(query);
    final url = switch (provider) {
      MapProvider.yandex => 'https://yandex.ru/maps/?text=$q',
      MapProvider.google => 'https://www.google.com/maps/search/?api=1&query=$q',
      MapProvider.apple => 'https://maps.apple.com/?q=$q',
    };
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
