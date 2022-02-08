# KRCL-Ripper

Grab a local copy of the latest krcl.org shows with playlist data, for listening on a laggy connection

Updated version of krcl-buffer. They've updated their API, so doesn't require as much scraping. 

## Notes

The timezone data provided by the KRCL / creek API is malformed. The broadcast 'start' and 'end' are in UTC and set to UTC correctly.

However, the playlist start and end times are listed as UTC, but they're actually 'America/Denver' time. 

This caused some confusion, since SQLite doesn't handle timezones and expects everything in UTC, so the timezone must be handled carefully on the application side...

The appropriate fix would be to manually adjust the timezone in the JQ parser (update-playlists.jq). But I already have a bunch of playlist data that contains this error.

So presently, after selecting playlist data, we manually set the timezone, since no conversion is actually needed...

Maybe I'll fix that someday...but they've changed their API every 6 months for the past 2 years or so which breaks the playlist parser...so maybe I'll just wait until it breaks again...if it ain't broke, don't fix it...

## TODO


### @TODO Use /archives API endpoint instead of the older /broadcasts

This version is working...but it's using the older API endpoints from the backend...should be updated to use the '/archives' endpoint, instead of grabbing all the missing broadcast data (especially since they'll probably introduce another breaking change soon...)
So fetching latest available broadcast data should use these endpoints (like the web player does):

```
https://krcl.studio.creek.org/api/studio
# No useful data for us here

https://krcl.studio.creek.org/api/archives?x=1
# Latest broadcast archives. I dunno what x=1 is for...pages are in 'meta', but web client doesn't seem to use the page data...

https://krcl.studio.creek.org/api/archives/shows-list
# List of current / archived shows and show ids
```

### @TODO Rewrite generate-cue in BASH

Currently in PHP to handle the timezone parsing easier

### Include track PREGAPs and POSTGAPs, along with FFMPEG split data

We use only the track START time to split tracks in the CUE sheet. And this mostly works, but some tracks are split
before or after the song has started. Depends on the show / DJ...sometimes they mix songs or skip songs, it's mostly due to crossfading tracks.
But song END times should be the next track split, and the difference should be recorded as PREGAP in the CUE sheet for later processing.

### Include FFMPEG split data

See the above...figure out where ffmpeg would split the track...

### GUI / Auto downloader

Make a bash menu or dialog/whiptail to download the latest.  

