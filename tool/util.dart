library dsa.links.repository.util;

import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math";

export "dart:async";
export "dart:io";
export "dart:math" show Random;

part "util/config.dart";
part "util/execute.dart";
part "util/rand.dart";
part "util/slack.dart";
part "util/lifecycle.dart";
part "util/json.dart";
part "util/fs.dart";
part "util/s3.dart";
part "util/links.dart";

String uuid;
String fileUuid;
String currentLinkDisplayName;
String currentLinkBuild;
DateTime buildTimestamp;
List<String> gargv;

bool isOptionOn(String name) =>
  gargv != null && gargv.contains("--${name}");
bool get isDebugOn => isOptionOn("debug");
