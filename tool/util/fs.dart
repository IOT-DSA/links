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
  Directory.current = dir;
}

Future<dynamic> readJsonFile(String path, [defaultValue]) async {
  var file = new File(path);

  if (!(await file.exists()) && defaultValue != null) {
    return defaultValue;
  }

  var content = await file.readAsString();
  return JSON.decode(content);
}

Future saveJsonFile(String path, value) async {
  var file = new File(path);
  await file.create(recursive: true);
  var content = const JsonEncoder.withIndent("  ").convert(value);
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

void popd() {
  if (_dirStack.isEmpty) {
    throw new Exception("No Directory to Pop from the Stack");
  }

  Directory.current = _dirStack.removeLast();
}

ensureDirectory(String path) async {
  var dir = new Directory(path);
  if (!(await dir.exists())) {
    await dir.create(recursive: true);
  }
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
