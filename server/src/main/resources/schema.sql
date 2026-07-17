CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'USER',
    enabled INTEGER NOT NULL DEFAULT 1,
    avatar TEXT,
    created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
    token_hash TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    expires_at INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions(expires_at);

CREATE TABLE IF NOT EXISTS favorites (
    user_id TEXT NOT NULL,
    track_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (user_id, track_id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS playlists (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    name TEXT NOT NULL,
    featured INTEGER NOT NULL DEFAULT 0,
    directory_path TEXT,
    pool_type TEXT NOT NULL DEFAULT 'NORMAL',
    created_at INTEGER NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_playlists_user ON playlists(user_id, created_at);

CREATE TABLE IF NOT EXISTS playlist_tracks (
    playlist_id TEXT NOT NULL,
    track_id TEXT NOT NULL,
    position INTEGER NOT NULL,
    added_at INTEGER NOT NULL,
    PRIMARY KEY (playlist_id, track_id),
    FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS play_history (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    track_id TEXT NOT NULL,
    played_at INTEGER NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_play_history_user ON play_history(user_id, played_at DESC);

CREATE TABLE IF NOT EXISTS playback_records (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    track_id TEXT NOT NULL,
    listened_ms INTEGER NOT NULL,
    progress_percent REAL NOT NULL,
    played_at INTEGER NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_playback_records_track ON playback_records(track_id, played_at DESC);
CREATE INDEX IF NOT EXISTS idx_playback_records_user ON playback_records(user_id, played_at DESC);

CREATE TABLE IF NOT EXISTS hidden_tracks (
    user_id TEXT NOT NULL,
    track_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (user_id, track_id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS playback_state (
    user_id TEXT PRIMARY KEY,
    queue_type TEXT NOT NULL,
    queue_context_id TEXT,
    track_id TEXT NOT NULL,
    queue_track_ids TEXT NOT NULL DEFAULT '',
    progress_ms INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS tracks (
    id TEXT PRIMARY KEY,
    path TEXT NOT NULL UNIQUE,
    file_size INTEGER NOT NULL,
    modified_at INTEGER NOT NULL,
    title TEXT NOT NULL,
    normalized_title TEXT NOT NULL,
    artist TEXT NOT NULL,
    album TEXT NOT NULL,
    track_number INTEGER,
    duration_ms INTEGER NOT NULL,
    codec TEXT NOT NULL,
    sample_rate INTEGER,
    bit_depth INTEGER,
    artwork_path TEXT,
    plain_lyrics TEXT,
    synced_lyrics TEXT,
    lyrics_source TEXT,
    metadata_status TEXT NOT NULL,
    pool_type TEXT NOT NULL DEFAULT 'NORMAL',
    audience_type TEXT NOT NULL DEFAULT 'GENERAL',
    genre TEXT NOT NULL DEFAULT '未分类',
    region TEXT NOT NULL DEFAULT 'OTHER',
    manual_edited INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS playback_batches (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    queue_type TEXT NOT NULL,
    queue_context_id TEXT,
    played_at INTEGER NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_tracks_sort ON tracks(normalized_title, id);
CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist);
CREATE INDEX IF NOT EXISTS idx_tracks_album ON tracks(album);

CREATE TABLE IF NOT EXISTS track_play_stats (
    track_id TEXT PRIMARY KEY,
    play_count INTEGER NOT NULL DEFAULT 0,
    completion_count INTEGER NOT NULL DEFAULT 0,
    completion_percent_sum REAL NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS random_queue_state (
    user_id TEXT NOT NULL,
    scope TEXT NOT NULL,
    cycle_no INTEGER NOT NULL DEFAULT 1,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (user_id, scope),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS random_track_exposures (
    user_id TEXT NOT NULL,
    scope TEXT NOT NULL,
    track_id TEXT NOT NULL,
    last_cycle INTEGER NOT NULL,
    selected_count INTEGER NOT NULL DEFAULT 1,
    last_selected_at INTEGER NOT NULL,
    PRIMARY KEY (user_id, scope, track_id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS download_tasks (
    id TEXT PRIMARY KEY,
    candidate_id TEXT NOT NULL,
    source TEXT NOT NULL,
    source_name TEXT NOT NULL,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    album TEXT NOT NULL,
    quality TEXT NOT NULL,
    artwork_url TEXT,
    target_playlist_id TEXT,
    requested_by TEXT NOT NULL,
    state TEXT NOT NULL,
    files_json TEXT NOT NULL DEFAULT '[]',
    message TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_download_tasks_created ON download_tasks(created_at DESC);

CREATE TABLE IF NOT EXISTS import_records (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    type TEXT NOT NULL,
    source TEXT NOT NULL,
    target TEXT NOT NULL,
    state TEXT NOT NULL,
    total INTEGER NOT NULL DEFAULT 0,
    succeeded INTEGER NOT NULL DEFAULT 0,
    failed INTEGER NOT NULL DEFAULT 0,
    discovered INTEGER NOT NULL DEFAULT 0,
    imported INTEGER NOT NULL DEFAULT 0,
    updated INTEGER NOT NULL DEFAULT 0,
    skipped INTEGER NOT NULL DEFAULT 0,
    added INTEGER NOT NULL DEFAULT 0,
    message TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_import_records_user ON import_records(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS directory_import_indexes (
    directory_path TEXT PRIMARY KEY,
    indexed_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS directory_track_memberships (
    directory_path TEXT NOT NULL,
    track_id TEXT NOT NULL,
    PRIMARY KEY (directory_path, track_id),
    FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_directory_track_memberships_track
    ON directory_track_memberships(track_id);

CREATE TABLE IF NOT EXISTS online_playback_sources (
    source_id TEXT PRIMARY KEY,
    enabled INTEGER NOT NULL DEFAULT 0
);
