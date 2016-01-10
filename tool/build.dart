#!/usr/bin/env dart

import "dart:async";

import "util.dart";

main(List<String> args) async {
  var out = new StringBuffer();
  try {
    await runZoned(() async {
      await _main(args);
    }, zoneSpecification: new ZoneSpecification(print: (a, b, c, s) {
      Zone.ROOT.print(s);
      out.writeln(s);
    }));
  } catch (e, stack) {
    var buff = new StringBuffer();
    buff.writeln("Looks like there was a bug in Link Builder: ${e}");
    buff.writeln(stack);
    await fail(buff.toString(), out: out.toString(), args: args);
  }
}

_main(List<String> argv) async {
  Map<String, dynamic> config = await readJsonFile("data/config.json");
  List<Map<String, dynamic>> links = await buildLinksList();
  Map<String, String> revs = await readJsonFile("data/revs.json");
  Map<String, String> lastUpdateTimes = await readJsonFile("data/updated.json", {});
  List<String> histories = await readJsonFile("data/history.json", []);

  uuid = await generateStrongToken(length: 10);

  {
    buildTimestamp = new DateTime.now();
    var date = "${buildTimestamp.year}-"
      "${buildTimestamp.month.toString().padLeft(2, '0')}-"
      "${buildTimestamp.day.toString().padLeft(2, '0')}";
    int i = 0;
    int length = 10;

    while (histories.contains("${date}-${uuid}")) {
      uuid = await generateStrongToken(length: length);
      i++;

      if (i % 10 == 0) {
        length++;
      }
    }

    fileUuid = "${date}-${uuid}";

    histories.add(fileUuid);
  }

  String triggeredBy = Platform.environment["TEAMCITY_TRIGGER"];

  if (triggeredBy != null && triggeredBy.isNotEmpty && triggeredBy != "%teamcity.build.triggeredBy.username%") {
    await sendSlackMessage("*Build Started (by ${triggeredBy})*");
  } else {
    await sendSlackMessage("*Build Started*");
  }

  links.sort((Map a, Map b) {
    String n = a["name"];
    String x = b["name"];
    return n.compareTo(x);
  });

  await rmkdir("tmp");
  await ensureDirectory("files");

  var doBuild = argv.where((x) => !x.startsWith("--")).toList();
  var doNotBuild = [];
  var doForceBuild = [];

  for (var e in doBuild.toList()) {
    if (e.startsWith("skip:")) {
      doNotBuild.add(e.substring(5));
      doBuild.remove(e);
    } else if (e.startsWith("force:")) {
      var name = e.substring(6);
      doForceBuild.add(name);
      doBuild.remove(e);
      doBuild.add(name);
    }
  }

  List<FileUpload> uploads = [];
  List removeLinkQueue = [];
  List<Map<String, dynamic>> builtLinks = [];

  for (var link in links) {
    var name = link["displayName"];
    var rname = link["name"];
    var linkType = link["type"];

    var automated = link["automated"];
    var repo = automated["repository"];

    String zipName = automated["zip"];

    if (zipName == null) {
      zipName = "${rname}.zip";
    }

    if (link["zip"] == null) {
      String base = config["automated.zip.base"];
      if (!base.endsWith("/")) {
        base += "/";
      }
      link["zip"] = base + zipName;
    }

    link["revision"] = revs[rname];

    if (!link.containsKey("automated")) {
      continue;
    }

    if (link["automated"]["enabled"] == false) {
      continue;
    }

    if (link["enabled"] == false) {
      removeLinkQueue.add(link);
      return;
    }

    if (doBuild.isNotEmpty &&
      !doBuild.contains(rname) &&
      !doBuild.contains("type-" + linkType)) {
      continue;
    }

    if (lastUpdateTimes[rname] is! String) {
      lastUpdateTimes[rname] = new DateTime.now().toString();
    }

    link["lastUpdated"] = lastUpdateTimes[rname];

    if (argv.contains("--generate-list")) {
      continue;
    }

    print("[Build Start] ${name}");

    if (doNotBuild.contains(rname)) {
      print("[Build Skipped] ${name}");
      continue;
    }

    FileUpload upload;

    if (argv.contains("--upload-all")) {
      String currentRev = revs[rname];
      upload = new FileUpload(rname, "files/${zipName}", "files/${zipName}", revision: currentRev);
    }

    bool forceBuild = doForceBuild.contains(rname);

    await pushd("tmp/${rname}");

    // Pre-Check for References
      {
      String rev;
      var out = await exec(
        "git",
        args: [
          "ls-remote",
          repo,
          "HEAD"
        ],
        writeToBuffer: true
      );
      rev = out.output.split("\t").first.trim();
      if (!forceBuild &&
        revs[rname] is String &&
        revs[rname].split("-").first == rev &&
        !argv.contains("--force")) {
        print("[Build Up-to-Date] ${name}");
        popd();
        if (upload != null) uploads.add(upload);
        continue;
      }
    }

    var cr = await exec("git", args: [
      "clone",
      "--depth=1",
      repo,
      "."
    ], writeToBuffer: true);
    if (cr.exitCode != 0) {
      await fail("DSLink ${name}: Failed to clone repository.\n${cr.output}");
    }

    var rpo = await exec("git", args: [
      "rev-parse",
      "HEAD"
    ], writeToBuffer: true);
    var rev = rpo.output.toString().trim();
    if (rev.isEmpty) {
      rpo = await exec("git", args: [
        "rev-parse",
        "HEAD"
      ], writeToBuffer: true);
      rev = rpo.output.toString().trim();
    }

    var realRevision = rev.split("-").first;

    if (!forceBuild &&
      revs[rname] is String &&
      revs[rname].split("-").first == realRevision &&
      !argv.contains("--force")) {
      print("[Build Up-to-Date] ${name}");
      popd();
      if (upload != null) uploads.add(upload);
      continue;
    }

    String lastRevision = revs[rname];

    if (lastRevision != null && lastRevision.split("-").first == rev) {
      int count = 0;
      if (lastRevision.contains("-")) {
        try {
          count = int.parse(lastRevision.split("-").last);
        } catch (e) {
          count = new Random().nextInt(500);
        }
      }
      count++;
      rev = "${rev}-${count}";
    }

    revs[rname] = rev;
    link["revision"] = rev;

    var cbs = new File("tool/build.sh");

    if (await cbs.exists() && automated["ignoreBuildScript"] != true) {
      var result = await exec("bash", args: [cbs.path], writeToBuffer: true);
      if (result.exitCode != 0) {
        await fail("DSLink ${name}: Failed to run custom build script.\n${result.output}");
      }
    } else if (linkType == "Dart") {
      var pur = await exec("pub", args: ["upgrade"], writeToBuffer: true);
      if (pur.exitCode != 0) {
        await fail("DSLink ${name}: Failed to fetch dependencies.\n${pur.output}");
      }

      var mainFile = new File("bin/run.dart");
      if (!(await mainFile.exists())) {
        mainFile = new File("bin/main.dart");
      }

      await rmkdir("build/bin");

      var cmfr = await exec("dart2js", args: [
        mainFile.absolute.path,
        "-o",
        "build/bin/${mainFile.path
          .split('/')
          .last}",
        "--output-type=dart",
        "--categories=Server",
        "-m"
      ], writeToBuffer: true);
      if (cmfr.exitCode != 0) {
        await fail("DSLink ${name}: Failed to build main file.\n${cmfr.output}");
      }

      await copy("dslink.json", "build/dslink.json");
      await pushd("build");

      try {
        await new File("${mainFile.path
          .split('/')
          .last}.deps").delete();
      } catch (e) {}
      var rpn = Directory.current.parent.parent.parent.path;
      await makeZipFile("${rpn}/files/${zipName}");
      popd();
    } else if (linkType == "Java") {
      await rmkdir("build");
      var pur = await exec("bash", args: [
        "gradlew",
        "clean",
        "distZip",
        "--refresh-dependencies"
      ], writeToBuffer: true);
      if (pur.exitCode != 0) {
        await fail("DSLink ${name}: Failed to build the DSLink.\n${pur.output}");
      }
      var dir = new Directory("build/distributions");
      if (!(await dir.exists())) {
        await fail("DSLink ${name}: Distributions directory does not exist.");
      }

      File file = await dir.list()
        .firstWhere((x) => x.path.endsWith(".zip"), defaultValue: () => null);

      if (file == null || !(await file.exists())) {
        await fail("DSLink ${name}: Unable to find distribution zip file.");
      }

      await file.copy("../../files/${rname}.zip");
    } else {
      await fail("DSLink ${name}: Failed to determine the automated build configuration.");
    }

    upload = new FileUpload(
      rname,
      "files/${zipName}",
      "files/${zipName}",
      revision: rev
    );
    uploads.add(upload);
    popd();
    lastUpdateTimes[rname] = new DateTime.now().toString();
    link["lastUpdated"] = lastUpdateTimes[rname];
    print("[Build Complete] ${name}");
    builtLinks.add(link);
  }

  for (var toRemove in removeLinkQueue) {
    links.remove(toRemove);
  }

  uploads.add(
    new FileUpload(
      "meta.history",
      "data/history.json",
      "history.json",
      revision: uuid
    )
  );

  uploads.add(
    new FileUpload(
      "meta.revisions",
      "data/revs.json",
      "revs.json",
      revision: uuid
    )
  );

  uploads.add(
    new FileUpload(
      "meta.links",
      "links.json",
      "links.json",
      revision: uuid
    )
  );

  uploads.add(
    new FileUpload(
      "meta.updated",
      "data/updated.json",
      "updated.json",
      revision: uuid
    )
  );

  var ts = new DateTime.now();

  var history = {
    "timestamp": ts.toString(),
    "args": argv,
    "host": Platform.localHostname,
    "uuid": uuid,
    "uploads": uploads.map((FileUpload upload) {
      return upload.toJSON();
    }).toList(),
    "built": builtLinks.map((link) {
      return link["displayName"];
    }).toList()
  };

  await saveJsonFile("data/revs.json", revs);
  await saveJsonFile("links.json", links);
  await saveJsonFile("data/history.json", histories);
  await saveJsonFile("data/updated.json", lastUpdateTimes);
  await saveJsonFile("data/histories/${fileUuid}.json", history);

  String s3Bucket = config["s3.bucket"];

  if (argv.contains("--upload") || argv.contains("--upload-all")) {
    try {
      await uploadToS3(uploads, s3Bucket);
    } catch (e) {
      await fail("S3 Upload: ${e.toString()}");
    }
  }

  if (builtLinks.isNotEmpty) {
    var buff = new StringBuffer();
    var plural = builtLinks.length > 1 ? "DSLinks" : "DSLink";
    buff.writeln("*Build Completed - ${builtLinks.length} updated ${plural}:*");
    buff.writeln(builtLinks.map((link) {
      return link["displayName"];
    }).join(", "));
    await sendSlackMessage(buff.toString().trim());
  } else {
    await sendSlackMessage("*Build Completed - No DSLinks Updated*");
  }
}
