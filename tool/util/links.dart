part of dsa.links.repository.util;

Future<List<Map<String, dynamic>>> buildLinksList() async {
  var links = await loadJsonDirectoryList("data/links");
  var typeRules = await loadJsonDirectoryMap("data/types");
  var mixins = await loadJsonDirectoryMap("data/mixins");
  var config = await readJsonFile("data/config.json");

  for (Map l in links) {
    mergeConfigurationTypes(typeRules, "type", l);
    mergeConfigurationTypes(mixins, "mixins", mixins);
  }

  crawlDataAndSubstituteVariables(links, config);

  return links;
}
