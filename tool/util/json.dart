part of dsa.links.repository.util;

bool isJsonEqual(a, b) {
  return JSON.encode(a) == JSON.encode(b);
}

Future<List<dynamic>> loadJsonDirectoryList(String path, {
  bool strict: false
}) async {
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

Future<Map<String, dynamic>> loadJsonDirectoryMap(String path, {
  bool strict: false
}) async {
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

void mergeConfigurationTypes(
  Map<String, Map<String, dynamic>> types,
  String field,
  Map input) {
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

Map merge(Map a, Map b, {
  bool uniqueCollections: true,
  bool allowDirectives: false
}) {
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
        value = merge(
          value,
          bval,
          uniqueCollections: uniqueCollections,
          allowDirectives: allowDirectives
        );
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
