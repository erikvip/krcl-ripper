
#!/bin/bash
# echo 'SELECT sh.title || strftime(" %Y-%m-%d", b.start) AS start_time, substr(s.artist, 1, 25) || "|" || substr(s.title, 1, 60) AS title FROM playlists p join songs s using (song_id) join shows sh using (show_id) join broadcasts b using (broadcast_id) ORDER BY start_time DESC' | sqlite3 db/krcl-playlist-data.sqlite3 | column -s '|' -t | fzf --tiebreak=index
	_sql=$(cat << END_QUERY
	SELECT 
		sh.title || strftime(" %Y-%m-%d", b.start) AS start_time, 
		substr(s.artist, 1, 25) || "|" || substr(s.title, 1, 60) AS title 
	FROM playlists p 
		join songs s using (song_id) 
		join shows sh using (show_id) 
		join broadcasts b using (broadcast_id) 
	ORDER BY p.start DESC
END_QUERY
);
 
	echo "$_sql" | sqlite3 -separator "|" db/krcl-playlist-data.sqlite3 \
	| column -s '|' -t | fzf --no-sort --tiebreak=index

