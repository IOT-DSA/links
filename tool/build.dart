import "dart:math" show Random;

import "util.dart";

main(List<String> argv) async {
  var config = await readJsonFile("data/config.json");
  var links = await buildLinksList();
  var revs = await readJsonFile("data/revs.json");

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

  Map<String, String> uploadFiles = {};
  List removeLinkQueue = [];

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

    if (doBuild.isNotEmpty && !doBuild.contains(rname) && !doBuild.contains("type-" + linkType)) {
      continue;
    }

    if (argv.contains("--generate-list")) {
      continue;
    }

    print("[Build Start] ${name}");

    if (doNotBuild.contains(rname)) {
      print("[Build Skipped] ${name}");
      continue;
    }

    if (argv.contains("--upload-all")) {
      uploadFiles["files/${zipName}"] = "files/${zipName}";
    }

    bool forceBuild = !(await new File("files/${zipName}").exists());

    forceBuild = forceBuild || doForceBuild.contains(rname);

    await pushd("tmp/${rname}");

    // Pre-Check for References
        {
      String rev;
      var out = await exec("git", args: ["ls-remote", repo, "HEAD"], writeToBuffer: true);
      rev = out.output.split("\t").first.trim();
      if (!forceBuild && revs[rname] is String && revs[rname].split("-").first == rev && !argv.contains("--force")) {
        print("[Build Up-to-Date] ${name}");
        popd();
        continue;
      }
    }

    var cr = await exec("git", args: ["clone", "--depth=1", repo, "."], writeToBuffer: true);
    if (cr.exitCode != 0) {
      fail("Failed to clone repository.\n${cr.output}");
    }

    var rpo = await exec("git", args: ["rev-parse", "HEAD"], writeToBuffer: true);
    var rev = rpo.output.toString().trim();
    if (rev.isEmpty) {
      rpo = await exec("git", args: ["rev-parse", "HEAD"], writeToBuffer: true);
      rev = rpo.output.toString().trim();
    }

    var realRevision = rev.split("-").first;

    if (!forceBuild && revs[rname] is String && revs[rname].split("-").first == realRevision && !argv.contains("--force")) {
      print("[Build Up-to-Date] ${name}");
      popd();
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
        fail("Failed to build main file.\n${cmfr.output}");
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
      var pur = await exec("bash", args: ["gradlew", "clean", "distZip", "--refresh-dependencies"], writeToBuffer: true);
      if (pur.exitCode != 0) {
        fail("Failed to build the DSLink.\n${pur.output}");
      }
      var dir = new Directory("build/distributions");
      if (!(await dir.exists())) {
        fail("Distributions directory does not exist.");
      }

      File file = await dir.list()
          .firstWhere((x) => x.path.endsWith(".zip"), defaultValue: () => null);

      if (file == null || !(await file.exists())) {
        fail("Unable to find zip file.");
      }

      await file.copy("../../files/${rname}.zip");
    } else {
      fail("Failed to determine the automated build configuration.");
    }

    uploadFiles["files/${zipName}"] = "files/${zipName}";
    popd();
    print("[Build Complete] ${name}");
  }

  for (var toRemove in removeLinkQueue) {
    links.remove(toRemove);
  }

  uploadFiles["revs.json"] = "data/revs.json";
  uploadFiles["links.json"] = "links.json";

  await saveJsonFile("data/revs.json", revs);
  await saveJsonFile("links.json", links);

  String s3Bucket = config["s3.bucket"];

  if (argv.contains("--upload") || argv.contains("--upload-all")) {
    for (String target in uploadFiles.keys.toList()) {
      String uploadPath = s3Bucket;
      if (!uploadPath.endsWith("/")) {
        uploadPath += "/";
      }
      uploadPath += target;

      String source = uploadFiles[target];

      var out = await exec("aws", args: [
        "s3",
        "cp",
        "--acl",
        "public-read",
        source,
        uploadPath,
      ], writeToBuffer: true);

      print("[Upload] ${source} => ${uploadPath}");

      if (out.exitCode != 0) {
        fail("Failed to upload '${uploadFiles[target]}' to '${uploadPath}':\n${out.output}");
      }
    }
  }
}
