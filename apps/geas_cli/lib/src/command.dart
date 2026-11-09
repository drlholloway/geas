import 'package:args/command_runner.dart';

import 'context.dart';
import 'session.dart';

/// A `geas` subcommand.
abstract class GeasCommand extends Command<int> {
  GeasCommand(this.context);

  final GeasContext context;

  StringSink get out => context.out;

  /// The global `--offline` flag.
  bool get offline => globalResults!['offline'] as bool;

  Future<Session> openSession() => Session.open(context, offline: offline);

  void warn(String message) => context.err.writeln('geas: $message');

  /// The positional arguments.
  List<String> get rest => argResults!.rest;
}
