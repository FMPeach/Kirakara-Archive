class LocalDatabase {
  const LocalDatabase();

  Future<void> open() async {
    // Reserved for drift + SQLite FTS tables.
  }

  Future<void> close() async {}
}
