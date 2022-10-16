// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:mirrors';

import 'package:conduit_runtime/src/build_context.dart';
import 'package:conduit_runtime/src/compiler.dart';
import 'package:conduit_runtime/src/file_system.dart';
import 'package:conduit_runtime/src/generator.dart';

class Build {
  Build(this.context);

  final BuildContext context;

  Future execute() async {
    final compilers = context.context.compilers;

    print("Resolving ASTs...");
    final astsToResolve = <Uri>{
      ...compilers.expand((c) => c.getUrisToResolve(context))
    };
    await Future.forEach<Uri>(
      astsToResolve,
      (astUri) async {
        final uri = await context.resolveUri(astUri);
        return await context.analyzer.resolveUnitAt(uri!);
      },
    );

    print("Generating runtime...");

    final runtimeGenerator = RuntimeGenerator();
    for (final entry in context.context.runtimes.map.entries) {
      if (entry.value is SourceCompiler) {
        runtimeGenerator.addRuntime(
          name: entry.key,
          source: await entry.value.compile(context),
        );
      }
    }

    await runtimeGenerator.writeTo(context.buildRuntimeDirectory.uri);
    print("Generated runtime at '${context.buildRuntimeDirectory.uri}'.");

    final nameOfPackageBeingCompiled = context.sourceApplicationPubspec.name;
    final pubspecMap = <String, dynamic>{
      'name': 'runtime_target',
      'version': '1.0.0',
      'environment': {'sdk': '>=2.12.0 <3.0.0'},
      'dependency_overrides': {}
    };
    final overrides = pubspecMap['dependency_overrides'] as Map;
    var sourcePackageIsCompiled = false;

    final packageMap = await context.resolvedPackages;

    for (final compiler in compilers) {
      final packageInfo = _getPackageInfoForCompiler(packageMap, compiler);
      final sourceDirUri = packageInfo.uri;
      final targetDirUri =
          context.buildPackagesDirectory.uri.resolve("${packageInfo.name}/");

      print("Compiling package '${packageInfo.name}'...");
      copyPackage(sourceDirUri, targetDirUri);
      compiler.deflectPackage(Directory.fromUri(targetDirUri));

      if (packageInfo.name != nameOfPackageBeingCompiled) {
        overrides[packageInfo.name] = {
          "path": targetDirUri.toFilePath(windows: Platform.isWindows)
        };
      } else {
        sourcePackageIsCompiled = true;
      }
      print("Package '${packageInfo.name}' compiled to '$targetDirUri'.");
    }

    final appDst = context.buildApplicationDirectory.uri;
    if (!sourcePackageIsCompiled) {
      print(
          "Copying application package (from '${context.sourceApplicationDirectory.uri}')...");
      copyPackage(context.sourceApplicationDirectory.uri, appDst);
      print("Application packaged copied to '$appDst'.");
    }
    pubspecMap['dependencies'] = {
      nameOfPackageBeingCompiled: {
        "path": appDst.toFilePath(windows: Platform.isWindows)
      }
    };

    if (context.forTests) {
      final devDeps = context.sourceApplicationPubspecMap['dev_dependencies'];
      if (devDeps != null) {
        pubspecMap['dev_dependencies'] = devDeps;
      }

      overrides['conduit'] = {
        'path': appDst.toFilePath(windows: Platform.isWindows)
      };
    }

    File.fromUri(context.buildDirectoryUri.resolve("pubspec.yaml"))
        .writeAsStringSync(json.encode(pubspecMap));

    context
        .getFile(context.targetScriptFileUri)
        .writeAsStringSync(context.source);

    for (final compiler in context.context.compilers) {
      compiler.didFinishPackageGeneration(context);
    }

    print("Fetching dependencies (--offline --no-precompile)...");
    await getDependencies();
    print("Finished fetching dependencies.");

    if (!context.forTests) {
      print("Compiling...");
      await compile(context.targetScriptFileUri, context.executableUri);
      print("Success. Executable is located at '${context.executableUri}'.");
    }
  }

  Future getDependencies() async {
    const String cmd = "dart";

    final res = await Process.run(
        cmd, ["pub", "get", "--offline", "--no-precompile"],
        workingDirectory:
            context.buildDirectoryUri.toFilePath(windows: Platform.isWindows),
        runInShell: true);
    if (res.exitCode != 0) {
      print("${res.stdout}");
      print("${res.stderr}");
      throw StateError(
          "'pub get' failed with the following message: ${res.stderr}");
    }
  }

  Future compile(Uri srcUri, Uri dstUri) async {
    final res = await Process.run(
        "dart",
        [
          "compile",
          "exe",
          "-v",
          srcUri.toFilePath(windows: Platform.isWindows),
          "-o",
          dstUri.toFilePath(windows: Platform.isWindows)
        ],
        workingDirectory: context.buildApplicationDirectory.uri
            .toFilePath(windows: Platform.isWindows),
        runInShell: true);
    if (res.exitCode != 0) {
      throw StateError(
          "'dart2native' failed with the following message: ${res.stderr}");
    }
    print("${res.stdout}");
  }

  void copyPackage(Uri srcUri, Uri dstUri) {
    copyDirectory(src: srcUri.resolve("lib/"), dst: dstUri.resolve("lib/"));
    context.getFile(srcUri.resolve("pubspec.yaml")).copySync(
        dstUri.resolve("pubspec.yaml").toFilePath(windows: Platform.isWindows));
  }

  _PackageInfo _getPackageInfoForName(
    Map<String, Uri> packageMap,
    String packageName,
  ) {
    final packageUri = packageMap[packageName];
    if (packageUri == null) {
      throw StateError(
          'Package "$packageName" not found in package map. Make sure it is in dependencies and run "pub get".');
    }

    return _PackageInfo(packageName, packageUri);
  }

  _PackageInfo _getPackageInfoForCompiler(
    Map<String, Uri> packageMap,
    Compiler compiler,
  ) {
    final compilerUri = reflect(compiler).type.location!.sourceUri;
    final parser = RegExp(r"package\:([^\/]+)");
    final parsed = parser.firstMatch(compilerUri.toString());
    if (parsed == null) {
      throw StateError(
        "Could not identify package of Compiler '${compiler.runtimeType}' "
        "(from URI '$compilerUri').",
      );
    }

    final packageName = parsed.group(1);
    return _getPackageInfoForName(packageMap, packageName!);
  }
}

class _PackageInfo {
  _PackageInfo(this.name, this.uri);

  final String name;
  final Uri uri;
}
