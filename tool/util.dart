library dsa.links.repository.util;

import "dart:async";
import "dart:convert";
import "dart:io";

export "dart:async";
export "dart:io";

typedef void ProcessHandler(Process process);
typedef void OutputHandler(String str);

class BetterProcessResult extends ProcessResult {
  final String output;

  BetterProcessResult(int pid, int exitCode, stdout, stderr, this.output) :
      super(pid, exitCode, stdout, stderr);
}

Directory getDir(String path) => new Directory(path);
File getFile(String path) => new File(path);

Future<BetterProcessResult> exec(
  String executable,
  {
  List<String> args: const [],
  String workingDirectory,
  Map<String, String> environment,
  bool includeParentEnvironment: true,
  bool runInShell: false,
  stdin,
  ProcessHandler handler,
  OutputHandler stdoutHandler,
  OutputHandler stderrHandler,
  OutputHandler outputHandler,
  File outputFile,
  bool inherit: false,
  bool writeToBuffer: false
  }) async {
  IOSink raf;

  if (outputFile != null) {
    if (!(await outputFile.exists())) {
      await outputFile.create(recursive: true);
    }

    raf = await outputFile.openWrite(mode: FileMode.APPEND);
  }

  try {
    Process process = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell
    );

    if (raf != null) {
      await raf.writeln("[${currentTimestamp}] == Executing ${executable} with arguments ${args} (pid: ${process.pid}) ==");
    }

    var buff = new StringBuffer();
    var ob = new StringBuffer();
    var eb = new StringBuffer();

    process.stdout.transform(UTF8.decoder).listen((str) async {
      if (writeToBuffer) {
        ob.write(str);
        buff.write(str);
      }

      if (stdoutHandler != null) {
        stdoutHandler(str);
      }

      if (outputHandler != null) {
        outputHandler(str);
      }

      if (inherit) {
        stdout.write(str);
      }

      if (raf != null) {
        await raf.writeln("[${currentTimestamp}] ${str}");
      }
    });

    process.stderr.transform(UTF8.decoder).listen((str) async {
      if (writeToBuffer) {
        eb.write(str);
        buff.write(str);
      }

      if (stderrHandler != null) {
        stderrHandler(str);
      }

      if (outputHandler != null) {
        outputHandler(str);
      }

      if (inherit) {
        stderr.write(str);
      }

      if (raf != null) {
        await raf.writeln("[${currentTimestamp}] ${str}");
      }
    });

    if (handler != null) {
      handler(process);
    }

    if (stdin != null) {
      if (stdin is Stream) {
        stdin.listen(process.stdin.add, onDone: process.stdin.close);
      } else if (stdin is List) {
        process.stdin.add(stdin);
      } else {
        process.stdin.write(stdin);
        await process.stdin.close();
      }
    }

    var code = await process.exitCode;
    var pid = process.pid;

    if (raf != null) {
      await raf.writeln("[${currentTimestamp}] == Exited with status ${code} ==");
      await raf.flush();
      await raf.close();
    }

    return new BetterProcessResult(
      pid,
      code,
      ob.toString(),
      eb.toString(),
      buff.toString()
    );
  } finally {
    if (raf != null) {
      await raf.flush();
      await raf.close();
    }
  }
}

String get currentTimestamp {
  return new DateTime.now().toString();
}

Future<dynamic> readJsonFile(String path, [Map defaultValue]) async {
  var file = new File(path);

  if (!(await file.exists()) && defaultValue != null) {
    return defaultValue;
  }

  var content = await file.readAsString();
  return JSON.decode(content);
}

bool deepEquals(a, b) {
  if (a is List && b is! List) return false;
  if (a is Map && b is! Map) return false;
  if (a is String && b is! String) return false;
}

Future saveJsonFile(String path, value) async {
  var file = new File(path);
  var content = new JsonEncoder.withIndent("  ").convert(value);
  await file.writeAsString(content + "\n");
}

void cd(String path) {
  var dir = new Directory(path);
  Directory.current = dir;
}

void fail(String msg) {
  print("ERROR: ${msg}");
  exit(1);
}

Future makeZipFile(String target) async {
  var tf = new File(target);

  if (!(await tf.parent.exists())) {
    await tf.parent.create(recursive: true);
  }

  var result = await exec("zip", args: [
    "-r",
    tf.absolute.path,
    "."
  ]);

  if (result.exitCode != 0) {
    throw new Exception("Failed to make ZIP file!");
  }
}

Future<List<dynamic>> loadJsonDirectoryList(String path, {bool strict: false}) async {
  var dir = new Directory(path);

  if (!(await dir.exists())) {
    return [];
  }

  var out = [];
  await for (FileSystemEntity entity in dir.list()) {
    if (entity is! File) continue;
    if (!entity.path.endsWith(".json")) continue;

    doWork() async {
      var data = await readJsonFile(entity.path);
      out.add(data);
    }

    if (strict) {
      await doWork();
    } else {
      try {
        await doWork();
      } catch (e) {}
    }
  }
  return out;
}

