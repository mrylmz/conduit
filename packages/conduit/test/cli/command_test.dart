import 'package:conduit/src/cli/command.dart';
import 'package:conduit/src/cli/metadata.dart';
import 'package:test/test.dart';

void main() {
  test('command invalid value', () async {
    var cmd = TestCLICommand();

    var args = ['--flavor=test'];

    expect(
        () => cmd.options.parse(args),
        throwsA(predicate<FormatException>((e) =>
            e.message ==
            '"test" is not an allowed value for option "flavor".')));
  });

  test('command invalid key', () async {
    var cmd = TestCLICommand();

    var args = ['--bad=test'];

    expect(
        () => cmd.options.parse(args),
        throwsA(predicate<FormatException>(
            (e) => e.message == 'Could not find an option named "bad".')));
  });

  test('Command empty value', () {
    var cmd = TestCLICommand();

    var args = ['--flavor=postgres'];

    var results = cmd.options.parse(args);
    cmd.process(results);
    expect(cmd.scopes, null);
  });

  test('Command list of values', () {
    var cmd = TestCLICommand();

    var args = ['--scopes=a b c d'];

    var results = cmd.options.parse(args);
    cmd.process(results);
    expect(cmd.scopes, ['a', 'b', 'c', 'd']);
  });

  test('Command invalid decode key', () {
    var cmd = TestCLICommand();

    var args = ['--scopes=a b c d'];

    var results = cmd.options.parse(args);
    cmd.process(results);
    expect(
        () => cmd.decode('invalid'),
        throwsA(predicate<CLIException>((e) =>
            e.message == 'The required argument "invalid" was not passed.')));
  });

  test('Command required key', () {
    var cmd = TestCLICommand();

    var args = ['--scopes=a b c d'];

    var results = cmd.options.parse(args);
    cmd.process(results);

    expect(
        () => cmd.databaseConnectionString,
        throwsA(predicate<CLIException>((e) =>
            e.message == 'The required argument "connect" was not passed.')));
  });

  test('Command int conversion', () {
    var cmd = TestCLICommand();

    var args = ['--count=10'];

    var results = cmd.options.parse(args);
    cmd.process(results);
    expect(cmd.count, equals(10));
  });

  test('Command missing optional arg', () {
    var cmd = TestCLICommand();

    var args = <String>[];

    var results = cmd.options.parse(args);
    cmd.process(results);
    expect(cmd.people, isNull);
  });

  test('Command missing optional arg with orElse', () {
    var cmd = TestCLICommand();

    var args = <String>['--guaranteed=4'];

    var results = cmd.options.parse(args);
    cmd.process(results);
    expect(cmd.guaranteed, 4);

    cmd = TestCLICommand();
    args = <String>[];
    results = cmd.options.parse(args);
    cmd.process(results);
    expect(cmd.guaranteed, 1);
  });

  test('Command invalid int conversion', () {
    var cmd = TestCLICommand();

    var args = ['--count=aa'];

    var results = cmd.options.parse(args);
    cmd.process(results);

    expect(
        () => cmd.count,
        throwsA(predicate<CLIException>((e) =>
            e.message == 'Invalid integer value "aa" for argument "count".')));
  });

  test('Command bool conversion ', () {
    var cmd = TestCLICommand();

    var args = ['--useSSL'];

    var results = cmd.options.parse(args);
    cmd.process(results);

    expect(cmd.useSSl, equals(true));
  });

  test('Command bool conversion - negated ', () {
    var cmd = TestCLICommand();

    var args = ['--no-useSSL'];

    var results = cmd.options.parse(args);
    cmd.process(results);

    expect(cmd.useSSl, equals(false));
  });
}

class TestCLICommand extends CLICommand {
  @override
  String get description => throw UnimplementedError();

  @override
  Future<int> handle() {
    return Future.value(0);
  }

  @override
  String get name => throw UnimplementedError();

  @Option('connect',
      abbr: 'c',
      help:
          'A database connection URI string. If this option is set, database-config is ignored.',
      valueHelp: 'postgres://user:password@localhost:port/databaseName')
  String? get databaseConnectionString => decode('connect');

  @Option('flavor',
      abbr: 'f',
      help: 'The database driver flavor to use.',
      defaultsTo: 'postgres',
      allowed: ['postgres'])
  String get databaseFlavor => decode('flavor');

  @Option('count', abbr: 'o', help: 'The no. of things.')
  int get count => decode('count');

  @Option('people', abbr: 'p', help: 'The no. of people.')
  int? get people => decodeOptional('people');

  @Option('guaranteed', abbr: 'g', help: 'The no. of guaranteed people.')
  int get guaranteed => decodeOptional('guaranteed', orElse: () => 1)!;

  @Flag('useSSL', abbr: 'u', help: 'UseSSL.', negatable: true)
  bool get useSSl => decode('useSSL');

  @Flag('useSSLWithDefault', abbr: 'd', help: 'useSSlWithDefault.')
  bool get useSSlWithDefault => decode('useSSlWithDefault');

  @Option('scopes',
      help:
          'A space-delimited list of allowed scopes. Omit if application does not support scopes.',
      defaultsTo: '')
  List<String>? get scopes {
    String? v = decode('scopes');
    if (v.isEmpty) {
      return null;
    }
    return v.split(' ').toList();
  }
}
