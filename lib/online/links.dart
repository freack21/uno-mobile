/// Invite links: `https://host/join/ROOMID-1234` (opens the app on Android)
/// or the older `https://host/#join=ROOMID-1234`.
String? joinCodeOf(Uri link) {
  final path = link.pathSegments;
  if (path.length == 2 && path[0] == 'join' && path[1].contains('-')) {
    return path[1];
  }
  if (link.fragment.startsWith('join=')) return link.fragment.substring(5);
  return null;
}
