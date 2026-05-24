import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../../features/products/data/product_repository.dart';
import 'database_service.dart';

const String fetchImageTask = "fetchProductImageTask";

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      if (task == fetchImageTask) {
        final productId = inputData?['productId'] as String?;
        final imageUrl = inputData?['imageUrl'] as String?;

        if (productId != null && imageUrl != null) {
          await DatabaseService.initialize();
          await _downloadAndSaveImage(productId, imageUrl);
        }
      }
      return Future.value(true);
    } catch (err) {
      debugPrint('Background task error: $err');
      return Future.value(false);
    }
  });
}

class BackgroundTasksService {
  static Future<void> init() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await Workmanager().initialize(callbackDispatcher);
    }
  }

  static void scheduleImageDownload(String productId, String imageUrl) {
    debugPrint('[BackgroundTasks] scheduleImageDownload called for $productId');
    debugPrint('[BackgroundTasks] imageUrl: $imageUrl');

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      Workmanager().registerOneOffTask(
        "image_download_$productId",
        fetchImageTask,
        inputData: <String, dynamic>{
          'productId': productId,
          'imageUrl': imageUrl,
        },
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } else {
      // Fallback for Windows/Mac/Linux where WorkManager isn't available
      _downloadAndSaveImage(productId, imageUrl)
          .then((_) {
            debugPrint(
              '[BackgroundTasks] Image download completed for $productId',
            );
          })
          .catchError((e) {
            debugPrint(
              '[BackgroundTasks] Image download FAILED for $productId: $e',
            );
          });
    }
  }
}

Future<void> _downloadAndSaveImage(String productId, String imageUrl) async {
  debugPrint('[BackgroundTasks] Starting download from: $imageUrl');

  // Use a proper User-Agent so servers don't block us
  final response = await http.get(
    Uri.parse(imageUrl),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      'Accept': 'image/*,*/*;q=0.8',
    },
  );

  debugPrint(
    '[BackgroundTasks] HTTP status: ${response.statusCode}, '
    'body length: ${response.bodyBytes.length}',
  );

  if (response.statusCode == 200 && response.bodyBytes.length > 500) {
    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${appDir.path}/product_images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    // Determine file extension from content-type or URL
    final contentType = response.headers['content-type'] ?? '';
    String ext = 'jpg';
    if (contentType.contains('png')) {
      ext = 'png';
    } else if (contentType.contains('webp')) {
      ext = 'webp';
    } else if (contentType.contains('gif')) {
      ext = 'gif';
    }

    final fileName = 'product_$productId.$ext';
    final file = File('${imagesDir.path}/$fileName');
    await file.writeAsBytes(response.bodyBytes);

    debugPrint('[BackgroundTasks] Saved to: ${file.path}');

    // Update the product record with the local file path
    await ProductRepository.update(productId, {'image_url': file.path});

    debugPrint(
      '[BackgroundTasks] Product $productId image_url updated to local path',
    );
  } else {
    debugPrint(
      '[BackgroundTasks] Download failed or image too small. '
      'Status: ${response.statusCode}, Size: ${response.bodyBytes.length}',
    );
    // Keep the original web URL as a fallback — don't clear it
  }
}
