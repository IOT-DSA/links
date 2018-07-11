part of dsa.links.repository.util;

final List<String> SLACK_NOTIFY_FAIL = [
  "<@butlermatt>"
];

sendSlackMessage(String message) async {
  message = message.trim();

  String slackChannel = Platform.environment["SLACK_CHANNEL"];
  String slackToken = Platform.environment["SLACK_TOKEN"];

  if (slackChannel == null || slackToken == null) {
    return;
  }

  String slackUrl =
    "https://slack.com/api/chat.postMessage";

  Map json = {
    "token": slackToken,
    "channel": slackChannel,
    "text": message,
    "username": "Automated Builder",
    "icon_url": "https://pbs.twimg.com/profile_images/623228341714182145/kdkH3j37_400x400.png"
  };

  for (String line in message.split("\n")) {
    print("[Slack Message] ${line}");
  }

  var client = new HttpClient();

  Uri uri = Uri.parse(slackUrl);
  uri = uri.replace(queryParameters: json);

  try {
    var request = await client.getUrl(uri);
    var response = await request.close();
    var bytes = await response.fold([], (List a, List b) {
      return a..addAll(b);
    });

    var result = const JsonDecoder().convert(
      const Utf8Decoder().convert(bytes)
    );

    if (response.statusCode != 200) {
      throw new Exception("Status Code: ${response.statusCode}\nResult: ${result}");
    }
  } catch (e) {
    print("[MAJOR ERROR] Failed to send Slack message: ${e}");
  } finally {
    client.close(force: true);
  }
}
