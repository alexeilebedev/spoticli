This is a Spotify command line client that I wrote in order to port my Google Play Music playlists over
to Spotify.

Summary of the command line:

./spoticli <command>+
List of available commands
init            provide client id and secret
import_goog     <regx> Import Google Play playlist downloaded via Takeout
import_json     <jsonfile> Import JSON file containing tracks
login           Authenticate with Spotify
logout          Logout from spotify
next            Play next track
playlists       Show playlists
prev            Play previous track
search          <query>: Search for a track
search_json     <jsonfile> Look up all tracks in JSON file via Spotify
seek            <time>: seek to specified position in seconds
status          Current player status

## THE SHORT WAY

Instructions to port your Google Play Music playlists to spotify:
1. Download spoticli
2. Register as an app developer on spotify: developer.spotify.com
3. Create an app on their web site. Note client ID and client secret
4. Run ./spoticli init. Enter client id and client secret.
   If everything works, you will be logged in.
   These tokens will be saved as sfydata/client_id and sfydata/client_secret.
5. Go to www.google.com/takeout. Deselect everything, select Google Play Music.
   Download the zip file they create. Don't touch it. Spoticli will find it
6. Run ./spoticli import_goog .
   This will import all of your play lists into Spotify the best it can.

If in doubt, read and modify sfy.pl. Since this is a personal project I didn't bother
much to make a whole framework out of it.

## MORE INFO

Spoticli uses an intermediate format, a file containing a json object with an array
of track records. In addition, a standalone goog_playlists.pl tool locates Takeout downloads
in your ~/Downloads directory and converts them to the intermediate format. This is done
automatically if you run spoticli import_goog, but you can also do it by hand:

./goog_playlists.pl <regx> > tracks.json
./spoticli search_json tracks.json

This will attempt to locate Spotify track ids for all tracks in tracks.json,
and write the file back with those ids filled in. You can edit the file by hand,
and run search_json multiple times. When done, you can run

./spoticli import_json tracks.json

## NOTES ON TRACK MATCHING

This ordeal took, on and off, the whole weekend. During this time I learned that:

- Spotify web API is pretty cool, building apps is easy.

- Documentation is decent, but the formats are all over the place. Search is done with
 URL arguments, other queries use a Json request object in request body,
 yet other queries use a form, plus request headers.

- Spotify search is great, but its weakest part is special characters in track names.
 It can't handle them. I had to include a range of strategies in my track lookup code
 in order to deal with this limitation.

- Spotify has problems with rate. If I issue requests to add a playlist to a track,
 one after another, almost nothing gets added. Out of 97 tracks, 3 end up in the playlist.
 If I insert a 1 second pause after each insert, things work OK.

- Google data quality is noticeably higher. In my playlists alone,
   Morcheeba'as 'Post Humous' is misspelled as 'Post Houmous' (Why not post-hummus?)
   SETI's beacon02..beacon14 tracks are misspelled as 'beatcon'
   Shpongle's "Walking backwards through the cosmic mirror" is misspelled as "backwards thought"   
  From this we can conclude that there was some crowd-funded effort to populate
  this data.

- Sometimes it's Google's fault. In one instance, Google replaced the spanish n~ character with ?

- Google's Takeout format for music, which is one cvs file per track, is truly idiotic.
  Doesn't really matter with Perl, but it's useless for other applications.
  
## EXAMPLES OF MATCHING STRATEGIES

Some examples of the matching strategy at work:
    Found Track After 13 Attempts
    ORIGINAL QUERY             track:You Want It Darker (feat. Cantor Gideon Y. Zelermyer) album:You Want It Darker artist:Leonard Cohen
    SUCCESSFUL QUERY           track:You Want It Darker  album:You Want It Darker artist:Leonard Cohen
    STRATEGY                  remove last parenthesis from title


    Found Track After 7 Attempts
    ORIGINAL QUERY             track:It's Now or Never album:Elv1s: 30 #1 Hits artist:Elvis Presley
    SUCCESSFUL QUERY           track:It's Now or Never artist:Elvis Presley
    STRATEGY                  omitting artist name

    Found Track After 13 Attempts
    ORIGINAL QUERY             track:Mis dos peque?as album:Cachaito artist:Cachaito Lopez
    SUCCESSFUL QUERY           track:Mis dos album:Cachaito artist:Cachaito Lopez
    STRATEGY                  remove word containing ? character

## FILES

- lib.pl contains library functions as pget/pset (persistence)
  and syscmd

- spoticli is the main client. You can specify multiple words on the command line,
  e.g. ./spoticli next next
  to skip 2 tracks forward

- You can run VERBOSE=1 ./spoticli if you want to trace all subprocess invocations

- sfy.pl is a simple module implementing all Spotify queries.
  It supports the track searching strategies.
  Also implements auto-login in case the token expires.

- goog_playlists.pl is a google play playlist converter
