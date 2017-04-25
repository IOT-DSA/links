

String fromUri(uri) {
  if (uri is String) uri = Uri.parse(uri);
  return Uri.decodeComponent((uri as Uri).path);
}

String dirname(String path) {
  var pt = path.trim();

  if (pt == '/') return pt;

  pt = _trimTail(path);

  var ind = pt.lastIndexOf('/');
  if (ind == -1) return '.';
  if (ind == 0) return path.substring(0, ind + 1);

  return path.substring(0, ind);
}

String join(String part1, String part2) {

  var pt1 = _trimTail(part1);
  var pt2 = _trimHead(part2);

  if (pt1 == '/') {
    if (pt2 == '/') { // Joining / and / ??
      return pt2;
    }
    return '$pt1$pt2';
  } else if (pt2 == '/') {
    return '$pt1$pt2';
  }

  return '$pt1/$pt2';
}

bool isRelative(String path) {
  var pt = path.trim();
  if (pt[0] == '/') return false;
  return true;
}

Iterable<String> split(String path) {
  var pt = _trimTail(path);
  List<String> lt = [];
  if (!isRelative(pt)) {
    lt.add('/');
  }
  lt.addAll(pt.split('/'));
  return lt;
}

String basename(String path) {
  var pt = _trimTail(path);

  if (pt == '/') return pt;
  var ind = pt.lastIndexOf('/');
  if (ind == -1) return pt;
  return pt.substring(ind + 1);
}

String joinAll(Iterable<String> parts) {
  return parts.join('/');
}

String _trimTail(String path) {
  var pt = path.trim();
  if (pt.endsWith('/') && pt.length > 1) return pt.substring(0, pt.length - 1);
  return pt;
}

String _trimHead(String path) {
  var pt = path.trim();
  if (pt.startsWith('/') && pt.length > 1) return pt.substring(1);
  return pt;
}