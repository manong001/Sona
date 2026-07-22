CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'USER',
    enabled INTEGER NOT NULL DEFAULT 1,
    avatar TEXT,
    display_name TEXT,
    signature TEXT NOT NULL DEFAULT '',
    last_seen_at INTEGER,
    last_login_at INTEGER,
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

CREATE TABLE IF NOT EXISTS friendships (
    user_low_id TEXT NOT NULL,
    user_high_id TEXT NOT NULL,
    created_by TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (user_low_id, user_high_id),
    CHECK (user_low_id < user_high_id),
    FOREIGN KEY (user_low_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (user_high_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS social_media (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    mime_type TEXT NOT NULL,
    original_name TEXT NOT NULL,
    group_id TEXT,
    component TEXT,
    storage_path TEXT NOT NULL UNIQUE,
    size_bytes INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    sender_id TEXT NOT NULL,
    recipient_id TEXT NOT NULL,
    client_message_id TEXT,
    kind TEXT NOT NULL,
    text TEXT,
    payload_json TEXT,
    created_at INTEGER NOT NULL,
    recalled_at INTEGER,
    read_at INTEGER,
    FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (recipient_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE (sender_id, client_message_id)
);

CREATE INDEX IF NOT EXISTS idx_messages_pair
    ON messages(sender_id, recipient_id, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_unread
    ON messages(recipient_id, read_at, created_at);

CREATE TABLE IF NOT EXISTS moments (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    text TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS moment_media (
    moment_id TEXT NOT NULL,
    media_id TEXT NOT NULL,
    position INTEGER NOT NULL,
    PRIMARY KEY (moment_id, media_id),
    FOREIGN KEY (moment_id) REFERENCES moments(id) ON DELETE CASCADE,
    FOREIGN KEY (media_id) REFERENCES social_media(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS moment_likes (
    moment_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (moment_id, user_id),
    FOREIGN KEY (moment_id) REFERENCES moments(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS moment_comments (
    id TEXT PRIMARY KEY,
    moment_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    body TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (moment_id) REFERENCES moments(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_moments_created_at ON moments(created_at DESC);

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
    artwork_track_id TEXT,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_playlists_user ON playlists(user_id, created_at);

CREATE TABLE IF NOT EXISTS home_items (
    user_id TEXT NOT NULL,
    item_id TEXT NOT NULL,
    position INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (user_id, item_id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS playlist_order_items (
    user_id TEXT NOT NULL,
    playlist_id TEXT NOT NULL,
    position INTEGER NOT NULL,
    PRIMARY KEY (user_id, playlist_id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_playlist_order_items_user_position
    ON playlist_order_items(user_id, position);

CREATE TABLE IF NOT EXISTS playlist_tracks (
    playlist_id TEXT NOT NULL,
    track_id TEXT NOT NULL,
    position INTEGER NOT NULL,
    added_at INTEGER NOT NULL,
    PRIMARY KEY (playlist_id, track_id),
    FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS playlist_subscriptions (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    playlist_id TEXT NOT NULL UNIQUE,
    source_url TEXT NOT NULL,
    name TEXT NOT NULL,
    artwork_url TEXT,
    pool_type TEXT NOT NULL DEFAULT 'NORMAL',
    auto_download INTEGER NOT NULL DEFAULT 0,
    sync_interval_hours INTEGER NOT NULL DEFAULT 24,
    enabled INTEGER NOT NULL DEFAULT 1,
    last_synced_at INTEGER,
    last_error TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    UNIQUE (user_id, source_url),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_playlist_subscriptions_due
    ON playlist_subscriptions(enabled, last_synced_at, updated_at);

CREATE TABLE IF NOT EXISTS playlist_subscription_items (
    subscription_id TEXT NOT NULL,
    item_key TEXT NOT NULL,
    position INTEGER NOT NULL,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    album TEXT,
    matched_track_id TEXT,
    state TEXT NOT NULL,
    last_seen_at INTEGER NOT NULL,
    PRIMARY KEY (subscription_id, item_key),
    FOREIGN KEY (subscription_id) REFERENCES playlist_subscriptions(id) ON DELETE CASCADE
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
    artwork_source TEXT,
    plain_lyrics TEXT,
    synced_lyrics TEXT,
    lyrics_source TEXT,
    metadata_status TEXT NOT NULL,
    pool_type TEXT NOT NULL DEFAULT 'NORMAL',
    audience_type TEXT NOT NULL DEFAULT 'GENERAL',
    genre TEXT NOT NULL DEFAULT '未分类',
    related_genres TEXT NOT NULL DEFAULT '',
    region TEXT NOT NULL DEFAULT 'OTHER',
    manual_edited INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS ai_settings (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    enabled INTEGER NOT NULL DEFAULT 0,
    base_url TEXT NOT NULL,
    api_key_ciphertext TEXT NOT NULL DEFAULT '',
    model TEXT NOT NULL,
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
CREATE INDEX IF NOT EXISTS idx_tracks_subscription_match
    ON tracks(
        trim(title) COLLATE NOCASE,
        replace(trim(artist), '、', '/') COLLATE NOCASE
    );

CREATE TABLE IF NOT EXISTS track_audio_features (
    track_id TEXT PRIMARY KEY,
    version INTEGER NOT NULL,
    file_size INTEGER NOT NULL,
    modified_at INTEGER NOT NULL,
    vector TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
);

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
CREATE INDEX IF NOT EXISTS idx_download_tasks_subscription_match
    ON download_tasks(
        trim(title) COLLATE NOCASE,
        replace(trim(artist), '、', '/') COLLATE NOCASE,
        state
    );

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
