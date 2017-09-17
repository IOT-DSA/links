part of dsa.links.repository.util;

Directory getDir(String path) => new Directory(path);
File getFile(String path) => new File(path);

List<Directory> _dirStack = [];

pushd(String path) async {
  _dirStack.add(Directory.current);
  var dir = new Directory(path);
  if (!(await dir.exists())) {
    await dir.create(recursive: true);
  }
  cd(dir.path);
}

Future<dynamic> readJsonFile(String path, {defaultValue, String shadow}) async {
  var file = new File(path);
  var shadowFile = shadow is String ? new File(shadow) : null;

  Future<dynamic> handleShadow(dynamic input) async {
    if (shadowFile == null || !(await shadowFile.exists())) {
      return input;
    }

    if (input is! Map) {
      return input;
    }

    var shadowContent = await shadowFile.readAsString();
    var json = JSON.decode(shadowContent);
    var result = merge(input, json, allowDirectives: true);
    dbg("[Load Shadow JSON] ${path}");
    return result;
  }

  if (!(await file.exists()) && defaultValue != null) {
    return await handleShadow(defaultValue);
  }

  var content = await file.readAsString();
  dbg("[Load JSON] ${path}");
  return await handleShadow(JSON.decode(content));
}

Future saveJsonFile(String path, value) async {
  var file = new File(path);
  await file.create(recursive: true);
  var content = const JsonEncoder.withIndent("  ").convert(value);
  await file.writeAsString(content + "\n");

  dbg("[Write JSON] ${path}");
}

void cd(String path) {
  var dir = new Directory(path);
  Directory.current = dir;
  dbg("[Change Directory] ${path}");
}

Future makeZipFile(String target) async {
  var tf = new File(target);

  if (await tf.exists()) {
    await tf.delete(recursive: true);
  } else if (!(await tf.parent.exists())) {
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

  dbg("[Create ZIP] ${target}");
}

void popd() {
  if (_dirStack.isEmpty) {
    throw new Exception("No Directory to Pop from the Stack");
  }

  cd(_dirStack.removeLast().path);
}

ensureDirectory(String path) async {
  var dir = new Directory(path);
  if (!(await dir.exists())) {
    await dir.create(recursive: true);
    dbg("[Make Directory] ${path}");
  }
}

rmkdir(String path) async {
  var dir = new Directory(path);
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
  await dir.create(recursive: true);
  dbg("[Make Directory] ${path}");
}

Future<File> copy(String from, String to) async {
  var ff = new File(from);
  var tf = new File(to);

  if (!(await tf.exists())) {
    await tf.create(recursive: true);
  }

  dbg("[Copy] ${from} => ${to}");

  return await ff.copy(tf.path);
}