bool isJsonEqual(a, b) {
  return JSON.encode(a) == JSON.encode(b);
}

Future<List<Map<String, dynamic>>> buildLinksList() async {
  var links = await loadJsonDirectoryList("data/links");
  var typeRules = await loadJsonDirectoryMap("data/types");
  var mixins = await loadJsonDirectoryMap("data/mixins");
  var config = await readJsonFile("data/config.json");

  for (Map l in links) {
    mergeConfigurationTypes(typeRules, "type", l);
    mergeConfigurationTypes(mixins, "mixins", mixins);
  }

  crawlDataAndSubstituteVariables(links, config);

  return links;
}

Future<Map<String, dynamic>> loadJsonDirectoryMap(String path, {bool strict: false}) async {
  var dir = new Directory(path);

  if (!(await dir.exists())) {
    return {};
  }

  var out = {};
  await for (FileSystemEntity entity in dir.list()) {
    if (entity is! File) continue;
    if (!entity.path.endsWith(".json")) continue;

    doWork() async {
      var name = entity.path.split(Platform.pathSeparator).last;
      name = name.substring(0, name.length - 5);
      var data = await readJsonFile(entity.path);
      out[name] = data;
    }

    if (strict) {
      await doWork();
    } else {
      try {
        await doWork();
      } catch (e) {}
    }
  }
  return out;
}

void mergeConfigurationTypes(Map<String, Map<String, dynamic>> types, String field, Map input) {
  if (input == null) return;
  var typeList = input[field];
  if (typeList is String) {
    typeList = [typeList];
  }

  if (typeList is! List) {
    return;
  }

  for (String type in typeList) {
    if (type is String && types.containsKey(type)) {
      var original = new Map.from(input);
      input.clear();
      input.addAll(merge(original, types[type]));
    }
  }
}

void crawlDataAndSubstituteVariables(input, Map<String, dynamic> variables) {
  String handleString(String input) {
    for (var key in variables.keys) {
      var value = variables[key];
      input = input.replaceAll(r"${" + key + "}", value);
    }
    return input;
  }

  if (input is List) {
    for (var i = 0; i < input.length; i++) {
      var e = input[i];
      if (e is! String) {
        crawlDataAndSubstituteVariables(e, variables);
      } else {
        input[i] = handleString(e);
      }
    }
  } else if (input is Map) {
    for (var key in input.keys.toList()) {
      var value = input[key];

      if (value is! String) {
        crawlDataAndSubstituteVariables(value, variables);
      } else {
        input[key] = handleString(value);
      }
    }
  }
}

Map merge(Map a, Map b, {bool uniqueCollections: true, bool allowDirectives: false}) {
  var out = {};
  for (var key in a.keys) {
    var value = a[key];

    if (allowDirectives) {
      if (b.containsKey("!remove")) {
        var rm = b["!remove"];
        if (rm is String && rm == key) {
          continue;
        } else if (rm is List && rm.contains(key)) {
          continue;
        }
      } else if (value is List && b.containsKey("${key}!remove")) {
        b["${key}!remove"].forEach((a) => value.removeWhere((x) => x == a));
      }
    }

    if (b.containsKey(key)) {
      var bval = b[key];

      if (value is Map && bval is Map) {
        value = merge(value, bval, uniqueCollections: uniqueCollections, allowDirectives: allowDirectives);
      } else if (value is List && bval is List) {
        var tmp = uniqueCollections ? new Set() : [];
        tmp.addAll(value);
        tmp.addAll(bval);

        value = tmp.toList();
      }
    }
    out[key] = value;
  }

  for (var key in b.keys) {
    var value = b[key];

    if (allowDirectives && key is String && key.endsWith("!remove"))
      continue;

    if (!a.containsKey(key)) {
      out[key] = value;
    }
  }

  return out;
}

List<Directory> _dirStack = [];

pushd(String path) async {
  _dirStack.add(Directory.current);
  var dir = new Directory(path);
  if (!(await dir.exists())) {
    await dir.create(recursive: true);
  }
  Directory.current = dir;
}

void popd() {
  if (_dirStack.isEmpty) {
    throw new Exception("No Directory to Pop from the Stack");
  }

  Directory.current = _dirStack.removeLast();
}

rmkdir(String path) async {
  var dir = new Directory(path);
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
  await dir.create(recursive: true);
}

Future<File> copy(String from, String to) async {
  var ff = new File(from);
  var tf = new File(to);

  if (!(await tf.exists())) {
    await tf.create(recursive: true);
  }

  return await ff.copy(tf.path);
}
