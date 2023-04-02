#!/bin/bash
 echo 'SELECT sh.title || strftime(" %Y-%m-%d", b.start), substr(s.artist, 1, 25) || "|" || substr(s.title, 1, 60) FROM playlists p join songs s using (song_id) join shows sh using (show_id) join broadcasts b using (broadcast_id)' | sqlite3 db/krcl-playlist-data.sqlite3 | column -s '|' -t | fzf --tiebreak=index
