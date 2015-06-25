import "dart:async";
import "dart:convert";
import "dart:io";

typedef void ProcessHandler(Process process);
typedef void OutputHandler(String str);

class BetterProcessResult extends ProcessResult {
  final String output;

  BetterProcessResult(int pid, int exitCode, stdout, stderr, this.output) :
  super(pid, exitCode, stdout, stderr);
}

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
    } else if (inherit) {
//      _stdin.listen(process.stdin.add, onDone: process.stdin.close);
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

Future<dynamic> readJsonFile(String path) async {
  var file = new File(path);
  var content = await file.readAsString();
  return JSON.decode(content);
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

List<Directory> _dirStack = [];

void pushd(String path) {
  _dirStack.add(Directory.current);
  var dir = new Directory(path);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  Directory.current = dir;
}

void popd() {
  if (_dirStack.isEmpty) {
    throw new Exception("No Directory to Pop from the Stack");
  }

  Directory.current = _dirStack.removeLast();
}

void rmkdir(String path) {
  var dir = new Directory(path);
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }
  dir.createSync(recursive: true);
}

void copy(String from, String to) {
  var ff = new File(from);
  var tf = new File(to);

  if (!tf.existsSync()) {
    tf.createSync(recursive: true);
  }

  tf.writeAsBytesSync(ff.readAsBytesSync());
}

main() async {
  var links = await readJsonFile("links.json");
  var revs = await readJsonFile("revs.json");

  rmkdir("tmp");
  
  for (var link in links) {
    if (!link.containsKey("automated")) {
      continue;
    }

    if (link["automated"]["enabled"] == false) {
      continue;
    }

    var name = link["displayName"];
    var rname = link["name"];

    print("[Build Start] ${name}");

    var linkType = link["type"];
    var automated = link["automated"];
    var repo = automated["repository"];
    pushd("tmp/${name}");
    var cr = await exec("git", args: ["clone", "--depth=1", repo, "."], writeToBuffer: true);
    if (cr.exitCode != 0) {
      fail("Failed to clone repository.\n${cr.output}");
    }

    var rpo = await exec("git", args: ["rev-parse", "HEAD"], writeToBuffer: true);
    var rev = rpo.output.toString().trim();

    if (revs.containsKey(rname) && revs[rname] == rev) {
      print("[Build Up-to-Date] ${name}");
      continue;
    }

    revs[rname] = rev;

    var cbs = new File("tool/build.sh");

    if (cbs.existsSync()) {
      var result = await exec("bash", args: [cbs.path], writeToBuffer: true);
      if (result.exitCode != 0) {
        fail("Failed to run custom build script.\n${result.output}");
      }
    } else if (linkType == "Dart") {
      var pur = await exec("pub", args: ["upgrade"], writeToBuffer: true);
      if (pur.exitCode != 0) {
        fail("Failed to fetch dependencies.\n${pur.output}");
      }

      var mainFile = new File("bin/run.dart");
      if (!(await mainFile.exists())) {
        mainFile = new File("bin/main.dart");
      }

      rmkdir("build/bin");

      var cmfr = await exec("dart2js", args: [
        mainFile.absolute.path,
        "-o",
        "build/bin/${mainFile.path.split('/').last}",
        "--output-type=dart",
        "--categories=Server",
        "-m"
      ], writeToBuffer: true);

      if (cmfr.exitCode != 0) {
        fail("Failed to build main file.\n${cmfr.output}");
      }

      copy("dslink.json", "build/dslink.json");
      pushd("build");
      var rpn = Directory.current.parent.parent.parent.path;
      await makeZipFile("${rpn}/files/${automated['zip']}");
      popd();
    } else {
      fail("Failed to determine the automated build configuration.");
    }

    popd();
    print("[Build Complete] ${name}");
  }

  await saveJsonFile("revs.json", revs);
}

void fail(String msg) {
  print("ERROR: ${msg}");
  exit(1);
}
