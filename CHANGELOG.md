# Changelog

All notable changes to DrivePlay (target `CarTV`) are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Security

- **The screen stream's token was 32 bits wide.** The stream is the phone's
  **screen**, served over the local network, and the token in its path is the
  only thing that keeps it private — eight hex characters are 2³² guesses,
  which is a weekend's work for anyone on the same Wi-Fi. The token is **128
  bits** now — one unbroken string of hex, so it needs no escaping in the
  URL path and in the relay's announcement.

- **A failed stream logged the account's token.** The playback error was
  logged as it was, and an `NSError`'s description carries the URL that
  failed — which is where Plex's token, Jellyfin's API key and Xtream's
  password live. The device's log is readable by anything attached to the
  phone. The log keeps the **host and the file name** now.

- **The browser logged the URL the user typed.** A pasted
  `https://user:password@host/` put the password in the log. The same
  redaction applies.

### Fixed

- **The phone's screen went black when the car launched the app.**
  The scene delegates carried an `@objc(Name)` attribute, which gives a class
  the Objective-C runtime name **without** the module prefix
  ("CarPlaySceneDelegate"), while the manifest asks for
  "CarTV.CarPlaySceneDelegate". `NSClassFromString` answered **nil**, so a
  scene built from the manifest — which is what happens when the **car**
  launches the app, before the app delegate can be asked — got **no delegate**,
  and CarPlay raised an NSException inside
  `-[CPTemplateApplicationScene _deliverInterfaceControllerToDelegate]`:
  SIGABRT, the app died, and the phone's window was black. The three crashes
  two seconds apart were the system relaunching the app in a loop. The
  attribute is gone, the manifest's names resolve, and a test reads the
  **running** app's manifest to keep it that way.

- **An offline vault video never reached the car's display.**
  Two faults in one chain. The **fullscreen player's dismissal** — which is
  how the car takes the picture — put the phone's mode back to the docked
  player, so the phone started drawing the video again and the app's own
  output was detached with it; and the app kept **no output of its own**
  while the picture was on its way to the car, where the phone's own view is
  not drawn (the CarPlay scene is in front). A video-only `AVPlayerItem`
  never renders without an output: CoreMedia waits for one that never comes,
  the playhead never leaves zero, the phone says "Loading Stream…" and the
  car's display stays black. The app keeps an output of its own for as long
  as the picture is wanted on the car, and the fullscreen dismissal no longer
  takes the picture back.

- **The offline vault's video died the moment the car took the picture.**
  The vault was played from a `file://` URL inside the app's container, and the
  car's display is fed by the system's **own** video target — a process that
  runs **outside** the app's sandbox. The target cannot open a sandboxed file,
  so the item failed with **-11870**
  (`AVErrorExternalPlaybackNotSupportedForAsset`) the moment the car's route
  took the picture, and the video died on the phone **and** on the car. The
  file is now **served over HTTP** and the player is given that URL — the same
  way the browser's picture reaches the car. The player seeks, so the file is
  served in ranges. The serving happens in `play(channel:)` — the one way in —
  so the vault's own tap, the watch history's "watch again" row and the
  CarPlay rows all get it. The server is bound to the phone's **loopback** and
  every path carries a **256-bit** token, compared in constant time.

- **The hand-off's re-offers restarted the clip.**
  The picture is offered to the car again and again (the car's video
  endpoint appears a couple of minutes after the scene connects), and every
  offer attaches the item again — which starts the video at the beginning.
  Putting the position back was not enough: the player resets the item to
  zero **while** it prepares it again, and the seek that followed was thrown
  away with it (measured on the phone — the playhead jumped back to 0 after
  every offer, so the clip played again and again and the phone said
  "Loading Stream…" the whole time). The offer now brings a **new** item for
  the same asset, and the new one starts where the old one was. A clip that
  has ended starts again — the car wants to see the video.

- **A browser row never asked the car for the video surface.**
  The page reaches the car as a **picture the app plays**, and the system
  draws that picture in the now-playing area — but only when the row that
  was picked asks for video. The Browser tab's rows carried no
  `playbackConfiguration` at all, so the car stayed on the list with nothing
  to draw. The site's rows and the row that shows the page on the car ask
  for the video surface now, the way a channel row does.

- **The car's keyboard clicked the row behind it.**
  The address bar's results were the **whole catalogue of sites** — seventeen
  rows with big tiles — so a row was always sitting under the keyboard that
  floats over the bottom of the car's list, and the key press landed on the
  row instead of the key. The address bar's list is **short** now: the way
  back, what the user typed, and a couple of matches. The whole catalogue is
  in the Browser tab's own list, one tap away.

- **A site could not be found by its name.**
  The results matched the **address** only, so "HBO Max", "Prime Video",
  "Sony LIV" and "iQIYI" found nothing — the name is what the user reads on
  the row, and "HBO Max" is nowhere in "max.com". A site answers to its name
  as well as to its address now.

- **The car's browser was a remote control for the phone.**
  CarPlay has **no web template** — there is none in `CarPlay.framework` at
  all — so a template browser can never show a page itself. The Browser tab
  used to hand every address to the **phone**, which is what made the car's
  browser nothing but a remote control for the iPhone. The app's own web
  view now runs the page **for the car**: the page is captured into frames,
  encoded and served as the very stream the app plays, so the car draws the
  page on its own display. The car's rows — Back, Forward, Reload, the two
  scrolls and Close — drive that web view. The app's own car screen (the
  external-display scene) and the phone's screen share survive as the
  fallbacks.

- **The video did not start on the car's display.**
  A video the user started **on the phone** was handed off, but a video the
  **car** asked for was offered to the car's display exactly **once** — at the
  moment the row was tapped. The car's video endpoint appears up to two
  minutes later, and the system only looks at the AirPlay route when the
  picture is offered, so that single offer found no endpoint and the car's
  screen stayed black. Every car-wanted play now carries the ladder of
  re-offers, and the ladder **repeats** (the old one stopped after 45
  seconds, long before the endpoint was there).

  The ladder also caused the "laggy" start: it offered the picture at 1 s and
  3 s — right on the start — and every offer rebuilds the player and drops
  the buffer. The first gap is now long enough for the video to start, and
  the gaps grow from there.

- **A page opened on the car played on the phone, not on the car.**
  The screen share is the only way a page reaches the car (CarPlay has no web
  view of its own), and the share played through the player's own hand-off
  path — which it never took. The share is now handed off to the car like any
  other video. And because iOS always asks the **user** to start a share, the
  phone now says that the car is waiting, with the button that starts it.

