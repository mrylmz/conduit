import 'dart:io';

import 'package:conduit_runtime/runtime.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

void main() {
  print(absolute(Directory.current.uri.toFilePath()));
  final absolutePathToAppLib = normalize(absolute(join(Directory.current.uri
      .resolve("../")
      .resolve("runtime_test_packages/")
      .resolve("application/")
      .resolve("lib/")
      .toFilePath(windows: Platform.isWindows))));
  late BuildContext ctx;

  setUpAll(() async {
    var cmd;
    if (Platform.isWindows) {
      cmd = (await Process.run("where", ["pub.bat"])).stdout;
    } else {
      cmd = (await Process.run("which", ["pub"])).stdout;
    }

    print(Directory.current.uri);
    final testPackagesUri =
        Directory.current.uri.resolve("../").resolve("runtime_test_packages/");
    await Process.run(cmd, ["get", "--offline"],
        workingDirectory: testPackagesUri
            .resolve("application/")
            .toFilePath(windows: Platform.isWindows),
        runInShell: true);
    await Process.run(cmd, ["get", "--offline"],
        workingDirectory: testPackagesUri
            .resolve("dependency/")
            .toFilePath(windows: Platform.isWindows),
        runInShell: true);

    final appDir = testPackagesUri.resolve("application/");
    final appLib = appDir.resolve("lib/").resolve("application.dart");
    final tmp = Directory.current.uri.resolve("tmp/");
    ctx = BuildContext(
        appLib,
        tmp,
        tmp.resolve("app.aot"),
        File.fromUri(appDir.resolve("bin/").resolve("main.dart"))
            .readAsStringSync());
  });
  test("Get import directives using single quotes", () async {
    final imports = await ctx.getImportDirectives(
        source:
            "import 'package:foo.dart';\nimport 'package:bar.dart'; class Foobar {}");
    expect(
        imports, ["import 'package:foo.dart';", "import 'package:bar.dart';"]);
  });
  test("Get import directives using double quotes", () async {
    final imports = await ctx.getImportDirectives(
        source:
            "import 'package:foo/foo.dart';\n import 'package:bar2/bar_.dart'; class Foobar {}");
    expect(imports,
        ["import 'package:foo/foo.dart';", "import 'package:bar2/bar_.dart';"]);
  });

  test("Find in file", () async {
    final imports = await ctx.getImportDirectives(
      uri: Directory.current.uri
          .resolve("../")
          .resolve("runtime_test_packages/")
          .resolve("application/")
          .resolve("lib/")
          .resolve("application.dart"),
    );

    expect(imports, [
      "import 'package:dependency/dependency.dart';",
      "import 'file:${absolutePathToAppLib}/src/file.dart';"
    ]);
  });

  test("Resolve input URI and resolves import relative paths", () async {
    final imports = await ctx.getImportDirectives(
      uri: Uri.parse("package:application/application.dart"),
    );

    expect(imports, [
      "import 'package:dependency/dependency.dart';",
      "import 'file:${absolutePathToAppLib}/src/file.dart';"
    ]);
  });

  test("Resolve src files and parent directories", () async {
    final imports = await ctx.getImportDirectives(
      uri: Uri.parse("package:application/src/file.dart"),
    );

    expect(imports, [
      "import 'file:${absolutePathToAppLib}/application.dart';",
    ]);
  });
}
