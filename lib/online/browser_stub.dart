final _memory = <String, String>{};

String? readStored(String key) => _memory[key];

void writeStored(String key, String? value) {
  if (value == null) {
    _memory.remove(key);
  } else {
    _memory[key] = value;
  }
}

Future<bool> shareLink({
  required String title,
  required String text,
  required String url,
}) async => false;

void setPageColors({required String background, required bool dark}) {}
