part of dsa.links.repository.util;

Future<String> generateStrongToken({int length: 50}) async {
  var r0 = new Random();
  var buffer = new StringBuffer();
  for (int i = 1; i <= length; i++) {
    await new Future.value();
    var r = new Random(r0.nextInt(0x70000000) + (new DateTime.now()).millisecondsSinceEpoch);
    if (r.nextBool()) {
      String letter = _alphabet[r.nextInt(_alphabet.length)];
      buffer.write(r.nextBool() ? letter.toLowerCase() : letter);
    } else {
      buffer.write(_numbers[r.nextInt(_numbers.length)]);
    }
  }
  return buffer.toString();
}

const List<String> _alphabet = const [
  "A",
  "B",
  "C",
  "D",
  "E",
  "F",
  "G",
  "H",
  "I",
  "J",
  "K",
  "L",
  "M",
  "N",
  "O",
  "P",
  "Q",
  "R",
  "S",
  "T",
  "U",
  "V",
  "W",
  "X",
  "Y",
  "Z"
];

const List<int> _numbers = const [
  0,
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9
];

const List<String> _specials = const [
  "@",
  "=",
  "_",
  "+",
  "-",
  "!",
  "."
];
