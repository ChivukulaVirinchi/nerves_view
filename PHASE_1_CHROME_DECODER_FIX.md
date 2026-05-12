# Phase 1 — Chrome decoder fix (kill the 1–2 s stutter)

## Goal

Live WebRTC stream plays continuously with **zero PLI-induced freezes**. `pli_count` reported by `ExWebRTC.PeerConnection.get_stats/1` stays ≤ 5 over a one-minute test, instead of the current ~100/min.

## Why this works (one paragraph for context)

`libcamera-vid` on the Pi Zero 2 W cannot emit H.264 below **level 4.0** (we tested: `--level 3.1` exits 255). Our current code therefore takes the encoded level-4.0 bitstream and rewrites the SPS bytes to *claim* level 3.1, matching the SDP we advertise. Chrome configures its decoder for level 3.1, sees an SPS claiming level 3.1, and decodes — until a frame uses something only level 4.0 supports (deeper DPB, slightly larger slice, etc.), at which point the decoder errors and sends a PLI. We then wait ~1 s for the next IDR and the cycle repeats — exactly the 1–2 s stutter loop.

The proper fix is the opposite: **leave the SPS honest (level 4.0) and rewrite the answer SDP to advertise level 4.0**. Chrome's offer carries `level-asymmetry-allowed=1`, which per RFC 6184 §8.2.2 explicitly permits the answerer to choose a different level than what the offerer named. Chrome will then configure its decoder for level 4.0 and stop choking.

## Pre-flight

- Pi reachable at `nervesview.local`.
- Local checkout at `~/code/nerves/nerves_view`.
- ex_dtls fork at `~/code/nerves/ex_dtls` on branch `fix/openssl3-dgram-mem-bio`.
- Camera plugged in, libcamera-vid producing frames (verified by HLS playback working).
- Browser session **closed** before starting (so we get a fresh PeerConnection).

## Files to read first

| File | Why |
|---|---|
| `lib/nerves_view/streaming/peer_connection.ex` | Has both the SPS rewrite (to remove) and the place to add the SDP rewrite |
| `deps/ex_webrtc/lib/ex_webrtc/peer_connection.ex` near `get_stats` | Stats schema for verification |

## Steps

### Step 1 — Remove the SPS rewrite

`lib/nerves_view/streaming/peer_connection.ex`

**1.1** In `handle_info({:pipeline_frame, ...}, ...)` (around line 273), find:

```elixir
nals =
  case Map.get(frame, :nals) do
    list when is_list(list) and list != [] -> list
    _ -> [Map.get(frame, :payload, <<>>)]
  end
  |> Enum.reject(&(&1 == <<>>))
  |> Enum.map(&rewrite_sps_profile_level/1)
```

Delete the last line of the pipe (the `Enum.map(&rewrite_sps_profile_level/1)` call). Resulting code:

```elixir
nals =
  case Map.get(frame, :nals) do
    list when is_list(list) and list != [] -> list
    _ -> [Map.get(frame, :payload, <<>>)]
  end
  |> Enum.reject(&(&1 == <<>>))
```

**1.2** Find and delete the `rewrite_sps_profile_level/1` function (the two clauses near the comment block "Rewrite the profile_idc/constraint_flags/level_idc bytes of an SPS NAL"). The whole block, including the comment, is roughly 13 lines. Delete it entirely.

### Step 2 — Add the SDP rewrite

`lib/nerves_view/streaming/peer_connection.ex`, in `maybe_reply_offer/1` (around line 428).

**2.1** Change:

```elixir
sdp =
  case WebRTCPeer.get_local_description(state.pc) do
    %SessionDescription{sdp: sdp} -> sdp
    nil -> state.answer_sdp || state.offer_sdp
  end
```

to:

```elixir
sdp =
  case WebRTCPeer.get_local_description(state.pc) do
    %SessionDescription{sdp: sdp} -> sdp
    nil -> state.answer_sdp || state.offer_sdp
  end
  |> rewrite_h264_level_in_answer()
```

**2.2** Add the helper near the bottom of the module (before `defp via/1`):

```elixir
# libcamera-vid on the Pi Zero 2 W cannot emit H.264 below level 4.0, so the
# stream's SPS legitimately advertises level_idc=0x28 (4.0). Chrome's offer
# usually proposes profile-level-id=42e01f (Constrained Baseline level 3.1)
# but explicitly sets `level-asymmetry-allowed=1`, which per RFC 6184 §8.2.2
# permits the answerer to choose a different level. Rewriting the answer fmtp
# to 42e028 makes Chrome configure its decoder for level 4.0, matching what
# we actually send and eliminating PLI-induced freezes.
defp rewrite_h264_level_in_answer(sdp) when is_binary(sdp) do
  Regex.replace(~r/profile-level-id=42[a-fA-F0-9]{2}1[fF]/, sdp, "profile-level-id=42e028")
end

defp rewrite_h264_level_in_answer(other), do: other
```

### Step 3 — Build + deploy

```fish
cd ~/code/nerves/nerves_view
MIX_ENV=prod MIX_TARGET=rpi0_2 mix firmware
MIX_ENV=prod MIX_TARGET=rpi0_2 mix upload nervesview.local
```

If `mix firmware` errors with a `scrub-otp-release.sh: ERROR: Unexpected executable format` line mentioning `srtp_linux_x86`, run:

```fish
find ~/code/nerves/nerves_view -path "*srtp_linux_x86*" -prune -exec rm -rf {} +
```

then `mix firmware` again. (This is the x86 precompiled archive that leaks in if anyone ran a host build between target builds.)

## Verification

After Pi reboots (~30 s):

1. Open the camera page in Chrome. Let it run **at least 90 s**.
2. From your laptop:

```fish
ssh -o StrictHostKeyChecking=no nervesview.local
```

In IEx on the Pi:

```elixir
keys = Registry.select(NervesView.Streaming.Registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
{_, pid} = Enum.find(keys, fn {_, p} -> :sys.get_state(p).state == :connected end)
s = :sys.get_state(pid)
stats = ExWebRTC.PeerConnection.get_stats(s.pc)
out = stats |> Map.values() |> Enum.find(&(&1.type == :outbound_rtp))
IO.puts("pli=#{out.pli_count} nack=#{out.nack_count} pkts=#{out.packets_sent}")
```

**Pass:** `pli_count` is in single digits and not climbing rapidly. `nack_count` is low (≤ 10).
**Fail:** `pli_count` is still ticking up faster than ~1/s — re-investigate (likely the SDP rewrite didn't match, or there's a second answer flow).

3. Visual: open `chrome://webrtc-internals` in a second tab. In the inbound-rtp video stats, confirm `framesDecoded` rises steadily, `freezeCount` stays low, and `totalFreezesDuration` flatlines after the initial connection.

## Style / safety rules

- **No SDP/answer rewriting beyond the one regex.** This is the smallest possible change. Anything else (changing offer munging, changing the producer, changing the packetizer) is out of scope for this phase.
- **Don't touch the producer or the access-unit pipeline.** Those are working; verify with phase-1 success before phase 2.

## Rollback

```fish
git -C ~/code/nerves/nerves_view diff lib/nerves_view/streaming/peer_connection.ex
```

If something regresses, `git checkout lib/nerves_view/streaming/peer_connection.ex` and re-flash. Previous behaviour (with the SPS rewrite) returns.

## Estimated time

15 minutes including the firmware flash.

## Done when

`pli_count` ≤ 5 over a full minute of streaming, video plays without visible freezes, and you've watched it for at least 2 minutes to be sure.
