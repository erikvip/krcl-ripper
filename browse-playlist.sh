#!/bin/bash
_sql=$(cat << END_QUERY
	SELECT 
		strftime("%Y-%m-%d %H:%M:%S", p.start), 
		strftime("%H:%M:%S", p.end), 
		sh.name, 
		s.artist,
		s.title 
	FROM playlists p 
		join songs s using (song_id) 
		join broadcasts b using (broadcast_id) 
		join shows sh using (show_id) 
	ORDER BY p.start DESC;
END_QUERY
);

echo "$_sql" | sqlite3 -csv db/krcl-playlist-data.sqlite3 | tabview -
