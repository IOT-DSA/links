import "util.dart";

main(List<String> argv) async {
  var links = await buildLinksList();
  var revs = await readJsonFile("data/revs.json");

  await rmkdir("tmp");

  var doBuild = argv.where((x) => !x.startsWith("--")).toList();

  for (var link in links) {
    if (argv.contains("--generate-list")) {
      continue;
    }

    if (doBuild.isNotEmpty && !doBuild.contains(link["name"])) {
      continue;
    }

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
    await pushd("tmp/${name}");
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

    if (revs.containsKey(rname) && revs[rname] == rev && !argv.contains("--force")) {
      print("[Build Up-to-Date] ${name}");
      popd();
      continue;
    }

    revs[rname] = rev;

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
        "build/bin/${mainFile.path.split('/').last}",
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
        await new File("${mainFile.path.split('/').last}.deps").delete();
      } catch (e) {
      }
      var rpn = Directory.current.parent.parent.parent.path;
      await makeZipFile("${rpn}/files/${automated['zip']}");
      popd();
    } else {
      fail("Failed to determine the automated build configuration.");
    }

    popd();
    print("[Build Complete] ${name}");
  }

  await saveJsonFile("data/revs.json", revs);
  await saveJsonFile("links.json", links);
}
