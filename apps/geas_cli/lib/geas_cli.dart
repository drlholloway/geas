/// The `geas` command line, with its I/O injected so it can be tested.
library;

import 'package:args/command_runner.dart';
import 'package:geas_core/geas_core.dart';

import 'src/context.dart';
import 'src/init_command.dart';
import 'src/list_commands.dart';
import 'src/matrix_command.dart';
import 'src/session.dart';
import 'src/setup_command.dart';
import 'src/task_commands.dart';
import 'src/token_stores.dart';

export 'src/config.dart';
export 'src/context.dart';
export 'src/session.dart' show Session;
export 'src/token_stores.dart';

/// Runs `geas` with [args] and returns the exit code: 0, 1 for a failure,
/// 64 for bad usage.
Future<int> runGeas(List<String> args, GeasContext context) async {
  final runner =
      CommandRunner<int>('geas', 'A task manager synced through GitHub.')
        ..argParser.addFlag('offline',
            negatable: false,
            help: 'Don\'t sync; work on the local copy. Changes go out with '
                'the next sync.');
  for (final command in [
    SetupCommand(context),
    InitCommand(context),
    AddCommand(context),
    LsCommand(context),
    MatrixCommand(context),
    ShowCommand(context),
    DoneCommand(context),
    RmCommand(context),
    EditCommand(context),
    ListsCommand(context),
    TagsCommand(context),
    SyncCommand(context),
  ]) {
    runner.addCommand(command);
  }

  void fail(String message) => context.err.writeln('geas: $message');
  try {
    return await runner.run(args) ?? 0;
  } on UsageException catch (e) {
    context.err.writeln(e);
    return 64;
  } on CliException catch (e) {
    fail(e.message);
  } on TokenStoreException catch (e) {
    fail(e.message);
  } on NotInitializedException catch (e) {
    fail('$e');
  } on SyncRetriesExhaustedException catch (e) {
    fail('$e');
  } on UnsupportedFormatException catch (e) {
    fail('$e');
  } on GitHubException catch (e) {
    fail(describeError(e));
  } on FormatException catch (e) {
    fail(e.message);
  } on Exception catch (e) {
    if (!isNetworkError(e)) rethrow;
    fail(describeError(e));
  }
  return 1;
}
