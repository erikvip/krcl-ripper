#!/bin/bash
_sql=$(cat << END_QUERY
	SELECT 
		'start' as start, 
		'show' as name, 
		'show_id' as show_id,
		'broadcast_id',
		'url' as audiourl
	UNION
	SELECT
		strftime("%Y-%m-%d %H:%M:%S", b.start) AS start, 
		sh.name, 
		sh.show_id,
		b.broadcast_id,
		b.audiourl
	FROM broadcasts b 
		join shows sh using (show_id) 
	ORDER BY start DESC LIMIT 100;
END_QUERY
);

echo "$_sql" | sqlite3 -csv db/krcl-playlist-data.sqlite3 | tabview -
