.data[] | {
	"id":				.id, 
	"show_id":			.show.id, 
	"start":			.start,
	"end":				.end, 
	"tracks_processed": 0,
	"title": 			( .show.title + " - " + 
							(.start|strptime("%Y-%m-%dT%H:%M:%S.000000Z") | strftime("%Y, %b %d"))
	),
	"audiourl":			.audio.url
} | ( "REPLACE INTO broadcasts ",
			"(broadcast_id, show_id, start, end, tracks_processed, title, audiourl) ", 
		"VALUES (",
			"\(.id),",
			"\(.show_id),",
			"\(.start|tojson),",
			"\(.end|tojson),",
			"0,",
			"\(.title|tojson),",
			"\(.audiourl|tojson)", 
		");"
)
