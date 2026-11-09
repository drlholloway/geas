/// The result of [mergeLines].
class LineMerge {
  const LineMerge(this.text, {required this.conflict});

  /// The merged text, or null if [conflict].
  final String? text;

  /// Both sides changed the same region of the base differently.
  final bool conflict;
}

/// Three-way merge of [local] and [remote] against [base], line by line
/// (diff3). Changes to separate regions combine; changes to the same region
/// conflict unless they're identical.
LineMerge mergeLines(String base, String local, String remote) {
  if (local == remote) return LineMerge(local, conflict: false);
  if (local == base) return LineMerge(remote, conflict: false);
  if (remote == base) return LineMerge(local, conflict: false);

  final o = base.split('\n'), a = local.split('\n'), b = remote.split('\n');
  final toA = _matches(o, a), toB = _matches(o, b);
  final out = <String>[];
  var io = 0, ia = 0, ib = 0;
  while (true) {
    // Copy lines that are unchanged on both sides.
    if (io < o.length && toA[io] == ia && toB[io] == ib) {
      out.add(o[io]);
      io++;
      ia++;
      ib++;
      continue;
    }
    // The next base line both sides kept, or the end of every text.
    var next = io;
    while (next < o.length && (toA[next] == null || toB[next] == null)) {
      next++;
    }
    final endA = next < o.length ? toA[next]! : a.length;
    final endB = next < o.length ? toB[next]! : b.length;
    final chunkO = o.sublist(io, next);
    final chunkA = a.sublist(ia, endA);
    final chunkB = b.sublist(ib, endB);
    if (_same(chunkA, chunkO)) {
      out.addAll(chunkB);
    } else if (_same(chunkB, chunkO) || _same(chunkA, chunkB)) {
      out.addAll(chunkA);
    } else if (chunkA.length == chunkO.length &&
        chunkB.length == chunkO.length) {
      // Both replaced the same lines one for one, as when two devices check
      // off neighboring checklist items: merge each line on its own.
      for (var k = 0; k < chunkO.length; k++) {
        if (chunkA[k] == chunkO[k] || chunkA[k] == chunkB[k]) {
          out.add(chunkB[k]);
        } else if (chunkB[k] == chunkO[k]) {
          out.add(chunkA[k]);
        } else {
          return const LineMerge(null, conflict: true);
        }
      }
    } else {
      return const LineMerge(null, conflict: true);
    }
    if (next >= o.length) break;
    io = next;
    ia = endA;
    ib = endB;
  }
  return LineMerge(out.join('\n'), conflict: false);
}

/// For each line of [o], its index in [x] under a longest common
/// subsequence, or null if it was removed.
List<int?> _matches(List<String> o, List<String> x) {
  final n = o.length, m = x.length;
  // lcs[i][j]: LCS length of o[i..] and x[j..].
  final lcs = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = o[i] == x[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final result = List<int?>.filled(n, null);
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (o[i] == x[j]) {
      result[i++] = j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return result;
}

bool _same(List<String> x, List<String> y) {
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}