- **The browser tab died and the app went back to the home screen.**
  The **cause** was the ad blocker: it took the rules away and put them back
  on **every navigation**, on the live web view's content controller. A
  `WKWebViewConfiguration` is copied when the web view is made, but its
  `userContentController` is a **shared reference** — so the rule store of
  the content process was torn down **under the page that was loading**. The
  device's own log says what that does: the GPU process and every web
  content process die with `reason=Crash`. The rules are applied **once**
  now.

  The crash handler then made it worse: it emptied the tab's address, and an
  empty address **is** the start page — so the page was thrown away and the
  user was back at the home screen. The address is **kept** now, and the page
  is reloaded **once**: a reload in a loop loads the page that killed the
  process again, kills it again, and takes the app down with it.

  The car's browser also no longer builds its result list again for **every
  keystroke** — the list is built once and filtered, so the pictures are not
  drawn again and again.

- **Typing in the phone's browser closed it.**
  The address bar at the bottom and the start page's own search box were
  **one** text field: what was typed in one of them appeared in the other,
  and the bar was filled over the text the user had already typed — so the
  typing looked like it did nothing at all. They are two fields now, each
  with its own text, and the bar is only filled **while it is empty**.

- **The car's Browser tab was dead.**
  Its search bar was **presented** with `presentTemplate`, which accepts only
  an action sheet, an alert and voice control — so the presentation failed
  every time and the Search button did nothing at all. It is **pushed** onto
  the stack now. A pushed search template cannot carry a navigation bar
  button (`CPSearchTemplate` does not conform to `CPBarButtonProviding`), so
  the way back is a row of the search's own list — *"Back to sites"* and
  *"Back to channels"*. And the channel search no longer rebuilds thirty rows
  (and thirty pictures at the car's scale) for **every keystroke**.

- **A page the car asked for never came to the phone.**
  The car's browser opened the page in the phone's browser tab — and the
  phone stayed on the tab it was on, because the tab was a `@State` **inside**
  the view, so nothing outside it could change it. The share the car needs
  captures **the phone's screen**, so the car was waiting for a share of the
  wrong screen: the car asked, and neither screen showed anything. The tab is
  shared now, and a page the car asks for brings the browser to the front.

- **The compass showed the wrong direction.**
  The GPS **course** (the direction of travel — noise while the car is slow)
  overwrote the compass on every GPS fix, and the rose turned *with* the
  heading instead of against it: a car heading east has north on its **left**.
  The compass now wins, the course is only the fallback for a device without
  one, the heading is normalised, and the needle is **fixed** while the rose
  turns under it (a needle inside the rose turns with it and always says
  north).

- **The compass was still wrong, and it was not smooth.**
  Three separate faults, all measured on the phone (the device's own log:
  *"magneticHeading 266.75 trueHeading 267.05 **accuracy 27.58**"*):

  1. **The heading was out by tens of degrees and was shown anyway.**
     CoreLocation reports the **error** of a heading in degrees; a phone
     lying flat has no usable horizontal field to read a heading from, and
     its error grows into the tens of degrees. A needle that follows such a
     reading points the wrong way — which is worse than the GPS's course.
     A reading the compass is out by more than twenty degrees is now refused,
     the GPS's course takes over, and the panel says **GPS COURSE** instead
     of pretending the compass knows.
  2. **The smoothing counted readings, not seconds.** The magnetometer
     delivers several times a second and the GPS once a second, so a filter
     that closes a third of the gap per *reading* smooths one of them and
     not the other. The filter now runs on a **clock**, so the rose moves by
     how much *time* has passed — and a burst of readings that arrive
     together moves it by as little as one that arrives alone. (Measured:
     two readings a second apart were delivered 128 ms apart — the jolt the
     user saw.)
  3. **A red needle said "north" while the letters said something else.**
     The needle is **fixed** (it points the way the car faces) but it was
     painted like a compass needle — red for north — so it always pointed up
     while the rose turned under it. It is the vehicle's direction marker
     now, in the car's green; the rose's red **N** is the only north marker.
  4. **The filter's clock could be dragged backwards.** The clock runs on the
     moment a reading **arrived** — what the user sees is when the needle
     moved, not when the field was measured — and it only ever moves
     **forward**. A reading that arrives late (a buffered one whose own stamp
     is older than the reading already applied) no longer moves the needle
     and no longer drags the clock back, which would make the next reading
     close a gap that never happened.

  The rose's rotation is continuous as well, so it no longer spins 358° the
  long way round every time the heading crosses north.

- **The ad blocker broke the sign-in of the sites that use a captcha.**
  The truth, measured against the real SonyLIV page and against a real
  `WKWebView`: **no rule ever matched the reCAPTCHA addresses** — the captcha's
  script and its frames were allowed through all along. The page broke for
  four other reasons, and all four are fixed:

  1. **the block rules never stopped an ad at all.** They named the ad hosts
     with `if-domain`, and `if-domain` reads the **top document's** host, not
     the host of the request — so a rule for the host of an image never
     stopped that image. The rules now match the **host of the request** with
     a filter that is anchored to it, so a page that merely *mentioned* a
     blocked host in its query string (Google's own collector carries
     `&scrsrc=www.googletagmanager.com`) keeps its own request;
  2. the rule that hides the ad boxes ran on **every page and every frame**,
     so it could hide a captcha badge — and a captcha badge lives in a
     third-party frame. It now runs on the page alone
     (`load-type: ["first-party"]`), and it excepts the captcha and identity
     providers;
  3. **the whole rule list did not compile.** WebKit compiles it as one
     thing, and one value it does not know (`load-type: ["top-frame"]`, or a
     glob that starts with `*://`) kills **every** rule — the blocker was
     simply dead, and only the log said so. A test now compiles the list the
     app really hands over;
  4. the **tag manager** was blocked, and a site's *own* setup travels
     through it — SonyLIV's sign-in page took its login-and-tray setup from
     there. It is not blocked any more; the ad hosts it fires at (DoubleClick,
     Google Ads, Google Analytics) are blocked on their own, so the ads stay
     blocked without the page breaking.

  The blocker could not be switched off either: the "Ad Shield" sheet was a
  read-only notice. It is a real control now, with a **master switch** and a
  **per-site switch** — a site that needs a captcha to log in can be let
  through while the rest of the web stays blocked.

  The compiled rules are also stored under a new name: WebKit keeps the
  compiled list, and the old one was found and used, so the new rules were
  never even compiled.

  The rules apply to the **next** load, and they are compiled in the
  background — so the pages are loaded again **after** the compile. Before,
  the page was loaded with the *old* rules and the switch looked like it had
  done nothing.

  A site's name is checked before it is used: it ends up in a rule as a
  **host**, so a host with a `*` in it (`https://*/` is a URL that parses)
  would have let **every** site through.

- **"No Plex media server found on this account" — whatever the real problem
  was.** The one message was used for four different failures. Now:

  - the **relay address** of a server is asked for (`includeRelay=1`). Without
    it a phone that is not on the server's own network saw a server with **no
    usable address at all**, and the account looked empty;
  - **one odd device cannot empty the whole list** any more — every field of
    a device was required, so a single device that left one out made the
    whole answer unreadable;
  - `provides` reads as a **string and as a list**, because plex.tv answers
    both ways;
  - the **HTTP status is read**: an account that was refused (401) is now
    reported as *"plex.tv refused the account — sign in again"*, not as an
    account without a server;
  - the account's **own phone is not taken for the server** — a device that
    says it is a player is never the media server.

- **The voice search crashed the app the moment it heard something.** The
  microphone worked and the app died: the speech framework calls back on
  **its own queue**, and the app published the transcript from that queue —
  which is *"Publishing changes from background threads are not allowed"* — and
  closed the search sheet and started the player from there too. The
  transcript now crosses to the main actor before anything touches the app's
  state.

- **A portrait video was drawn as a landscape one — black bars on both
  sides.** Every surface asked the player to *fit* the picture into the
  frame, so a phone-shot video stood in the middle of the car's screen with a
  black bar on each side. A **portrait** video now fills the frame; a
  **landscape** one keeps its edges, because a channel's logo at the edge of
  the picture must not be cropped away.

- **A phone that locked itself took the app down in the middle of a test
  run.** A locked screen backgrounds the app, so the stream work stops and
  the test times out — and the failure was reported against whichever test
  happened to be running, on code that had not changed. Only the app can hold
  the phone's idle timer, so the app holds it while the tests run. The suite
  on the phone is green again, twice in a row, with no app restart at all.

- **The picture was on neither screen — "sometimes only in the car, sometimes
  only on the phone".** The hand-off hid the phone's picture *straight away*,
  so a car whose video endpoint was not ready yet left the video on nothing at
  all, and "Play on Phone" never brought the phone's own picture back. The
  picture now belongs to the **system's** answer: the phone keeps drawing it
  until the system reports it on the car, takes it back when the user asks,
  and the ladder that offers the picture again stops the moment the user
  takes it back — so a picture taken back no longer jumps to the car on its
  own a few seconds later. The banner and the picture can no longer disagree:
  the system is the only writer of the flag.

- **The phone stuttered while a video played.** The now-playing info is
  refreshed four times a second, and the artwork was **drawn** every time: a
  512×512 gradient with a symbol and three lines of text, on the main thread,
  four times a second. The artwork is drawn once per channel and kept, and the
  info is only handed over when something in it changed.

- **A video that had just started was built twice.** The item was attached
  with the route already open, so the system had looked at it — and the
  hand-off offered the picture again straight away, which builds the player a
  second time. The start is a start now, not a stutter.

- **The car's screen waited for the wrong server.** The pictures were asked
  for one after another with a gap between them — a gap that exists because
  of one CDN's per-IP quota. The quota belongs to the **server**, so eight
  servers' logos no longer wait for each other: eight pictures from eight
  servers now arrive in 18 ms instead of 1.6 s. The car is also told about a
  whole row of pictures **once**, instead of reloading the row for every
  picture that arrives.

- **A video lost its sound when the voice search could not open the
  microphone.** The voice search borrows the audio session (`.record`); when
  the microphone was refused — a car that holds the phone's audio route
  refuses it for **every** app — the session was left as `.record` and the
  player's sound never came back. The player's session is restored on every
  path out now.

- **The picture never reached the car's display.** The app offered the stream
  to the car, but the system only looks at the AirPlay route **when the
  picture is offered** — and the car's video endpoint only exists once the
  CarPlay scene is up. The offer that happened before that found no endpoint
  at all (the system's own log said *"Local Playback = 1"*) and the car's
  screen stayed black. The picture is offered again at once, and again a
  moment, a few moments and half a minute later, until the system reports it
  on the car.

- **"Play on Car Display" showed the system's list of displays.** The app
  cannot pick an AirPlay route — there is no public API for it — so the
  button offered the list of screens every time. With a car connected the
  picture now goes there at once and the list is never shown; without a car
  the list is still the only way to reach a display, so it stays.

- **The car's Browser tab was a list of sites that did nothing, and it had
  no address bar.** It is now a **list** whose first row opens the **address
  bar** — a search template — with the sites of the app's own catalogue, the
  page the phone shows now, and what the user types going to the app's own
  browser on the phone (a URL is a URL, anything else is a search).

- **The app died at every CarPlay connect.** The Browser tab was a search
  template, and the tab bar **rejects** one: `-[CPTabBarTemplate
  validateTemplates:]` raises an `NSException` and the process takes a
  **SIGABRT** (the device's crash reports show the exact stack). The Browser
  tab is a list now, and the address bar is **pushed** onto the stack. The
  tab bar is built through `makeTabBar(_ templates: [CPListTemplate])`, so
  the compiler itself refuses a search template there.

- **The screen share produced nothing on a real phone.** The encoder refused
  every frame the app produced — *"FigSampleBufferSerialization err=-19642"*,
  logged as *"a frame could not be appended"* — because the pixel buffer was
  not **IOSurface-backed**. The Simulator's encoder takes a plain buffer, so
  the chain looked whole there and only the phone showed the hole: no
  fragment, no playlist, no picture on the car. Both the captured frame and
  the demo picture now go through the same IOSurface-backed canvas.

- **The channel logos never reached the car.** A third of the playlist's logos
  live on a CDN that answers **429** when more than about a hundred pictures
  are asked for in a short while — and the car asks for a whole category at
  once. A refused logo was never asked for again, so the card kept its
  initials for ever. The pictures are now asked for one after another, a
  refused one is asked for again, and a card is drawn from **the logo that
  arrived** rather than from a cache lookup that can come back empty.

- **Every card on the car had a green frame around it.** The card's tint
  paints the frame *and* the text on it, so our green was on every card of
  every category. The car paints its own cards now — the artwork carries the
  logo and nothing else.

- **The car's Home tab took the CarPlay session down.** The app did not crash
  — the **session** died: the Home tab was built from every one of the
  playlist's 184 categories, and every category is a row of 8 cards, so the
  screen was ~400 pictures the phone had to draw at the car's scale. The build
  alone took about 7 seconds, and every logo that arrived rebuilt the whole
  template again, so the car was sent the entire catalogue hundreds of times
  over — the CarPlay host's resource consumption climbed from 7 % to 59 % in
  about a second and the scene was torn down. The Home tab now shows 12
  categories, the rest are behind **"All categories (N)"** (every one of them,
  with its real count, and a way into its channels), and a logo that arrives
  **patches the card that shows it** instead of rebuilding the screen.

- **The car's cards showed the same initials instead of the channel's own
  logo.** The artwork was fetched, but the screen was never told about it: the
  picture was only ever used for the *first* build of a card, and a logo that
  arrived later was thrown away. The row, the card and the category's header
  are now patched in place (`CPListItem.setImage:`, `CPListImageRowItem
  .elements`, `CPListSection.headerImage`), so the car shows the **real**
  channel logos as they arrive.

- **The microphone did not work.** The voice search died with *"com.apple
  .coreaudio.avfaudio error 1852797029"*. A connected car takes the phone's
  audio route — output **and input** — and the car's input cannot record, so
  the recorder was pointed at the car. It now asks for the phone's own
  microphone by name, and waits for the route to carry it before the engine
  starts.

- **The account's token was written to the library file and to the watch
  history in the clear.** The image loader cannot send a header, so the token
  rides in the artwork's query — and only the *stream* URL was taken out of it
  before the file was written. The artwork carries the same token, so the
  library file (`saved_channels.json`) and the watch history held it in the
  clear. Both are taken out now and put back when the channel is played.

- **"Watch again" played a URL with a placeholder in it.** The watch history
  kept the *redacted* URL in memory, so the row played
  `…stream.mp4?api_key=__dp_token__` until the app was restarted. The item in
  memory keeps the real URL; the copy on disk is the one without the secrets.

- **One Plex server's remote address beat another's local one.** The local
  address won *within* a server's list of connections, but not *across* the
  servers: the first server with any address at all was taken, so a server
  that could only be reached from outside the network won over one that
  answers on the local network. The local one comes first now.

- **A monitor stopped the orientation notifications it did not start.** The
  generation of the orientation notifications belongs to the device, not to a
  monitor: a second monitor that stopped switched off what the first one had
  started, and the rotate handler went quiet. A monitor now only stops what it
  started.

- **The audio and subtitle picker moved a checkmark instead of a track.** The
  manager kept the *names* of the tracks and nothing else, so there was no
  option to hand to AVFoundation: `select(_:in:)` was never called and the
  stream kept speaking its own language. The real options are kept now, and
  the selection is read-only from the outside — the only way to change it is
  the player's own method.

- **A Plex source pointed at plex.tv.** That is the cloud API, not the media
  server: a source that names it can never list a file. The account's own
  server is looked up now, and the address on the local network wins over the
  remote one.

- **The Jellyfin library stopped after a hundred items.** One request with
  `Limit=100` truncated it silently — the user saw the first hundred and
  nothing else, with no hint that more existed. The pages are walked now until
  the server says there are no more. The artwork had no token either, and the
  image loader cannot send a header — the token rides in the query.

- **One entry that could not be read emptied the whole library.** The library
  is the one thing the user cannot get back, and the next save overwrote the
  file with nothing. Every entry is now decoded on its own, and the old copy
  in `UserDefaults` is only thrown away once the library was really read.

- **The DLNA parser took the title of the folder for the title of the first
  item, and glued several addresses into one.** A DIDL-Lite document carries a
  `<dc:title>` for the container, and an item may carry several `<res>`
  elements — one per protocol and bitrate. The container's name is not an
  item's name, and only the first `<res>` is the stream.

- **The M3U parser lost unquoted attributes and claimed resolutions the
  provider never gave.** A playlist that writes `tvg-id=abc123` instead of
  `tvg-id="abc123"` lost its id — and with it the channel's identity. A
  channel that says "HD" is no longer labelled "720P".

- **The car's Cast tab had rows that did nothing.** The picture rows need a
  player: without one "picture on the car" and "pause" look alive and do
  nothing at all. And "Stop mirroring" was there even when no share was
  running — now the row only exists while there is something to stop.

- **The car's channel picker dropped everything past the limit without a
  word.** CarPlay shows the first `maximumItemCount` rows and drops the rest
  silently, so a category of 500 channels lost everything past the limit. The
  list is paged now: the last row offers the next page, and every channel is
  reachable.

- **The car's Home tab could exceed CarPlay's item budget.** The budget is
  counted over **all** sections, so the tail of a long playlist was cut off
  without a word. It is counted now, before the section is added.

- **The relay's announcement buffer could grow without end.** The extension
  sends the address in one line; a peer that kept sending without ever
  sending the newline grew the buffer for ever. An announcement that passes
  the limit is dropped.

- **The phone never learned that it had been turned.** The orientation
  notification is only posted while the device is *generating* them, and
  nothing ever asked for them — so the docked player never rotated into full
  screen.

- **A copy that could not happen created a vault entry anyway.** The entry
  pointed at a file that was never written: a broken entry the user can
  neither play nor remove. The copy is not optional any more — it throws.

- **Every imported photo left a full-size copy in the temporary folder.** The
  transferable's file is a copy; the import copies it into the vault, so the
  temporary one has to go.

- **The extractor could be used exactly once.** The sheet hid its button as
  soon as a result was on the screen. A result no longer disables the button.

- **The volume HUD claimed 50 % while the audio played at 100 %.** It now
  shows the player's own volume.

- **A search query with a trailing space hid every result.** The query is
  trimmed once, and the trimmed value is what every match is made against.

- **A search result picked on the car played nothing.** The car's search is a
  `CPSearchTemplate`: the app hands CarPlay the results and CarPlay hands the
  selection back through `searchTemplate(_:selectedResult:completionHandler:)`
  — the row's own handler is never called for a search result. The delegate
  answered the completion handler and stopped, so the search found channels
  and played none of them. The result now carries the channel it stands for,
  and picking it plays that channel.

- **The voice search showed "com.apple.coreaudio.avfaudio error 1852797029"
  and never listened.** The player holds the audio session as `.playback` — a
  category with **no input route** — and the recorder's engine was born on
  that session, so its input node carried a 0 Hz format and refused to start
  (*"IsFormatSampleRateAndChannelCountValid"*). The session is now handed over
  to the microphone before the engine is built, the engine is built for the
  recording, and the player's session comes back when the microphone is
  released — a video that is playing gets its sound back with it.

- **The player's audio session was never configured.** The session was set up
  as `.playback` with the AirPlay and Bluetooth options — and those options
  are only valid with `.playAndRecord`, so the system rejected the whole call
  (`OSStatus -50`) and the session was **never activated**. The AirPlay route
  to the car's display was therefore never offered. The category is now the
  one the options belong to: `.playback`, no options.

- **The contract tests failed on the phone.** Seven of them read a file from
  the repository (`project.yml`, the entitlements, the scripts), and the paths
  baked into the test bundle point at the Mac it was built on — the phone has
  the app, not the checkout. A file that is not on the machine says nothing
  about the contract, so those tests now skip on a device instead of failing
  there.

- **The "a relay that cannot listen" test could not fail on iOS.** It proved
  the failure with a privileged port, but iOS does not refuse a port below
  1024 — the bind simply succeeded and the test waited for a failure that
  never came. It now takes a port that is **already bound** — and it binds it
  on the **loopback** interface, like the app's own relay: a listener on every
  interface asks a phone for the local-network permission first and then waits
  for the answer. The listener that occupies the port also needs a connection
  handler: one started without one never creates its socket, never reaches
  `.ready`, and leaves the test waiting for a bind that was never going to
  happen while the port itself was free.

- **The "a capture without frames falls back to the demo" test could not
  happen on a phone.** ReplayKit waits for the user's consent there and never
  ends on its own, so the share sat in "Starting…" for ever and the demo never
  took over. The capture is now a seam (`ScreenShareService(capture:)`), so the
  test can drive a capture that ends without a frame — the same way the
  "this device cannot record" test already drives `captureAvailable: false`.

- **The car's artwork was drawn for the wrong screen.** Apple says it plainly:
  *"images you display in any template should be sized to a display scale matching
  the scale of the `carTraitCollection`, not the scale of the iOS device's main
  screen."* The car is a different display — another aspect ratio, another
  scale — so a logo drawn at the phone's scale arrives on the car either soft
  or resized. The scale of the car's own trait collection is now read when the
  scene connects, and every card is drawn at it.

- **A rebuilt car's screen drew every card again.** The logo cache held the
  *logo*, so a rebuild fetched nothing new — but it also drew every tile from
  scratch. With a playlist of thousands of channels that is the difference
  between a rebuild and a stall, and the rebuild happens on every favourite
  change. The drawn tiles are cached too, so a screen that is rebuilt draws
  nothing that is already on it.

- **The car's display stayed black — the player had nowhere to draw.** A
  video-only `AVPlayerItem` never renders without a video output: CoreMedia
  logs *"video-only item is waiting for video output"*, `timeControlStatus`
  stays `.waiting` and the playhead never leaves zero, while the stream itself
  is fine. On the car the phone shows no player at all, so nothing owned an
  `AVPlayerLayer` and the item never started. The app now keeps a small output
  of its own whenever the phone shows no picture, and gives it up again the
  moment the phone's own player comes back — one output at a time.

- **The broadcast never reached the car — the relay was not listening yet.** The
  relay only started when a CarPlay row was tapped or the phone's screen
  mirroring tab appeared, but the user starts a broadcast from the Control
  Center: the extension announced its stream into a relay that was not there
  yet, and the share never began. The relay now listens from launch.

- **The test bundle could not be signed for a real device.** `CarTVTests` had
  no development team, so `xcodebuild test` against the phone failed with
  *"Signing for CarTVTests requires a development team"*. The target is signed
  like any other app now, so the suite runs on the device.

- **The picture never reached the car.** A CarPlay video app has to support
  AirPlay video streaming — the car's display is an AirPlay destination ("Rev
  up your CarPlay app", WWDC26) — but the player allowed external playback only
  on the screen-share path. Every channel played from the car therefore played
  on the phone and left the car's display black, with nothing logged. The
  player now allows external playback on every path.

- **Tapping any row on the car killed the app.** Every channel and playlist row
  presented the now-playing template modally, and CarPlay **throws an
  `NSException` when a template call fails and no completion handler was given**
  — an uncaught ObjC exception, so the process aborted (SIGABRT) and the app
  died on the first tap. The now-playing screen is the system's to present: the
  rows carry a `playbackConfiguration`, and CarPlay shows the media presentation
  itself when an item is selected, so the app now only configures the shared
  template. Every other template call (the channel list, the search) carries a
  completion handler as well, so a failed call is logged instead of being fatal.

- **Starting the relay tore down the share that was already running.** The
  relay only listens — it shares nothing until the broadcast extension
  announces its stream — but it stopped whatever was being shared *before* the
  broadcast arrived. The relay now only listens, and the broadcast replaces the
  running share when it turns up, which is what makes it safe to leave the
  relay running while the user picks the broadcast.

- **The app could die when the screen capture delivered no frame.** The encoder
  only starts with the first frame, so a capture that delivers nothing leaves a
  writer that was never started — and closing such a writer throws an
  `NSInternalInconsistencyException`, which takes the app down with it. The
  Simulator does exactly that, and so does a phone that refuses to record the
  screen while CarPlay is connected (`RPRecordingErrorCarPlay`): tapping the
  car's "Screen Mirroring" row could kill the app. The writer is now only
  closed when it actually started.

- **Waiting for the car's broadcast blocked the phone's own share.** The relay
  latched the "starting" state while it waited for the broadcast extension, so
  the capture and demo buttons stayed disabled — and the phone never said that
  it was waiting. The relay now only listens: the share state is untouched
  until a stream really arrives, and the waiting is visible.
- **Ending a share took the relay down with it.** The listener was stopped
  when the share was torn down, so the next broadcast was not picked up until
  the car's row was tapped again. The listener now lives as long as the car is
  connected and stops when the car disconnects.

- **The fragment window was read under a lock and written without one.** The
  encoder fills the fragments on its own queue while the HTTP server serves
  them on another; the readers took the lock and the writers did not, so the
  lock protected nothing. A Swift array mutated while it is read is undefined
  behaviour — not a glitch — so the fragments are now filled and read under
  the same lock.

- **A broadcast address that arrived in two pieces was thrown away.** The
  listener did one read and parsed it as a whole line, but the network can
  split a line: the first read then held half an address, which was not an
  address, so it was dropped — and the extension does not send it again. The
  phone's screen never reached the car, with nothing to show for it. The
  listener now waits for the whole line.

- **A relay that could not listen said nothing.** The bind fails *after*
  `start()` has returned, so the app waited for an announcement that could
  never arrive and the car showed nothing with no reason given. The failure is
  now reported, and the app says so instead of waiting.

- **The screen share could never work from the car.** iOS refuses to record the
  screen while CarPlay is connected (`RPRecordingErrorCarPlay`, "Failed to
  start recording due to carplay being active"), so the capture behind the
  CarPlay row always failed and the share fell back to the demo picture — the
  driver saw a fake animation instead of their phone. The car's row now waits
  for a broadcast (the WhatsApp-style mechanism) and the failure says what to
  do instead of failing silently.
- **CarPlay was asked for a video surface the app was not entitled to.** Every
  row asked for `.video` presentation, and the system refused the playback
  ("presentation is video but app does not have the video entitlement") — the
  car got no picture and the log filled with errors. The app now asks for video
  only when this build carries the CarPlay video entitlement, and falls back to
  the now-playing screen when it does not.
- **`scripts/carplay_grant.sh check` always said MISSING.** The provisioning
  profile folder has a space in its name ("Provisioning Profiles"), so the
  paths were word-split and the profiles were never read; `pipefail` with
  `grep -q` also turned a good profile into a failed one. The check now
  reports the profile that carries the entitlement.

- **The car shelves were rebuilt three times at launch.** The store
  republishes its channel list on every save, and the publisher also fires
  once on subscription, so the shelves were torn down and rebuilt — every
  card, every category — for data that had not changed. A rebuild now
  happens only when the channel list or the favourites actually differ.
- **The install helper only worked on the machine that wrote it.**
  `scripts/auto_install.sh` hardcoded one iPhone's UDID and one absolute
  DerivedData path, and looped forever when that phone was not connected —
  the job hung with no way out. The device is now detected at run time (or
  passed as an argument), the built `.app` is located in DerivedData, and the
  wait for a phone is bounded and ends in a clear error.
- **The offline vault could lose imports.** Two files with the same name (e.g.
  `clip.mp4` from two different folders) were both stored as `clip.mp4`, so the
  second import overwrote the first and the vault ended up with two entries
  pointing at one copy. Stored files are now prefixed with a fresh id.
- **The offline vault index was written non-atomically.** A write interrupted by a
  crash left a truncated `index.json`, and the vault then failed to load — every
  import looked gone. The index is now written atomically.
- **Voice search never worked.** The overlay was never presented, `startRecording`
  had no callers, and neither the speech-recognition nor the microphone permission
  was ever requested — the sheet showed "Listening…" while nothing was recording.
  The microphone button on Home now opens it, the permissions are requested, and a
  spoken channel or category name starts playback. A tap left installed on the audio
  input node (when the engine failed to start) also trapped the next recording; the
  tap is now always detached.
- **Plex sign-in could never complete.** `PlexPin` required a JSON key `expiresAt`,
  which Plex does not send — it returns `expiresIn` and `createdAt`. Every pin
  response therefore failed to decode with `keyNotFound`, so neither creating a
  pin nor checking it could succeed.
- **Unbounded channel-logo cache.** The `NSCache` holding channel logos had no cost
  limit, so it grew with every logo ever seen and evicted nothing. It is now capped
  at 32 MB and each image is stored with its approximate byte cost.
- **M3U parsing — channel titles with commas.** The title separator was found by
  scanning for the *last* comma on the `#EXTINF` line, so a title containing a
  comma (`ESPN, Sports`) was truncated. The separator is now found by skipping
  over quoted attribute values.
- **M3U parsing — group titles leaking between entries.** An entry without a
  `group-title` inherited the *previous* entry's group. Group membership is now
  derived only from the entry's own tags, and `#EXTGRP` applies only to the
  entry it belongs to.
- **Xtream Codes — credentials breaking the request URL.** Usernames and
  passwords were interpolated raw into the query string and the stream path. A
  password containing `&`, `#`, `?` or `/` truncated the request (HTTP 401 or a
  404 on every channel). Credentials are now percent-encoded.
- **Xtream Codes — unplayable channels.** A channel whose stream URL cannot be
  constructed was silently given the API endpoint as its stream URL, handing the
  player a JSON document. Such channels are now dropped.
- **Xtream Codes — multi-category streams.** A stream reported with several
  category ids (`"1,2"`) was grouped under no category at all. It now uses the
  first matching category.
- **Screen mirroring on the iOS Simulator.** The Cast tab latched a "mirroring
  active" state *before* checking `RPScreenRecorder.isAvailable`, which is
  always false in the Simulator. Every later attempt returned early and the tab
  spun on a waiting card forever. It now reports that screen recording is not
  supported in the Simulator.
- **CarPlay home chevrons.** The scroll up/down chevrons were positioned
  against the view's bounds instead of the scroll container's, putting the
  up-chevron 48pt too low and the down-chevron 26pt below the bottom of the
  screen, where it could not be tapped.
- **Video player skip buttons.** The ±10s buttons were created visible, so the
  first tap on the video hid them instead of revealing them. They now start
  hidden.
- **Favorites.** The docked player's channel grid and the group detail swipe
  action render a snapshot of the channel list; favoriting a channel updated
  the store but not the snapshot, so the heart never changed. The snapshot is
  now kept in step.
- **Stream health.** A source with 500 ms or more latency was reported as
  "fair", which made the "poor" state unreachable even though the UI branches
  on it. It is now reported as "poor".
- **Screen mirroring outlived the external display.** The capture was only
  stopped by the Cast tab's close button; a tab switch or the external display
  going away left the recording running (the recording indicator stayed on and
  the battery drained). The stop path is now shared by all three, and the
  sample-buffer renderer is only touched on the main thread, which is where
  `AVSampleBufferDisplayLayer` requires it.
- **App Transport Security allowed plain HTTP to every host.** The app
  declared `NSAllowsArbitraryLoads`, so any server address could be fetched
  over an unencrypted connection. Plain HTTP is now limited to the local
  network (`NSAllowsLocalNetworking`), the in-app browser keeps its own
  exception, and every server URL the app builds goes through one policy that
  picks `http` for local hosts and `https` for everything else.
- **Server credentials were stored in the clear.** The username, password and
  access token of a source were JSON-encoded into `UserDefaults`, and the
  Xtream stream URLs (which carry the credentials in their path) and the
  Jellyfin URLs (which carry the token in the query) were written to
  `Documents/saved_channels.json` and to the watch history. The secrets now
  live in the Keychain, the files on disk hold placeholders, and the URLs get
  their credentials back when they are played.
- **A blocked server was a mystery.** When iOS refused an unencrypted address
  the app showed the raw system error, which does not say what to do about it.
  It now says that the address uses an unencrypted connection and what to use
  instead.

### Added

- **A minimised player — the bar under the content, above the tab bar.** A
  video that is playing can now be put away: the picture leaves the phone's
  screen and a bar takes its place, YouTube's way. The bar carries the
  channel's picture and its name, and it plays and pauses the video, skips to
  the **next channel of the group the current one belongs to**, and closes the
  video with ✕. It sits **above** the tab bar and never covers it — the
  tab bar's height is measured from the live window, so it is right on every
  phone.

- **A swipe down puts the player away.** YouTube's gesture works in the app
  too: a swipe down on the docked player — or on the full-screen one — leaves
  the bar behind. Only a swipe **down**: a drag to the side is not a
  dismissal.

- **A video started on the phone goes to the car's display by itself.** When a
  car is connected, a video the user starts on the phone is handed over to the
  car at once — the phone keeps no picture and the car shows the video. A
  video started *by* the car is left alone: the car already asked for it.

- **A switch between the car's display and the phone.** The car's display is an
  AirPlay destination — a CarPlay video app has to support AirPlay video
  streaming ("Rev up your CarPlay app", WWDC26) — so the picture travels the
  AirPlay route: the player offers the video to the car's display
  (`allowsExternalPlayback`), the system reports the route back
  (`isExternalPlaybackActive`), and a "Play on Car Display" pill opens the
  system's own device list. When the car is connected, a "Car connected" banner
  appears with "Play on Phone" to take the picture back and a pause button.
  Nothing about it is a mock: every row acts on the real route.

- **The picture keeps playing when the app is minimised or the screen is
  locked.** The player now keeps the video alive in the background
  (`audiovisualBackgroundPlaybackPolicy = .continuesIfPossible`, with the
  `audio` background mode), and the scene's phase change puts it back to work
  when the phone goes to the background — so the car keeps the picture the
  phone was showing.

- **The car's screen is a tab bar with four tabs — Home, Favorites, Cast and
  Browser.**
  - **Home** lists the whole playlist under "All" and then every category, each
    with its real count, its own artwork, its channels as horizontally
    scrollable cards (iOS 26+) and a way into all of its entries.
  - **Favorites** is the phone's own list: the same favourites, the same
    instant, kept in step by the store.
  - **Cast** shows where the picture is and what the share does — the real
    state of the player and of the broadcast, with the actions each one allows.
  - **Browser** offers the sites of the app's own browser and opens them **on
    the phone**. CarPlay has no web view — Apple does not allow one — so the
    closest compliant interaction is to drive the phone's browser and let the
    screen share carry the picture to the car.

  The rows carry the `playbackConfiguration` that asks CarPlay for the video
  surface, the logos are fetched once and cached, and every logo is drawn at
  its own aspect ratio on a rounded charcoal card with the green accent — never
  stretched, never clipped.

- **The `screen-capture` background mode.** The share to the car runs with the
  app in the background (the car is driving the app) and the capture runs in
  the broadcast extension, so the app needs to stay alive while the capture
  runs — that is what the mode is for.

- **A broadcast button in the app — the WhatsApp screen share, without the
  Control Center.** The app cannot start a broadcast by itself (iOS always asks
  the user), but it can put the system picker in front of the user: one tap on
  the "Screen Mirroring" screen and one on "DrivePlay Screen Relay" starts the
  share, and the car's display shows the phone's screen. Only the app's own
  extension is offered, so the list holds a single entry.

- **`scripts/carplay_video_install.sh` — the CarPlay video build, in one
  command.** Apple mints the provisioning profile that carries
  `com.apple.developer.carplay-video`; the script takes the profile the
  account holder downloaded, checks that it really carries the entitlement,
  installs it where Xcode looks (moving the profile it replaces aside, so Xcode
  cannot sign with the wrong one), builds the video build for the connected
  phone and installs it. Signing stays on automatic, so no Apple account has to
  be signed in on the build machine.

- **The phone's screen on the car, broadcast WhatsApp-style.** The
  `ScreenRelay` broadcast extension encodes the screen into a live HLS stream
  and serves it; the app picks the stream up and plays it, and the car draws
  it in the now-playing area. This is the capture that works while CarPlay is
  connected: iOS does not allow the app to record its own screen then, but a
  broadcast started from the Control Center keeps running. The two processes
  find each other over the loopback interface — they share no container, so
  the stream address travels in one line.

- **The phone's screen on the car's display — screen sharing, WhatsApp-style.**
  A car screen never shows a mirror, only the video the app plays, so the app
  records its screen, serves it as a live HLS stream and plays that very
  stream; the car draws it in the now-playing area. The share card lives on
  the Cast-to-car screen, and the CarPlay template starts the same share.
  The playlist is served on the local network as well, so a head unit that is
  not CarPlay can open it and watch the screen live.
- **A demo stream for the CarPlay Simulator.** The Simulator has no screen to
  record, so `DemoFrameSource` draws a moving picture and feeds it through the
  same encoder and the same server — the whole chain can be checked there. A
  share whose capture delivers no frame now hands over to it by itself, so the
  CarPlay row works on the Simulator too, and the phone says plainly that a
  demo picture is being shared.
- **The car's "Screen Mirroring" row now starts that demo on the Simulator.**
  The row waited for a broadcast, and no broadcast can arrive there: the phone
  has no screen to record and the extension cannot be started. On the Simulator
  the row now starts the demo picture — the same chain, and a picture on the
  car's screen. On a real phone it still waits for the broadcast: a fake
  picture on a real car would be worse than nothing.
- **`scripts/carplay_simulator.sh`** builds and installs the app in the
  Simulator **with the CarPlay video entitlement**, which is what makes the
  CarPlay Simulator ask for the video surface at all, and prints the two facts
  that decide it. The device build stays on the audio category until the
  portal carries the CarPlay Video capability — a device build that asks for
  video does not sign.
- A `CarTVTests` unit-test target (`CarTV/Tests`) wired into the `CarTV`
  scheme, with 66 tests covering the M3U, Xtream and DLNA parsers, the Plex
  pin response, the offline vault, the CarPlay templates, the car shelves,
  the URL policy, the credential storage, the purchase layer, the CarPlay
  entitlement, the install script and the screen share.
- **A Pro row in Settings.** The paywall existed but nothing led to it. It
  is now reachable, and it says whether Pro is unlocked, offers the upgrade
  with its price, or says that the upgrade is not in the store yet.
- **A local StoreKit configuration** (`Configuration/DrivePlay.storekit`) with
  the Pro product, attached to the `CarTV` scheme — the purchase path can be
  exercised in the Simulator without a Sandbox account.
- **`scripts/run_tests.sh`** — the whole suite in one command, with the
  ad-hoc signing the Keychain needs and an automatic choice of Simulator.
- **`scripts/carplay_grant.sh`** — says whether the local provisioning profile
  carries the CarPlay entitlement, and asks Xcode for a new one that does
  (once Apple has granted the capability).
- **`docs/carplay-video-request.md`** — the step-by-step package for the Apple
  account admin: what to send Apple, the text for every field, and what
  happens after the request is approved. `docs/carplay-video-request-simple.pdf`
  is the same guide in plain language, ready to hand over.
- **A GitHub Actions workflow** (`.github/workflows/tests.yml`) that generates
  the project and runs the same script on every push.

### Changed

- **The app is dark now, whatever the phone says.** DrivePlay is a dark-first
  app — the cards, the player and the whole in-car screen are dark — but a
  phone set to light still showed a light app sitting next to a dark car. The
  app now asks for the dark appearance once, for the whole process, so every
  tab, every sheet and every window is dark. The car is unchanged: the car
  paints its own chrome, and the app cannot tell a car what colour to be.

- **The video build asks for both CarPlay entitlements.** Apple's profile for
  the app id carries `carplay-audio` and `carplay-video`, and Apple's own
  guidance is to include both when the content suits both: the app then
  appears on **every** car — an app with only the video entitlement does not
  appear at all on a car without "video in car" — and the picture appears on
  the cars that support it. The audio build stays audio-only, so it still
  signs with the old profile.

- **One CarPlay category per build, chosen by a setting.** Apple grants one
  category per app and the capability lives on the app id, so a build is
  either signed with the entitlement or it does not build at all. The build
  setting `CARPLAY_CATEGORY` ("audio" or "video") picks the entitlements file
  *and* tells the app what it was signed with, so the app can never ask
  CarPlay for a picture it is not allowed to have. It is "audio" until the app
  id carries the CarPlay Video capability, and the device build works again in
  the meantime.

- **The CarPlay screen share is a list row now, not a bar button.** Only
  `CPListItem` carries a `playbackConfiguration`, and that is how CarPlay is
  told that the content behind a selection is video — without it the car's
  now-playing area had no picture to draw. The row carries the same video
  signal the channel rows carry.

- **`CarPlayVideoViewController.swift` is no longer a 2,022-line file.** It is
  split into nine files by responsibility — the controller itself plus the top
  bar, the content area, the browser, the video, the mirror, the search, the
  shelves and the actions. The code was moved, not rewritten; the members that
  the extensions share are no longer `private` (Swift's `private` is limited
  to one file).
- **The CarPlay entitlements now include video.** `CarTV.entitlements` asked
  for `com.apple.developer.carplay-audio` only, so the car screen could never
  show a picture. It now asks for `com.apple.developer.carplay-video` (the
  video key is `carplay-video`, not `carplay`) and no longer for the audio key:
  Apple grants **one** CarPlay category per app, so asking for both meant
  asking for two categories and getting neither. Apple grants that capability
  per app: **the device build stops signing until the provisioning profile
  carries it.** The Simulator build is unaffected.
- **The `CarTV` scheme is shared now.** It was defined under a target in
  `project.yml`, which XcodeGen does not write to disk — so no `.xcscheme`
  existed and Xcode silently fell back to an auto-created one, without the
  test target. The scheme is now defined at the project level and lives in
  `CarTV.xcodeproj/xcshareddata/xcschemes/CarTV.xcscheme`.
- **CarPlay now uses the template API only.** CarPlay renders templates — no
  public header in `CarPlay.framework` exposes `UIViewController`, so the
  custom view controller the CarPlay scene used to install on the CarPlay
  window could never render. The scene delegate now builds the car UI from
  `CPListTemplate` (Favourites + Categories, then a list of the category's
  channels), starts playback through `PlaybackManager` and hands the
  transport controls to `CPNowPlayingTemplate`. The window hijack, the
  `zPosition = 99999` lift and the 3-second "keep on top" timer are gone.
- **CarPlay channel rows request video.** On iOS 26.4+ each channel row
  carries a `CPPlaybackConfiguration` with a `.video` preferred presentation,
  which is how CarPlay is told the selection is video and the system presents
  the picture itself. The picker is a list rather than a grid for exactly this
  reason — only `CPListItem` carries that property, `CPGridButton` does not.
- **CarPlay search is reachable.** `CPSearchTemplate` is presented from a
  navigation-bar button on the root template.
- **The handset search box no longer shrinks the car catalogue.** The
  CarPlay browser reads the new `PlaylistStore.allGroups`, which is the
  unfiltered channel index.
- **The purchase layer is a real StoreKit 2 integration.** `StoreKitManager`
  loaded no products, bought nothing and hardcoded `isProUnlocked = true`. It
  now loads the products of the store, buys, restores, listens for
  `Transaction.updates` and reads `Transaction.currentEntitlements`. Nothing in
  the app is gated behind Pro — that is still a product decision — so the app
  behaves exactly as before.

### Removed

- **An 822-line in-car dashboard that nothing showed.** `CarPlayAutomotiveDashboardView`
  was a whole second implementation of the car's screens — its own tab state,
  its own shelves, its own artwork — and no code path ever presented it. The
  car's screens live in `CarPlayTabs` and the scene delegate now; the view is
  gone.
- **A second, unused in-car browser.** `CarBrowserView` was a whole second
  implementation of the browser — its own `WKWebView`, its own tab state, its
  own list of preset sites — and nothing in the app ever showed it. It was a
  second source of truth for "the sites": the car's Browser tab uses
  `BrowserCatalog`, the dead view carried YouTube/Twitch/Bilibili/Vimeo. The
  view is gone; the `WKWebView` wrapper it held is now next to the browser
  that actually uses it.
- A stale 56 KB Mach-O binary at the repository root, compiled from the
  deleted `CarTV/Tests/main.swift`. Nothing referenced it and it cannot run
  standalone.
- The CarPlay scene no longer assigns `CPWindow.rootViewController`,
  lifts a view above the template stack, or keeps it on top with a
  repeating timer. CarPlay owns that window.
