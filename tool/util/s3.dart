part of dsa.links.repository.util;

uploadToS3(List<FileUpload> uploads, String s3Bucket) async {
  for (var upload in uploads) {
    String uploadPath = s3Bucket;
    if (!uploadPath.endsWith("/")) {
      uploadPath += "/";
    }
    uploadPath += upload.target;

    var file = new File(upload.source);

    if (!(await file.exists()) && !upload.onlyIfExists) {
      throw new UploadError(upload, "Source file does not exist.");
    }

    print("[Upload Start] ${upload.source} => ${upload.target}");

    {
      var out = await exec("aws", args: [
        "s3",
        "cp",
        "--acl",
        "public-read",
        upload.source,
        uploadPath
      ], writeToBuffer: true);

      if (out.exitCode != 0) {
        var msg = "Put Operation Failed (exit: ${out.exitCode})\n";
        msg += "Command Output:\n";
        msg += out.output;
        throw new UploadError(upload, msg);
      }
    }

    if (upload.revision != null) {
      String revisionUploadPath = s3Bucket;
      if (revisionUploadPath.endsWith("/")) {
        revisionUploadPath = revisionUploadPath.substring(1);
      }
      var split = upload.target.split("/");
      var name = split.last;
      var dir = split.take(split.length - 1).join("/");
      revisionUploadPath += "/versions/${upload.tag}/${upload.revision}/${dir}/${name}";
      revisionUploadPath = revisionUploadPath.replaceAll("//", "/");
      revisionUploadPath = revisionUploadPath.replaceAll("s3:/", "s3://");
      var out = await exec("aws", args: [
        "s3",
        "cp",
        "--acl",
        "public-read",
        uploadPath,
        revisionUploadPath
      ], writeToBuffer: true);

      if (out.exitCode != 0) {
        var msg = "Put Operation Failed for Versioning (exit: ${out.exitCode})\n";
        msg += "Command Output:\n";
        msg += out.output;
        throw new UploadError(upload, msg);
      }
    }

    print("[Upload Complete] ${upload.source} => ${upload.target}");
  }
}

class UploadError {
  final FileUpload upload;
  final String message;

  UploadError(this.upload, this.message);

  @override
  String toString() => "Failed to execute upload job '${upload}': ${message}";
}

class FileUpload {
  final String tag;
  final String source;
  final String target;

  String revision;
  bool onlyIfExists;

  FileUpload(this.tag, this.source, this.target, {
    this.revision,
    this.onlyIfExists: false
  });

  @override
  String toString() {
    var msg = "${source} => ${target}";

    if (revision != null) {
      msg += " (revision: ${revision})";
    }

    return msg;
  }

  Map toJSON() {
    return {
      "tag": tag,
      "source": source,
      "target": target,
      "revision": revision
    };
  }
}
