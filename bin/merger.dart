import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  var argParser = ArgParser()
    ..addOption(
      'input-name',
      help: 'Name of the package which should be transferred to a mono-repo',
    )
    ..addOption(
      'input-path',
      help: 'Path to the package which should be transferred to a mono-repo',
    )
    ..addOption(
      'target-path',
      help: 'Path to the mono-repo',
    )
    ..addOption(
      'branch-name',
      help: 'The name of the main branch on the input repo',
      defaultsTo: 'main',
    )
    ..addOption(
      'git-filter-repo',
      help: 'Path to the git-filter-repo tool',
    )
    ..addFlag(
      'push',
      help: 'Whether to push the branch to remote',
      defaultsTo: true,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Prints usage info',
      negatable: false,
    );

  String input;
  String inputPath;
  String targetPath;
  String branchName;
  String gitFilterRepo;
  bool push;
  try {
    var parsed = argParser.parse(arguments);
    if (parsed.flag('help')) {
      print(argParser.usage);
      exit(0);
    }

    input = parsed['input-name'] as String;
    inputPath = parsed['input-path'] as String;
    targetPath = parsed['target-path'] as String;
    branchName = parsed['branch-name'] as String;
    gitFilterRepo = parsed['git-filter-repo'] as String;
    push = parsed.flag('push');
  } catch (e) {
    print(e);
    print('');
    print(argParser.usage);
    exit(1);
  }

  print('Rename to `pkgs/`');
  await filterRepo(
    ['--path-rename', ':pkgs/$input/'],
    workingDirectory: inputPath,
    gitFilterRepo: gitFilterRepo,
  );
  print('Prefix tags');
  await filterRepo(
    ['--tag-rename', ':$input-'],
    workingDirectory: inputPath,
    gitFilterRepo: gitFilterRepo,
  );

  print('Create branch at target');
  await runProcess(
    'git',
    ['checkout', '-b', 'merge-$input-package'],
    workingDirectory: targetPath,
  );
  print('Add a remote for the local clone of the moving package');
  await runProcess(
    'git',
    ['remote', 'add', '${input}_package', inputPath],
    workingDirectory: targetPath,
  );
  await runProcess(
    'git',
    ['fetch', '${input}_package'],
    workingDirectory: targetPath,
  );
  print('Merge branch into monorepo');
  await runProcess(
    'git',
    [
      'merge',
      '--allow-unrelated-histories',
      '${input}_package/$branchName',
      '-m',
      'Merge package:$input into shared tool repository'
    ],
    workingDirectory: targetPath,
  );
  if (push) {
    print('Push to remote');
    await runProcess(
      'git',
      ['push', '--set-upstream', 'origin', 'merge-$input-package'],
      workingDirectory: targetPath,
    );
  }

  print('DONE!');
  print('''
Steps left to do:

- Move and fix workflow files
${push ? '' : '- Run `git push --set-upstream origin merge-$input-package` in the monorepo directory'}
- Disable squash-only in GitHub settings, and merge with a fast forward merge to the main branch, enable squash-only in GitHub settings.
- Push tags to github
- Follow up with a PR adding links to the top-level readme table.
- Add a commit to https://github.com/dart-lang/$input/ with it's readme pointing to the monorepo
- Archive https://github.com/dart-lang/$input/.
''');
}

Future<void> runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  print('----------');
  print(
      'Running `$executable $arguments`${workingDirectory != null ? ' in $workingDirectory' : ''}');
  var processResult = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  print('stdout:');
  print(processResult.stdout);
  if ((processResult.stderr as String).isNotEmpty) {
    print('stderr:');
    print(processResult.stderr);
  }
  print('==========');
}

Future<void> filterRepo(
  List<String> args, {
  required String workingDirectory,
  required String gitFilterRepo,
}) async {
  await runProcess(
    'python3',
    [p.relative(gitFilterRepo, from: workingDirectory), ...args],
    workingDirectory: workingDirectory,
  );
}
