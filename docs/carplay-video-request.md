# CarPlay video entitlement — what the Apple account admin has to do

> **Status (2026-11-02): the request has already been granted — do not send the form
> below any more.** Apple assigned the **CarPlay Video App** entitlement to the team
> (Case-ID 23260500, App Type VIDEO). The team's own capability catalogue shows the
> capability as `editable: true` with `canRequestFromPortal: false`, i.e. there is no
> request form for it any more.
>
> **What is left (about a minute):**
> <https://developer.apple.com/account/resources/identifiers/list> → App ID
> **XC com rushabh cartvv** → **Capabilities** → tick **CarPlay Video**, untick
> **CarPlay Audio** (both at once is not supported) → **Save**.
>
> The developer then rebuilds with `CARPLAY_CATEGORY=video`. The rest of this document
> describes the request that has already been made and approved, and is kept for the
> record.

**For:** the Account Holder / Admin of the Apple Developer team **47T499AR2T**
(the team that owns `com.rushabh.cartvv`).
**From:** the developer of DrivePlay, who cannot sign in to that team.
**What it takes:** about 10 minutes, plus reading one legal addendum.

---

## 0. The short version

DrivePlay (the CarTV iPhone app, bundle id `com.rushabh.cartvv`) wants to show **video in the
car** through CarPlay. Apple only allows this for apps they have reviewed and approved, so
one request has to be sent to Apple from the Apple account.

**Only you can send it**, because the request form needs the account to be signed in, and it
includes an agreement to Apple's CarPlay Entitlement Addendum.

Everything else — enabling the capability, the provisioning profile, the build — happens
afterwards, from the developer's side. There is nothing else for you to do.

---

## 1. What you need

- The Apple ID of the **Account Holder** (the team admin), with its 2-factor code.
- The CarPlay Entitlement Addendum (Apple sends it as a link, or it is linked from the form).
- Nothing from the developer. All the details you need are below.

---

## 2. Step 1 — sign in to the Apple Developer account

Go to **https://developer.apple.com/account/** and sign in with the Account Holder's Apple ID
(the one that owns team **47T499AR2T**, shown as *Florence Mitchell* / Individual in Xcode).

> If your team has several members and you are an **Admin** or **Account Holder**, you can do
> this yourself. If you are only a **Member**, the Account Holder has to do it — the addendum
> has to be accepted by somebody who can sign for the account.

## 3. Step 2 — open the CarPlay request form

Go to **https://developer.apple.com/contact/carplay/** and sign in when asked.

This is Apple's official "request a CarPlay app entitlement" form. It is the same page as the
"Request CarPlay app entitlement" link on <https://developer.apple.com/carplay/>.

## 4. Step 3 — fill the form

The wording of the form may differ slightly from the list below — use these answers for the
equivalent questions.

| Field | Answer |
|---|---|
| Your name / email / phone / company / address | Your own details (the account holder's). |
| Company / team | The team that owns `com.rushabh.cartvv` (team id **47T499AR2T**). |
| App name | **DrivePlay** |
| Bundle identifier | **com.rushabh.cartvv** |
| Version | **1.2.0** |
| App Store link | *Not on the App Store yet — the app is still in development.* (If the form requires a link, write this sentence.) |
| Website | *No public site yet.* |
| **CarPlay category / app type** | **Video** — a CarPlay video app. |
| Which markets | **All markets** (or: United States, India — whichever is wanted). |
| Target iOS | **iOS 27 or later** (the CarPlay video category needs iOS 27). |

### The description of the app — paste this

```
DrivePlay is an iPhone app that plays live TV and video playlists in the car through CarPlay.

The user adds their own media server or playlist (M3U playlist, Xtream Codes, Plex), and the
app shows the channels as a CarPlay list. Choosing a channel starts that stream in the car's
now-playing area, where the car screen shows the video while the car is parked.

DrivePlay is a player: it does not host, sell or distribute any video. All content comes from
services the user adds themselves, and the user signs in with their own credentials. The app
also supports AirPlay video streaming, so a stream can be sent to an AirPlay display.

CarPlay is used only for browsing the channels and starting playback; every part of the flow
works from the car screen alone.
```

### The content-licensing question — paste this

```
DrivePlay does not provide video content and holds no content rights. It is a client: the
content is served by the user's own server or subscription, and the app only sends the player
the stream URL that the user's own account returned. There is no catalogue, no library and no
third-party content in the app.
```

> **Only answer this if it is true of your build.** If the app ever ships with a built-in
> channel list or with content the app itself distributes, that answer has to change — Apple
> reviews the rights to the content, and a wrong answer here is what gets a request rejected.

### If the form asks for a demo video

Apple usually wants to see the app working in a car. Send a short screen recording of:

1. the app on the iPhone with the channel list,
2. the CarPlay screen showing the same list,
3. one channel playing video on the car screen.

Upload it wherever the form asks (a private/unlisted link is fine — Google Drive, iCloud, YouTube
unlisted) and put the link in the field.

## 5. Step 4 — agree to the addendum and submit

Tick the box / open the link for the **CarPlay Entitlement Addendum** and accept it. That is a
short legal agreement about how a CarPlay app may behave in a car (no games, no social
networking, no reading messages on the car screen, everything usable from the car screen
alone). It has to be accepted by the Account Holder or an Admin.

Then press **Submit**.

## 6. Step 5 — wait

Apple reviews the request (usually a few days, sometimes longer). They reply to the Account
Holder's email address. If they ask a question, forward the question to the developer — the
answers above are the technical content.

**That is everything.** Do not create certificates, profiles or app IDs — the developer handles
all of that as soon as Apple says yes.

---

## 7. What happens after you approve (the developer's job, no action needed)

1. Apple grants the **CarPlay video** capability to the team.
2. The capability is enabled on the App ID `com.rushabh.cartvv`
   (Identifiers → App ID → Additional Capabilities → CarPlay → Video → Save).
3. A new provisioning profile is generated that carries it
   (`scripts/carplay_grant.sh grant` does this).
4. The app is built for the phone and installed.
5. The car screen shows the channel list and plays the video.

## 8. If something goes wrong

| Situation | What to do |
|---|---|
| The form says the category is not available | Screenshot it and send it to the developer — it means the team is not eligible for that category yet. |
| Apple rejects the request | Forward the rejection mail. The usual reasons are the description being unclear about the content rights, or a missing demo video. |
| You cannot sign in (no access to the Account Holder) | The request has to come from the Account Holder. The developer cannot send it for you. |
| You want to use the **Audio** category instead | Say so — it is an older, more widely supported category (an audio app may also play video), but the car shows the app as an audio app and it needs no iOS 27. Apple allows only **one** CarPlay category per app, so the two cannot be combined. |
