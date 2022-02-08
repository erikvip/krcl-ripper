CREATE TABLE shows (show_id int primary key not null, title text, name varchar(255), updated_at DATETIME);
CREATE TABLE broadcasts (broadcast_id int primary key not null, show_id int, start datetime, end datetime, tracks_processed int default 0 not null, title text, audiourl text);
CREATE TABLE songs (song_id int primary key not null, artist text, title text, album text, label text, year int);
CREATE TABLE IF NOT EXISTS "playlists" (playlist_id int not null, broadcast_id int not null, show_id int not null, song_id int not null, start datetime, end datetime, PRIMARY KEY (playlist_id, broadcast_id, show_id));
