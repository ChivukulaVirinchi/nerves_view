# NervesView - Self-Hosted Home Surveillance System

> A completely self-hosted, privacy-first home surveillance system built with Nerves, Elixir, and Phoenix LiveView.

## Table of Contents

1. [Vision & Goals](#vision--goals)
2. [Architecture Overview](#architecture-overview)
3. [Technology Decisions](#technology-decisions)
4. [Project Structure](#project-structure)
5. [Implementation Phases](#implementation-phases)
6. [Detailed Component Design](#detailed-component-design)
7. [Hardware Requirements](#hardware-requirements)
8. [Deployment Modes](#deployment-modes)
9. [Dependencies](#dependencies)
10. [Development Setup](#development-setup)
11. [Future Considerations](#future-considerations)

---

## Implementation Status

- [x] Phase 1 foundation completed (camera domain + registry + tests)
- [x] Phase 2 signaling core completed (in-memory WebRTC signaling + tests)
- [x] Phase 3 motion and recording core completed (detection + retention store + tests)
- [x] Phase 4 clustering/discovery core completed (node registry + service discovery + tests)
- [x] Phase 5 authentication core completed (accounts + sessions + role checks + tests)
- [x] Phase 6 initial advanced feature completed (motion alerts + throttling + tests)

Commit trail:
- `76253ee` bootstrap
- `4897aac` phase 1
- `2698e4a` phase 2
- `6d27451` phase 3
- `c70f7aa` phase 4
- `572cdd7` phase 5

Phase 6 commit hash will be appended as it lands.

---

## Vision & Goals

### Core Principles
1. **Privacy First**: All data stays on user's devices. No cloud, no external services required.
2. **Zero Cost**: Completely open source. No subscriptions, no fees.
3. **Bring Your Own Hardware**: Works with RPi Camera Modules, USB webcams, and existing IP cameras.
4. **Progressive Complexity**: Start with one device, scale to many.
5. **Nerves Native**: Leverage Elixir's concurrency, fault tolerance, and OTA updates.

### Target Users
- Privacy-conscious homeowners
- DIY enthusiasts
- Small business owners
- Anyone tired of cloud surveillance subscriptions

### MVP Features
- [x] Live streaming dashboard (multi-camera grid)
- [x] Motion detection with recording
- [x] Continuous recording with configurable retention
- [x] Mobile-friendly responsive UI
- [x] Multi-user authentication with roles

---

## Architecture Overview

### High-Level System Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           User's Local Network                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                     Camera Nodes (Nerves Firmware)                   │    │
│  │                                                                      │    │
│  │   ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐   │    │
│  │   │   RPi 4 + Cam   │   │ RPi Zero 2W+Cam │   │ RPi 3B+ + Cam   │   │    │
│  │   │                 │   │                 │   │                 │   │    │
│  │   │ ┌─────────────┐ │   │ ┌─────────────┐ │   │ ┌─────────────┐ │   │    │
│  │   │ │  libcamera  │ │   │ │  libcamera  │ │   │ │  libcamera  │ │   │    │
│  │   │ │  /v4l2      │ │   │ │  /v4l2      │ │   │ │  /v4l2      │ │   │    │
│  │   │ └──────┬──────┘ │   │ └──────┬──────┘ │   │ └──────┬──────┘ │   │    │
│  │   │        │        │   │        │        │   │        │        │   │    │
│  │   │ ┌──────▼──────┐ │   │ ┌──────▼──────┐ │   │ ┌──────▼──────┐ │   │    │
│  │   │ │  Membrane   │ │   │ │  Membrane   │ │   │ │  Membrane   │ │   │    │
│  │   │ │  Pipeline   │ │   │ │  Pipeline   │ │   │ │  Pipeline   │ │   │    │
│  │   │ │  - H.264    │ │   │ │  - H.264    │ │   │ │  - H.264    │ │   │    │
│  │   │ │  - Motion   │ │   │ │  - Motion   │ │   │ │  - Motion   │ │   │    │
│  │   │ └──────┬──────┘ │   │ └──────┬──────┘ │   │ └──────┬──────┘ │   │    │
│  │   │        │        │   │        │        │   │        │        │   │    │
│  │   └────────┼────────┘   └────────┼────────┘   └────────┼────────┘   │    │
│  │            │                     │                     │            │    │
│  └────────────┼─────────────────────┼─────────────────────┼────────────┘    │
│               │                     │                     │                 │
│               │    Distributed Erlang + WebRTC Streams    │                 │
│               │                     │                     │                 │
│               └─────────────────────┼─────────────────────┘                 │
│                                     │                                        │
│                                     ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                         Hub (Phoenix LiveView)                       │    │
│  │                                                                      │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │    │
│  │  │   WebRTC     │  │   Camera     │  │   Storage    │              │    │
│  │  │  Signaling   │  │   Registry   │  │   Manager    │              │    │
│  │  │ (ex_webrtc)  │  │   (mDNS)     │  │  (HLS/MP4)   │              │    │
│  │  └──────────────┘  └──────────────┘  └──────────────┘              │    │
│  │                                                                      │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │    │
│  │  │   LiveView   │  │    User      │  │   Motion     │              │    │
│  │  │  Dashboard   │  │    Auth      │  │   Events     │              │    │
│  │  │   (Grid)     │  │  (Sessions)  │  │  (Timeline)  │              │    │
│  │  └──────────────┘  └──────────────┘  └──────────────┘              │    │
│  │                                                                      │    │
│  │  Storage: SQLite (metadata) + Filesystem (recordings)               │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                     │                                        │
│              ┌──────────────────────┼──────────────────────┐                │
│              │                      │                      │                │
│              ▼                      ▼                      ▼                │
│       ┌────────────┐        ┌────────────┐        ┌────────────┐           │
│       │  Desktop   │        │   Mobile   │        │   Tablet   │           │
│       │  Browser   │        │  Browser   │        │  Browser   │           │
│       └────────────┘        └────────────┘        └────────────┘           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
                                     │
                                     │ Optional: Tailscale/Cloudflare Tunnel
                                     ▼
                            ┌────────────────┐
                            │ Remote Access  │
                            │ (Phone on LTE) │
                            └────────────────┘
```

### Data Flow Diagram

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Camera    │     │  Membrane   │     │   WebRTC    │     │   Browser   │
│   Sensor    │────▶│  Pipeline   │────▶│   Track     │────▶│   Video     │
│             │     │             │     │             │     │   Element   │
└─────────────┘     └──────┬──────┘     └─────────────┘     └─────────────┘
                           │
                           │ Motion Detected?
                           ▼
                    ┌─────────────┐
                    │   Motion    │
                    │  Detection  │
                    │  (Evision)  │
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
       ┌─────────────┐          ┌─────────────┐
       │   Record    │          │    Push     │
       │  HLS/MP4    │          │   Event     │
       │   to Disk   │          │  to Hub     │
       └─────────────┘          └─────────────┘
```

---

## Technology Decisions

### Core Stack

| Component | Choice | Rationale |
|-----------|--------|-----------|
| **Firmware** | Nerves | Purpose-built for embedded Elixir, OTA updates, minimal attack surface |
| **Video Pipeline** | Membrane Framework | Elixir-native, composable, supports WebRTC |
| **Streaming Protocol** | WebRTC (ex_webrtc) | Sub-100ms latency, browser-native, P2P capable |
| **Camera Capture** | libcamera + Membrane plugin | Modern RPi camera stack, hardware acceleration |
| **Motion Detection** | Evision (OpenCV bindings) | Mature algorithms, Elixir integration |
| **Web Framework** | Phoenix LiveView | Real-time updates, minimal JS, server-rendered |
| **Database** | SQLite (via Ecto) | Embedded, no server needed, portable |
| **Authentication** | bcrypt + Phoenix sessions | Simple, secure, no external deps |
| **Discovery** | mDNS (mdns_lite) | Zero-config networking on LAN |
| **Clustering** | libcluster + Distributed Erlang | Native Elixir clustering |

### Why NOT These Alternatives?

| Alternative | Why Not |
|------------|---------|
| **HLS Streaming** | 2-10 second latency unacceptable for live monitoring |
| **RTMP** | Requires separate server, more complex |
| **MJPEG** | Higher bandwidth, no audio support |
| **PostgreSQL** | Overkill for embedded, requires server |
| **Redis** | Unnecessary for our pub/sub (Phoenix PubSub suffices) |
| **React/Vue** | LiveView eliminates need for JS framework |

### Rust NIFs / WebAssembly Decision

**Verdict: Not needed for MVP**

| Component | Native Elixir Solution | Rust NIF Needed? |
|-----------|------------------------|------------------|
| Video Encoding | Membrane + FFmpeg (C) | No |
| Motion Detection | Evision (OpenCV bindings) | No |
| Image Processing | Evision | No |
| WebRTC | ex_webrtc (pure Elixir!) | No |

**Future Considerations:**
- Custom Rust NIF for specialized ML inference (person detection)
- WASM for browser-side object detection (TensorFlow.js alternative)

---

## Project Structure

We'll convert from a single Nerves app to a **Poncho Project** (not umbrella - better for Nerves):

```
nerves_view/
├── nerves_view_firmware/        # Nerves firmware (runs on RPi)
│   ├── config/
│   │   ├── config.exs
│   │   ├── host.exs
│   │   ├── target.exs
│   │   └── runtime.exs
│   ├── lib/
│   │   └── nerves_view_firmware/
│   │       ├── application.ex
│   │       ├── camera/
│   │       │   ├── capture.ex          # Camera capture GenServer
│   │       │   ├── pipeline.ex         # Membrane pipeline
│   │       │   └── detector.ex         # Motion detection
│   │       ├── streaming/
│   │       │   ├── webrtc_endpoint.ex  # WebRTC peer connection
│   │       │   └── signaling.ex        # WebRTC signaling client
│   │       ├── recording/
│   │       │   ├── hls_writer.ex       # HLS segment writer
│   │       │   └── mp4_writer.ex       # MP4 clip writer
│   │       ├── network/
│   │       │   ├── discovery.ex        # mDNS advertisement
│   │       │   └── cluster.ex          # Erlang distribution setup
│   │       └── mode.ex                 # Hub vs Node mode switching
│   ├── rootfs_overlay/
│   ├── mix.exs
│   └── README.md
│
├── nerves_view_core/            # Shared business logic
│   ├── lib/
│   │   └── nerves_view_core/
│   │       ├── cameras/
│   │       │   ├── camera.ex           # Camera schema
│   │       │   └── camera_registry.ex  # Camera tracking
│   │       ├── recordings/
│   │       │   ├── recording.ex        # Recording schema
│   │       │   ├── segment.ex          # HLS segment schema
│   │       │   └── storage.ex          # Storage management
│   │       ├── events/
│   │       │   ├── motion_event.ex     # Motion event schema
│   │       │   └── event_store.ex      # Event persistence
│   │       ├── accounts/
│   │       │   ├── user.ex             # User schema
│   │       │   └── auth.ex             # Authentication logic
│   │       └── repo.ex                 # Ecto Repo (SQLite)
│   ├── priv/
│   │   └── repo/
│   │       └── migrations/
│   ├── mix.exs
│   └── README.md
│
├── nerves_view_web/             # Phoenix web interface
│   ├── lib/
│   │   ├── nerves_view_web/
│   │   │   ├── router.ex
│   │   │   ├── endpoint.ex
│   │   │   ├── components/
│   │   │   │   ├── layouts.ex
│   │   │   │   ├── core_components.ex
│   │   │   │   └── camera_components.ex
│   │   │   ├── live/
│   │   │   │   ├── dashboard_live.ex       # Main camera grid
│   │   │   │   ├── camera_live.ex          # Single camera view
│   │   │   │   ├── recordings_live.ex      # Recording browser
│   │   │   │   ├── playback_live.ex        # Video playback
│   │   │   │   ├── settings_live.ex        # System settings
│   │   │   │   ├── cameras_live.ex         # Camera management
│   │   │   │   └── auth/
│   │   │   │       ├── login_live.ex
│   │   │   │       └── register_live.ex
│   │   │   ├── controllers/
│   │   │   │   ├── webrtc_controller.ex    # WebRTC signaling endpoint
│   │   │   │   ├── recording_controller.ex # Recording file serving
│   │   │   │   └── api/
│   │   │   │       └── camera_controller.ex
│   │   │   └── channels/
│   │   │       └── camera_channel.ex       # WebSocket for camera updates
│   │   └── nerves_view_web.ex
│   ├── assets/
│   │   ├── js/
│   │   │   ├── app.js
│   │   │   ├── hooks/
│   │   │   │   ├── webrtc_player.js        # WebRTC video element hook
│   │   │   │   └── video_grid.js           # Responsive grid hook
│   │   │   └── webrtc/
│   │   │       └── peer_connection.js      # WebRTC client logic
│   │   ├── css/
│   │   │   └── app.css
│   │   └── vendor/
│   ├── priv/
│   │   └── static/
│   ├── mix.exs
│   └── README.md
│
├── config/                      # Shared configuration
│   ├── config.exs
│   ├── dev.exs
│   ├── prod.exs
│   ├── runtime.exs
│   └── test.exs
│
├── PLAN.md                      # This file
├── README.md                    # User-facing documentation
├── LICENSE                      # MIT or Apache 2.0
└── .github/
    └── workflows/
        ├── ci.yml               # Test & lint
        └── firmware.yml         # Build firmware artifacts
```

---

## Implementation Phases

### Phase 1: Foundation (Week 1-2)

**Goal:** Single camera streaming to browser on local network

#### 1.1 Project Setup
- [ ] Restructure to poncho project (firmware, core, web)
- [ ] Set up shared dependencies
- [ ] Configure for rpi4, rpi3, rpi0_2 targets
- [ ] Set up development environment (host target simulation)

#### 1.2 Camera Capture
- [ ] Integrate membrane_camera_capture_plugin
- [ ] Create Camera.Capture GenServer
- [ ] Test with RPi Camera Module v2/v3
- [ ] Test with USB webcam (v4l2)
- [ ] Add libcamera support for newer RPi OS

#### 1.3 Basic Membrane Pipeline
```elixir
# Target pipeline structure:
Camera -> H264Encoder -> [WebRTC Track, HLS Writer]
```
- [ ] Create basic capture → encode pipeline
- [ ] Use hardware H.264 encoding (VideoCore on RPi)
- [ ] Verify encoding performance on RPi Zero 2W

#### 1.4 Basic Phoenix Web
- [ ] Set up Phoenix with LiveView
- [ ] Create basic dashboard page
- [ ] Add video element placeholder
- [ ] Verify Phoenix runs on Nerves target

#### 1.5 mDNS Discovery
- [ ] Configure mdns_lite for `nervesview.local`
- [ ] Add HTTP service advertisement
- [ ] Test discovery from multiple clients

#### Deliverable: Access `http://nervesview.local` and see "Camera Ready" status

---

### Phase 2: WebRTC Streaming (Week 3-4)

**Goal:** Live video streaming with sub-second latency

#### 2.1 ex_webrtc Integration
- [ ] Add ex_webrtc dependency
- [ ] Create WebRTC signaling endpoint (Phoenix channel or controller)
- [ ] Implement offer/answer exchange
- [ ] Handle ICE candidates

#### 2.2 Membrane WebRTC Pipeline
```elixir
# Enhanced pipeline:
Camera -> H264Encoder -> WebRTC.Track -> PeerConnection -> Browser
```
- [ ] Integrate membrane_webrtc_plugin
- [ ] Create WebRTC endpoint GenServer
- [ ] Handle multiple peer connections (multiple viewers)

#### 2.3 Browser Client
- [ ] Create WebRTC player LiveView hook
- [ ] Implement RTCPeerConnection JavaScript
- [ ] Handle connection lifecycle
- [ ] Add reconnection logic

#### 2.4 Single Camera View
- [ ] Create CameraLive page
- [ ] Full-screen video with controls
- [ ] Connection status indicator
- [ ] Basic stats overlay (fps, bitrate)

#### Deliverable: View live camera feed in browser with <500ms latency

---

### Phase 3: Recording (Week 5-6)

**Goal:** Continuous and motion-triggered recording

#### 3.1 HLS Recording
- [ ] Add membrane_file_plugin for segment writing
- [ ] Create HLS segment writer
- [ ] Implement playlist management (.m3u8)
- [ ] Configure segment duration (2-6 seconds)

#### 3.2 Storage Backend
- [ ] Create Recording and Segment schemas
- [ ] Implement storage manager GenServer
- [ ] Add retention policy (auto-delete old recordings)
- [ ] Calculate and display storage usage

#### 3.3 Motion Detection
- [ ] Add evision dependency
- [ ] Implement frame differencing algorithm
- [ ] Create motion detection Membrane element
- [ ] Configure sensitivity thresholds

```elixir
# Motion detection pipeline branch:
Camera -> [H264Encoder, FrameSampler -> MotionDetector -> EventDispatcher]
```

#### 3.4 Motion-Triggered Recording
- [ ] Create MotionEvent schema
- [ ] Implement pre-roll buffer (capture before motion)
- [ ] Create motion clips (MP4)
- [ ] Link events to recordings

#### 3.5 Recordings UI
- [ ] Create RecordingsLive page
- [ ] Calendar/timeline view of recordings
- [ ] Motion event markers
- [ ] Video playback with HLS.js

#### Deliverable: Browse and play back recordings, view motion events timeline

---

### Phase 4: Multi-Camera & Clustering (Week 7-8)

**Goal:** Support multiple camera nodes managed by a hub

#### 4.1 Hub/Node Architecture
- [x] Implement mode detection (hub vs node) - API-level node mode registry
- [x] Create node registration protocol - in-memory registration + heartbeat
- [x] Hub: camera registry GenServer - base camera registry already in place
- [ ] Node: stream forwarding to hub

#### 4.2 Distributed Erlang
- [ ] Configure libcluster for LAN discovery
- [ ] Set up Erlang cookie management
- [x] Implement node heartbeat/health checks
- [x] Handle node disconnection gracefully (stale node pruning)

#### 4.3 Camera Discovery
- [x] Advertise cameras via mDNS (service model + announce API)
- [x] Hub: scan for camera services (discovery cache + list API)
- [ ] Auto-discovery UI
- [ ] Manual camera addition (IP cameras)

#### 4.4 Multi-Camera Dashboard
- [ ] Responsive grid layout (1/2/4/9/16 cameras)
- [ ] Grid layout presets
- [ ] Camera drag-and-drop arrangement
- [ ] Individual camera pop-out

#### 4.5 IP Camera Support (RTSP)
- [ ] Add RTSP client to Membrane pipeline
- [ ] Parse RTSP URLs
- [ ] Handle authentication
- [ ] Transcode to WebRTC

```elixir
# RTSP camera pipeline:
RTSP Source -> H264 Parser -> [WebRTC Track, HLS Writer]
```

#### Deliverable: View multiple cameras in grid, add IP cameras

---

### Phase 5: Authentication & Polish (Week 9-10)

**Goal:** Production-ready with multi-user support

#### 5.1 User Authentication
- [x] Create User schema with roles (admin/viewer) - in-memory user model
- [x] Implement registration flow - API/service layer
- [x] Implement login with sessions - session store + token lifecycle
- [x] Add "remember me" functionality
- [ ] Password reset flow (email optional)

#### 5.2 Authorization
- [x] Define permission levels:
  - **Admin:** full access, manage users, configure system
  - **Viewer:** view cameras, view recordings
- [ ] Protect routes with plugs
- [ ] Camera-level permissions (optional)

#### 5.3 Mobile Optimization
- [ ] Responsive CSS (Tailwind)
- [ ] Touch-friendly controls
- [ ] Adaptive video quality
- [ ] PWA manifest (add to home screen)

#### 5.4 Settings & Configuration
- [ ] System settings page
- [ ] Camera configuration (name, location, recording settings)
- [ ] Network configuration (WiFi setup)
- [ ] Storage configuration (retention, paths)

#### 5.5 OTA Updates
- [ ] Integrate nerves_hub_link (optional)
- [ ] Or: simple firmware upload via web UI
- [ ] A/B partition management
- [ ] Rollback support

#### Deliverable: Complete MVP ready for public release

---

### Phase 6: Advanced Features (Future)

#### 6.1 Remote Access
- [ ] Tailscale integration guide
- [ ] Cloudflare Tunnel integration
- [ ] WireGuard configuration
- [ ] DDNS setup documentation

#### 6.2 Notifications
- [x] Motion alert service with throttling (core backend)
- [ ] Motion alert push notifications (web push)
- [ ] Email notifications
- [ ] Telegram/Signal bot integration

#### 6.3 AI/ML Features
- [ ] Person detection (TensorFlow Lite on device)
- [ ] Vehicle detection
- [ ] Face recognition (opt-in)
- [ ] Object tracking

#### 6.4 Advanced Recording
- [ ] Timelapse generation
- [ ] Smart fast-forward (skip no-motion)
- [ ] Export clips
- [ ] Cloud backup integration (optional, user-provided)

---

## Detailed Component Design

### Camera Capture Module

```elixir
defmodule NervesViewFirmware.Camera.Capture do
  @moduledoc """
  GenServer managing camera capture lifecycle.
  
  Supports:
  - RPi Camera Module (libcamera)
  - USB Webcams (v4l2)
  - IP Cameras (RTSP)
  """
  use GenServer
  
  defstruct [
    :camera_id,
    :source_type,      # :libcamera | :v4l2 | :rtsp
    :device_path,      # "/dev/video0" or "rtsp://..."
    :resolution,       # {1920, 1080}
    :framerate,        # 30
    :pipeline_pid,
    :status            # :initializing | :streaming | :error
  ]
  
  # Configuration
  @default_resolution {1280, 720}
  @default_framerate 30
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: via_tuple(opts[:camera_id]))
  end
  
  def get_status(camera_id) do
    GenServer.call(via_tuple(camera_id), :get_status)
  end
  
  def add_viewer(camera_id, peer_connection) do
    GenServer.call(via_tuple(camera_id), {:add_viewer, peer_connection})
  end
  
  # ... implementation
end
```

### Membrane Pipeline Architecture

```elixir
defmodule NervesViewFirmware.Camera.Pipeline do
  @moduledoc """
  Membrane pipeline for video capture, encoding, and distribution.
  
  Pipeline structure:
  
      ┌──────────────────────────────────────────────────────────────┐
      │                                                              │
      │  Camera ──▶ H264Encoder ──┬──▶ WebRTC Tracks (N viewers)    │
      │     │                     │                                  │
      │     │                     └──▶ HLS Writer (recording)        │
      │     │                                                        │
      │     └──▶ FrameSampler ──▶ MotionDetector ──▶ EventSink      │
      │                                                              │
      └──────────────────────────────────────────────────────────────┘
  """
  use Membrane.Pipeline
  
  @impl true
  def handle_init(_ctx, opts) do
    camera_source = build_camera_source(opts)
    
    spec = [
      # Main video path
      child(:camera, camera_source)
      |> child(:encoder, build_encoder(opts))
      |> child(:tee, Membrane.Tee.Master),
      
      # WebRTC output (dynamic tracks added when viewers connect)
      get_child(:tee)
      |> via_out(:master)
      |> child(:webrtc_sink, %WebRTCSink{endpoint: opts[:webrtc_endpoint]}),
      
      # Recording output (if enabled)
      get_child(:tee)
      |> via_out(:copy)
      |> child(:hls_writer, build_hls_writer(opts)),
      
      # Motion detection branch (lower framerate)
      get_child(:camera)
      |> child(:frame_sampler, %FrameSampler{fps: 5})
      |> child(:motion_detector, %MotionDetector{
        sensitivity: opts[:motion_sensitivity] || 0.1,
        callback: opts[:motion_callback]
      })
    ]
    
    {[spec: spec], %{opts: opts}}
  end
  
  defp build_camera_source(%{source_type: :libcamera} = opts) do
    %Membrane.LibCamera.Source{
      device: opts[:device] || "/dev/video0",
      width: elem(opts[:resolution], 0),
      height: elem(opts[:resolution], 1),
      framerate: opts[:framerate]
    }
  end
  
  defp build_camera_source(%{source_type: :v4l2} = opts) do
    %Membrane.CameraCapture.Source{
      device: opts[:device],
      width: elem(opts[:resolution], 0),
      height: elem(opts[:resolution], 1),
      fps: opts[:framerate]
    }
  end
  
  defp build_camera_source(%{source_type: :rtsp} = opts) do
    %Membrane.RTSP.Source{
      url: opts[:rtsp_url],
      # ... RTSP options
    }
  end
  
  defp build_encoder(opts) do
    # Use hardware encoder on RPi
    %Membrane.H264.FFmpeg.Encoder{
      preset: :ultrafast,
      tune: :zerolatency,
      profile: :baseline,
      gop_size: opts[:framerate] * 2,  # Keyframe every 2 seconds
      use_shm?: true
    }
  end
  
  defp build_hls_writer(opts) do
    %Membrane.HLS.Writer{
      manifest_path: opts[:recording_path],
      segment_duration: Membrane.Time.seconds(6),
      target_window_duration: :infinity
    }
  end
end
```

### Motion Detection Element

```elixir
defmodule NervesViewFirmware.Camera.MotionDetector do
  @moduledoc """
  Membrane element for motion detection using frame differencing.
  
  Uses Evision (OpenCV) for efficient image processing.
  """
  use Membrane.Filter
  
  def_input_pad :input, accepted_format: Membrane.RawVideo
  def_output_pad :output, accepted_format: Membrane.RawVideo
  
  def_options sensitivity: [
    spec: float(),
    default: 0.1,
    description: "Motion sensitivity threshold (0.0 - 1.0)"
  ],
  min_area: [
    spec: integer(),
    default: 500,
    description: "Minimum contour area to trigger motion"
  ],
  callback: [
    spec: (boolean() -> any()) | nil,
    default: nil,
    description: "Callback when motion state changes"
  ]
  
  @impl true
  def handle_init(_ctx, opts) do
    state = %{
      previous_frame: nil,
      motion_state: false,
      sensitivity: opts.sensitivity,
      min_area: opts.min_area,
      callback: opts.callback,
      background_subtractor: Evision.createBackgroundSubtractorMOG2()
    }
    {[], state}
  end
  
  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    # Convert to grayscale mat
    mat = buffer_to_mat(buffer)
    gray = Evision.cvtColor(mat, Evision.cv_COLOR_BGR2GRAY())
    
    # Apply background subtraction
    fg_mask = Evision.BackgroundSubtractorMOG2.apply(
      state.background_subtractor,
      gray
    )
    
    # Find contours
    {contours, _} = Evision.findContours(
      fg_mask,
      Evision.cv_RETR_EXTERNAL(),
      Evision.cv_CHAIN_APPROX_SIMPLE()
    )
    
    # Check for significant motion
    motion_detected = Enum.any?(contours, fn contour ->
      Evision.contourArea(contour) > state.min_area
    end)
    
    # Trigger callback on state change
    state = maybe_trigger_callback(state, motion_detected)
    
    {[buffer: {:output, buffer}], %{state | motion_state: motion_detected}}
  end
  
  defp maybe_trigger_callback(state, motion_detected) do
    if state.motion_state != motion_detected and state.callback do
      state.callback.(motion_detected)
    end
    %{state | motion_state: motion_detected}
  end
  
  defp buffer_to_mat(buffer) do
    # Convert raw video buffer to Evision mat
    # Implementation depends on pixel format
  end
end
```

### WebRTC Signaling

```elixir
defmodule NervesViewWeb.WebRTCController do
  @moduledoc """
  REST endpoint for WebRTC signaling.
  
  Flow:
  1. Client requests offer from camera
  2. Server creates PeerConnection, sends offer
  3. Client sends answer
  4. ICE candidates exchanged
  5. Connection established, video flows
  """
  use NervesViewWeb, :controller
  
  alias NervesViewFirmware.Streaming.WebRTCEndpoint
  
  def offer(conn, %{"camera_id" => camera_id}) do
    case WebRTCEndpoint.create_offer(camera_id) do
      {:ok, offer, session_id} ->
        json(conn, %{
          type: "offer",
          sdp: offer.sdp,
          session_id: session_id
        })
      
      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: reason})
    end
  end
  
  def answer(conn, %{"session_id" => session_id, "sdp" => sdp}) do
    case WebRTCEndpoint.handle_answer(session_id, sdp) do
      :ok ->
        json(conn, %{status: "ok"})
      
      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: reason})
    end
  end
  
  def ice_candidate(conn, %{"session_id" => session_id, "candidate" => candidate}) do
    WebRTCEndpoint.add_ice_candidate(session_id, candidate)
    json(conn, %{status: "ok"})
  end
end
```

### LiveView Dashboard

```elixir
defmodule NervesViewWeb.DashboardLive do
  @moduledoc """
  Main dashboard showing all cameras in a responsive grid.
  """
  use NervesViewWeb, :live_view
  
  alias NervesViewCore.Cameras.CameraRegistry
  
  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      # Subscribe to camera updates
      Phoenix.PubSub.subscribe(NervesView.PubSub, "cameras")
      Phoenix.PubSub.subscribe(NervesView.PubSub, "motion_events")
    end
    
    cameras = CameraRegistry.list_cameras()
    
    {:ok, assign(socket,
      cameras: cameras,
      layout: determine_layout(length(cameras)),
      current_user: session["current_user"]
    )}
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <div class="dashboard">
      <header class="dashboard-header">
        <h1>NervesView</h1>
        <div class="status-bar">
          <span class="camera-count"><%= length(@cameras) %> cameras</span>
          <.layout_selector layout={@layout} />
        </div>
      </header>
      
      <main class={"camera-grid layout-#{@layout}"}>
        <%= for camera <- @cameras do %>
          <.camera_tile camera={camera} />
        <% end %>
      </main>
    </div>
    """
  end
  
  defp camera_tile(assigns) do
    ~H"""
    <div class="camera-tile" id={"camera-#{@camera.id}"}>
      <div class="video-container" 
           phx-hook="WebRTCPlayer"
           data-camera-id={@camera.id}>
        <video autoplay muted playsinline></video>
        <div class="camera-overlay">
          <span class="camera-name"><%= @camera.name %></span>
          <span class="camera-status"><%= @camera.status %></span>
          <%= if @camera.motion_detected do %>
            <span class="motion-indicator">Motion</span>
          <% end %>
        </div>
      </div>
      <div class="camera-controls">
        <.link navigate={~p"/cameras/#{@camera.id}"}>
          <.icon name="hero-arrows-pointing-out" />
        </.link>
        <.link navigate={~p"/recordings?camera=#{@camera.id}"}>
          <.icon name="hero-video-camera" />
        </.link>
      </div>
    </div>
    """
  end
  
  @impl true
  def handle_info({:camera_updated, camera}, socket) do
    cameras = update_camera_in_list(socket.assigns.cameras, camera)
    {:noreply, assign(socket, cameras: cameras)}
  end
  
  def handle_info({:motion_detected, camera_id, detected}, socket) do
    cameras = socket.assigns.cameras
    |> Enum.map(fn cam ->
      if cam.id == camera_id do
        %{cam | motion_detected: detected}
      else
        cam
      end
    end)
    
    {:noreply, assign(socket, cameras: cameras)}
  end
  
  defp determine_layout(count) when count <= 1, do: "1"
  defp determine_layout(count) when count <= 4, do: "2x2"
  defp determine_layout(count) when count <= 9, do: "3x3"
  defp determine_layout(_), do: "4x4"
end
```

### WebRTC JavaScript Hook

```javascript
// assets/js/hooks/webrtc_player.js

const WebRTCPlayer = {
  mounted() {
    this.cameraId = this.el.dataset.cameraId;
    this.video = this.el.querySelector('video');
    this.pc = null;
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 5;
    
    this.connect();
  },
  
  destroyed() {
    this.cleanup();
  },
  
  async connect() {
    try {
      // Create peer connection
      this.pc = new RTCPeerConnection({
        iceServers: [
          { urls: 'stun:stun.l.google.com:19302' }
        ]
      });
      
      // Handle incoming tracks
      this.pc.ontrack = (event) => {
        console.log('Received track:', event.track.kind);
        if (event.track.kind === 'video') {
          this.video.srcObject = event.streams[0];
        }
      };
      
      // Handle ICE candidates
      this.pc.onicecandidate = (event) => {
        if (event.candidate) {
          this.sendIceCandidate(event.candidate);
        }
      };
      
      // Handle connection state
      this.pc.onconnectionstatechange = () => {
        console.log('Connection state:', this.pc.connectionState);
        if (this.pc.connectionState === 'failed') {
          this.handleReconnect();
        }
      };
      
      // Request offer from server
      const response = await fetch(`/api/webrtc/offer?camera_id=${this.cameraId}`);
      const { sdp, session_id } = await response.json();
      this.sessionId = session_id;
      
      // Set remote description (offer)
      await this.pc.setRemoteDescription({ type: 'offer', sdp });
      
      // Create and send answer
      const answer = await this.pc.createAnswer();
      await this.pc.setLocalDescription(answer);
      
      await fetch('/api/webrtc/answer', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          session_id: this.sessionId,
          sdp: answer.sdp
        })
      });
      
      this.reconnectAttempts = 0;
      
    } catch (error) {
      console.error('WebRTC connection failed:', error);
      this.handleReconnect();
    }
  },
  
  async sendIceCandidate(candidate) {
    await fetch('/api/webrtc/ice-candidate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        session_id: this.sessionId,
        candidate: candidate.toJSON()
      })
    });
  },
  
  handleReconnect() {
    if (this.reconnectAttempts < this.maxReconnectAttempts) {
      this.reconnectAttempts++;
      const delay = Math.min(1000 * Math.pow(2, this.reconnectAttempts), 30000);
      console.log(`Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts})`);
      setTimeout(() => {
        this.cleanup();
        this.connect();
      }, delay);
    }
  },
  
  cleanup() {
    if (this.pc) {
      this.pc.close();
      this.pc = null;
    }
  }
};

export default WebRTCPlayer;
```

---

## Hardware Requirements

### Minimum Setup (Single Camera Hub)

| Component | Recommended | Minimum |
|-----------|-------------|---------|
| **Board** | RPi 4 (4GB) | RPi 3B+ |
| **Camera** | RPi Camera Module 3 | RPi Camera Module v2 |
| **Storage** | 64GB+ USB SSD | 32GB SD Card |
| **Power** | Official 5V 3A PSU | 5V 2.5A |
| **Network** | Ethernet | WiFi |

### Camera Node (Additional Cameras)

| Component | Recommended | Minimum |
|-----------|-------------|---------|
| **Board** | RPi Zero 2W | RPi Zero 2W |
| **Camera** | RPi Camera Module 3 | Any CSI camera |
| **Storage** | 8GB SD Card | 8GB SD Card |
| **Power** | 5V 2A | 5V 1A |
| **Network** | WiFi | WiFi |

### Scalability Estimates

| Hub Device | Max Cameras | Max Viewers | Recording |
|------------|-------------|-------------|-----------|
| RPi 3B+ | 2-3 | 3-4 | 720p |
| RPi 4 (4GB) | 4-6 | 6-8 | 1080p |
| RPi 5 (8GB) | 8-12 | 10-15 | 1080p |
| Mini PC (x86) | 16+ | 20+ | 4K |

---

## Deployment Modes

### Mode 1: All-in-One (Default)

Single device acts as both camera and hub.

```
┌─────────────────────────────────┐
│         RPi 4 + Camera          │
│  ┌───────────┐ ┌─────────────┐  │
│  │  Camera   │ │   Phoenix   │  │
│  │  Capture  │ │   Server    │  │
│  └───────────┘ └─────────────┘  │
│  ┌───────────────────────────┐  │
│  │   Local Storage (SSD)     │  │
│  └───────────────────────────┘  │
└─────────────────────────────────┘
```

**Configuration:**
```elixir
# config/runtime.exs
config :nerves_view_firmware,
  mode: :hub,  # or :all_in_one
  local_camera: true,
  storage_path: "/data/recordings"
```

### Mode 2: Hub + Nodes

Separate hub with dedicated camera nodes.

```
┌──────────────┐     ┌──────────────┐     ┌──────────────────┐
│ RPi Zero 2W  │     │ RPi Zero 2W  │     │    RPi 4         │
│ + Camera     │────▶│ + Camera     │────▶│    (Hub)         │
│ (Node)       │     │ (Node)       │     │                  │
└──────────────┘     └──────────────┘     └──────────────────┘
```

**Node Configuration:**
```elixir
config :nerves_view_firmware,
  mode: :node,
  hub_host: "nervesview-hub.local",
  camera_name: "front-door"
```

**Hub Configuration:**
```elixir
config :nerves_view_firmware,
  mode: :hub,
  local_camera: false,  # hub-only, no local camera
  storage_path: "/data/recordings",
  auto_discover_nodes: true
```

### Mode 3: Existing Server

Use existing home server/NAS as hub, RPis only as cameras.

```
┌──────────────┐     ┌──────────────────────────────┐
│ RPi + Camera │────▶│   Home Server / NAS          │
│ (Node)       │     │   (Docker: nerves_view_web)  │
└──────────────┘     └──────────────────────────────┘
```

**Docker Compose:**
```yaml
version: '3'
services:
  nerves_view:
    image: ghcr.io/yourrepo/nerves_view_web:latest
    ports:
      - "4000:4000"
    volumes:
      - ./data:/app/data
    environment:
      - DATABASE_PATH=/app/data/nerves_view.db
      - RECORDINGS_PATH=/app/data/recordings
```

---

## Dependencies

### nerves_view_firmware/mix.exs

```elixir
defp deps do
  [
    # Nerves Core
    {:nerves, "~> 1.10", runtime: false},
    {:shoehorn, "~> 0.9"},
    {:ring_logger, "~> 0.11"},
    {:toolshed, "~> 0.4"},
    {:nerves_runtime, "~> 0.13"},
    {:nerves_pack, "~> 0.7", targets: @all_targets},
    
    # Target Systems
    {:nerves_system_rpi4, "~> 1.24", runtime: false, targets: :rpi4},
    {:nerves_system_rpi3, "~> 1.24", runtime: false, targets: :rpi3},
    {:nerves_system_rpi0_2, "~> 1.31", runtime: false, targets: :rpi0_2},
    {:nerves_system_rpi5, "~> 0.2", runtime: false, targets: :rpi5},
    
    # Camera Capture
    {:membrane_camera_capture_plugin, "~> 0.7"},
    # Note: May need custom libcamera plugin for newer RPi cameras
    
    # Membrane Pipeline
    {:membrane_core, "~> 1.0"},
    {:membrane_h264_ffmpeg_plugin, "~> 0.31"},
    {:membrane_h264_plugin, "~> 0.9"},
    {:membrane_file_plugin, "~> 0.16"},
    {:membrane_tee_plugin, "~> 0.12"},
    {:membrane_raw_video_format, "~> 0.4"},
    
    # WebRTC
    {:membrane_webrtc_plugin, "~> 0.17"},
    {:ex_webrtc, "~> 0.3"},
    
    # Motion Detection
    {:evision, "~> 0.1"},  # OpenCV bindings
    
    # HLS
    {:membrane_http_adaptive_stream_plugin, "~> 0.18"},
    
    # Networking
    {:mdns_lite, "~> 0.8"},
    {:vintage_net, "~> 0.13"},
    {:vintage_net_wifi, "~> 0.12"},
    {:vintage_net_ethernet, "~> 0.11"},
    
    # Clustering
    {:libcluster, "~> 3.3"},
    
    # Internal deps
    {:nerves_view_core, path: "../nerves_view_core"},
  ]
end
```

### nerves_view_core/mix.exs

```elixir
defp deps do
  [
    # Database
    {:ecto_sql, "~> 3.11"},
    {:ecto_sqlite3, "~> 0.12"},
    
    # Utilities
    {:jason, "~> 1.4"},
    {:timex, "~> 3.7"},
  ]
end
```

### nerves_view_web/mix.exs

```elixir
defp deps do
  [
    # Phoenix
    {:phoenix, "~> 1.7"},
    {:phoenix_ecto, "~> 4.4"},
    {:phoenix_html, "~> 4.0"},
    {:phoenix_live_reload, "~> 1.4", only: :dev},
    {:phoenix_live_view, "~> 0.20"},
    {:phoenix_live_dashboard, "~> 0.8"},
    
    # Assets
    {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
    {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
    
    # Authentication
    {:bcrypt_elixir, "~> 3.0"},
    
    # Utilities
    {:jason, "~> 1.4"},
    {:plug_cowboy, "~> 2.6"},
    {:gettext, "~> 0.24"},
    {:dns_cluster, "~> 0.1"},
    {:bandit, "~> 1.2"},
    
    # WebRTC
    {:ex_webrtc, "~> 0.3"},
    
    # Internal deps
    {:nerves_view_core, path: "../nerves_view_core"},
  ]
end
```

---

## Development Setup

### Prerequisites

```bash
# Install Nerves tooling
mix archive.install hex nerves_bootstrap

# Install Erlang/Elixir (via asdf recommended)
asdf install erlang 26.2
asdf install elixir 1.16.0-otp-26

# Install system dependencies (Ubuntu/Debian)
sudo apt install build-essential automake autoconf git squashfs-tools \
  ssh-askpass pkg-config curl libmnl-dev libssl-dev libncurses5-dev \
  bc m4 unzip cmake python3 libopencv-dev ffmpeg
```

### Local Development (Host Target)

```bash
# Clone and setup
cd nerves_view

# Fetch deps for all projects
cd nerves_view_firmware && mix deps.get && cd ..
cd nerves_view_core && mix deps.get && cd ..
cd nerves_view_web && mix deps.get && cd ..

# Run web in dev mode (without firmware)
cd nerves_view_web
mix phx.server

# Access at http://localhost:4000
```

### Firmware Development

```bash
# Set target
export MIX_TARGET=rpi4

# Build firmware
cd nerves_view_firmware
mix deps.get
mix firmware

# Burn to SD card
mix burn

# Or upload via SSH (after initial burn)
mix upload nervesview.local
```

### Testing on Host with Simulated Camera

```elixir
# config/host.exs
config :nerves_view_firmware,
  camera_source: :test_pattern,  # Use test pattern instead of real camera
  test_video_path: "test/fixtures/sample.mp4"
```

---

## Future Considerations

### Performance Optimizations

1. **Hardware Encoding**
   - Use RPi's VideoCore GPU via v4l2 codec interface
   - Investigate membrane_h264_plugin hardware encoder support

2. **Memory Management**
   - Use shared memory for video buffers (Membrane SHM)
   - Implement frame pooling to reduce allocations

3. **Network Efficiency**
   - Simulcast for multiple quality levels
   - SVC (Scalable Video Coding) when supported

### Potential Rust NIFs

If performance becomes an issue, consider Rust NIFs for:

```rust
// Hypothetical motion detection NIF
#[rustler::nif]
fn detect_motion(current: Binary, previous: Binary, threshold: f64) -> bool {
    // Optimized frame differencing
}

// Hypothetical image processing
#[rustler::nif]
fn resize_frame(frame: Binary, width: u32, height: u32) -> Binary {
    // Fast image resize
}
```

### WebAssembly Possibilities

Browser-side ML (optional enhancement):
- TensorFlow.js for person detection
- Face-api.js for face detection
- Custom WASM for video effects

### Community Integrations

- Home Assistant integration
- Frigate NVR compatibility
- ONVIF support for enterprise cameras
- Matrix/Discord notifications

---

## Success Metrics

### MVP Launch Criteria

- [ ] Single camera streaming with <1s latency
- [ ] Continuous recording for 24+ hours
- [ ] Motion detection with 90%+ accuracy
- [ ] 3+ concurrent viewers without degradation
- [ ] OTA update works reliably
- [ ] Setup time <30 minutes for new user

### Community Goals

- [ ] 100 GitHub stars
- [ ] 10 external contributors
- [ ] 5 blog posts/tutorials
- [ ] Working on 3+ RPi variants

---

## Getting Help

- GitHub Issues: Bug reports and feature requests
- GitHub Discussions: Questions and community chat
- Nerves Slack: #nerves-view channel (TBD)

---

*This document is a living plan. Update as implementation progresses.*
