import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The SHA git gives a blob with [content], so local files can be compared
/// with a remote tree without downloading anything.
///
/// SHA-1 because that's how git names objects; it identifies content here
/// and protects nothing.
String gitBlobSha(List<int> content) => sha1 // NOSONAR
    .convert(
        [...utf8.encode('blob ${content.length}\x00'), ...content]).toString();
