part of dsa.links.repository.util;

dbg(String msg) {
  if (gargv == null) {
    return;
  }

  if (gargv.contains("--debug")) {
    var prefix = "[DEBUG]";
    if (currentLinkBuild != null) {
      prefix += "[${currentLinkDisplayName}]";
    }
    var lines = msg.trim().split("\n");
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line == ".") {
        continue;
      }

      print("${prefix} ${line}");
    }
  }
}

fail(String msg, {String out, bool firstLineOnlyDebug: false}) async {
  if (firstLineOnlyDebug) {
    msg = msg.split("\n").first;
  }

  print("[ERROR] ${msg}");

  if (gargv != null && gargv.contains("--test")) {
    exit(1);
  }

  var m = new StringBuffer();
  m.writeln("*Build Failed:*");
  m.writeln(msg.trim());

  var fid = await generateStrongToken();
  var map = {
    "timestamp": new DateTime.now().toString(),
    "buildId": uuid,
    "failureId": fid,
    "args": gargv,
    "message": msg
  };

  if (out != null) {
    map["output"] = out;
  }

  await saveJsonFile("data/failures/${fid}.json", map);

  if (SLACK_NOTIFY_FAIL.isNotEmpty) {
    m.writeln(SLACK_NOTIFY_FAIL.join(" "));
  }

  await sendSlackMessage(m.toString());

  exit(1);
}
