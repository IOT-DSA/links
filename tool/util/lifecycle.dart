part of dsa.links.repository.util;

fail(String msg, {String out}) async {
  print("ERROR: ${msg}");

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
