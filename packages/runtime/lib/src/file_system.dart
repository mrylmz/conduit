import 'dart:io';

import 'package:package_config/package_config.dart';

/// Recursively copies the contents of the directory at [src] to [dst].
///
/// Creates directory at [dst] recursively if it doesn't exist.
void copyDirectory({required Uri src, required Uri dst}) {
  final srcDir = Directory.fromUri(src);
  final dstDir = Directory.fromUri(dst);
  if (!dstDir.existsSync()) {
    dstDir.createSync(recursive: true);
  }

  srcDir.listSync().forEach((fse) {
    if (fse is File) {
      final outPath = dstDir.uri
          .resolve(fse.uri.pathSegments.last)
          .toFilePath(windows: Platform.isWindows);
      fse.copySync(outPath);
    } else if (fse is Directory) {
      final segments = fse.uri.pathSegments;
      final outPath = dstDir.uri.resolve(segments[segments.length - 2]);
      copyDirectory(src: fse.uri, dst: outPath);
    }
  });
}

/// Reads .dart_tool/package_config.json file from [packagesFileUri] and returns map of package name to its location on disk.
///
/// If locations on disk are relative Uris, they are resolved by [relativeTo]. [relativeTo] defaults
/// to the CWD.
Future<Map<String, Uri>> getResolvedPackageUris(
  Uri packagesFileUri, {
  Uri? relativeTo,
}) async {
  final _relativeTo = relativeTo ?? Directory.current.uri;

  final packageConfig = await findPackageConfig(Directory.current);
  if (packageConfig == null) {
    throw StateError(
      "No .dart_tool/package_config.json file found at '$packagesFileUri'. "
      "Run 'pub get' in directory '${packagesFileUri.resolve('../')}'.",
    );
  }

  return Map.fromEntries(packageConfig.packages.map((package) {
    if (package.relativeRoot) {
      return MapEntry(
        package.name,
        Directory.fromUri(
          _relativeTo.resolveUri(package.packageUriRoot).normalizePath(),
        ).parent.uri,
      );
    }

    return MapEntry(
      package.name,
      Directory.fromUri(package.packageUriRoot).parent.uri,
    );
  }));
}
