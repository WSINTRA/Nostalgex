// Playback information for the web tuner: what the browser and the server are doing with
// the programme on screen.
//
// PARITY with tvOS (PR #26)
//   Nostalgex/Nostalgex/Services/PlaybackInformation.swift        the model, rows and wording
//   Nostalgex/Nostalgex/App/AppState+PlaybackInformation.swift    begin / attempt / ready / rows
//   Nostalgex/Nostalgex/Views/NowPlayingPanel.swift               the PLAYBACK INFORMATION panel
//
// Same rows, same labels, same fallback sentences. Like the Swift model it only ever holds
// enums, bounded numbers and allowlisted codec names. It never stores an item, a URL, a
// server address, a token, a session id or an error message, so nothing private can reach
// the screen through it.
//
// Late callbacks. A programme gets a generation; each try at playing it (the first one, the
// server stream after a failed direct play, an hls.js recovery) gets an attempt id. Ready is
// only accepted for the current generation AND the current attempt, so an event left over
// from an earlier programme, or from an attempt that was replaced, cannot mark the
// replacement ready or describe it.
//
// What the web tuner fills in:
//   BACKEND          Plex, Jellyfin, Emby
//   PLAYBACK         Direct Play or Server stream once the video element is playing; Loading before
//   QUALITY AT TUNE  what this browser asked for: Plex gets no limit, Jellyfin and Emby 120 Mbps
//   PLAYER SIZE      the video element's videoWidth x videoHeight, once playing
//   SOURCE METADATA  the library's codec fields for the version being played
//   FALLBACK         none, server stream chosen, direct play failed, or an hls.js retry
// RECOVERY REQUEST stays hidden: the web tuner has no 1080p compatibility rung.
//
// USAGE (browser: plain <script src="scripts/nostalgex-playback-info.js">,
// node: `import "./nostalgex-playback-info.js"`, then globalThis):
//
//   const PI = window.NostalgexPlaybackInfo;
//   const info = PI.create({ generation, backend, qualityAtTune, videoCodec, audioCodec });
//   const attempt = info.beginAttempt(generation, 'directPlay', 'none');
//   info.markReady(generation, attempt);
//   info.rows(video.videoWidth, video.videoHeight);

(function (global) {
  'use strict';

  const BACKENDS = { plex: 'Plex', jellyfin: 'Jellyfin', emby: 'Emby', demo: 'Demo' };

  const DELIVERY = { unknown: 'Unknown', directPlay: 'Direct Play', serverStream: 'Server stream' };

  // Observed recovery decisions only, never a guessed cause or a server's error text.
  const REASONS = {
    none: 'No fallback used.',
    serverStreamSelected: 'Server streaming was selected for this source.',
    directPlayFailed: 'Direct Play failed. Trying a server stream.',
    startupNoPicture: 'No picture reached the startup deadline. Trying a different stream.',
    streamStalled: 'Playback stopped making progress. Trying a different stream.',
    playerRetry: 'The player could not open the stream. Retrying it once.',
  };

  const RECOVERY_REQUESTS = { compatibility1080p: 'Compatibility retry, up to 1080p' };

  // Same allowlists as PlaybackInformation.Source. Even codec fields are server text, so
  // only these fixed labels cross into the panel.
  const VIDEO_CODECS = {
    h264: 'H.264', avc: 'H.264', avc1: 'H.264', hevc: 'HEVC', h265: 'HEVC', hev1: 'HEVC', hvc1: 'HEVC',
    mpeg2video: 'MPEG-2', mpeg4: 'MPEG-4', av1: 'AV1', vp9: 'VP9', vc1: 'VC-1',
  };
  const AUDIO_CODECS = {
    aac: 'AAC', ac3: 'AC-3', eac3: 'E-AC-3', dts: 'DTS', dca: 'DTS', truehd: 'TrueHD', flac: 'FLAC',
    alac: 'ALAC', mp3: 'MP3', opus: 'Opus', vorbis: 'Vorbis', pcm: 'PCM',
  };

  const EVIDENCE_NOTE = 'Source codecs come from library metadata. Player size is reported by the browser. '
    + 'Quality is what this browser asked for at tune time, not a measured output. '
    + 'Server streams may copy or convert media; the tuner does not know which.';

  function codecLabel(value, video) {
    const key = String(value == null ? '' : value).trim().toLowerCase();
    const known = video ? VIDEO_CODECS : AUDIO_CODECS;
    return Object.prototype.hasOwnProperty.call(known, key) ? known[key] : 'Unknown';
  }

  /** The quality ceiling the web tuner asks for at tune time. It has no quality setting. */
  function webQualityLabel(backend) {
    if (backend === 'jellyfin' || backend === 'emby') return 'Up to 120 Mbps';
    if (backend === 'plex') return 'Server default';
    return 'Unknown';
  }

  function sizeLabel(width, height) {
    const w = Number(width), h = Number(height);
    if (!Number.isFinite(w) || !Number.isFinite(h) || w < 1 || h < 1 || w > 65536 || h > 65536) return 'Unknown';
    return `${Math.round(w)} × ${Math.round(h)}`;
  }

  let attemptSeq = 0;

  function create(opts = {}) {
    const generation = opts.generation;
    const backend = Object.prototype.hasOwnProperty.call(BACKENDS, opts.backend) ? BACKENDS[opts.backend] : 'Unknown';
    // Only the fixed labels webQualityLabel produces are accepted.
    const allowedQuality = new Set(['Up to 120 Mbps', 'Server default', 'Unknown']);
    const qualityAtTune = allowedQuality.has(opts.qualityAtTune) ? opts.qualityAtTune : 'Unknown';
    const source = { video: codecLabel(opts.videoCodec, true), audio: codecLabel(opts.audioCodec, false) };

    let delivery = 'unknown';
    let reason = 'none';
    let recoveryRequest = null;
    let isReady = false;
    let attemptId = null;

    return {
      get generation() { return generation; },
      get attemptId() { return attemptId; },
      get isReady() { return isReady; },

      /** A replaced player's ready state and size must not describe the one still loading. */
      invalidateAttempt() {
        attemptId = null;
        isReady = false;
      },

      /** Starts a try at playing this programme. Returns its id, or null for a stale generation. */
      beginAttempt(gen, nextDelivery, nextReason = 'none', nextRecovery = null) {
        if (gen !== generation) return null;
        attemptSeq += 1;
        attemptId = attemptSeq;
        isReady = false;
        delivery = Object.prototype.hasOwnProperty.call(DELIVERY, nextDelivery) ? nextDelivery : 'unknown';
        reason = Object.prototype.hasOwnProperty.call(REASONS, nextReason) ? nextReason : 'none';
        if (nextRecovery && Object.prototype.hasOwnProperty.call(RECOVERY_REQUESTS, nextRecovery)) {
          recoveryRequest = nextRecovery;
        }
        return attemptId;
      },

      /** Accepted only for this generation and the attempt that is current right now. */
      markReady(gen, id) {
        if (gen !== generation || id == null || id !== attemptId) return false;
        isReady = true;
        return true;
      },

      rows(width, height) {
        const rows = [
          { id: 'backend', label: 'BACKEND', value: backend },
          { id: 'delivery', label: 'PLAYBACK', value: isReady ? DELIVERY[delivery] : 'Loading' },
          { id: 'quality', label: 'QUALITY AT TUNE', value: qualityAtTune },
        ];
        if (recoveryRequest) {
          rows.push({ id: 'recovery', label: 'RECOVERY REQUEST', value: RECOVERY_REQUESTS[recoveryRequest] });
        }
        rows.push(
          { id: 'presentation', label: 'PLAYER SIZE', value: isReady ? sizeLabel(width, height) : 'Unknown' },
          { id: 'source', label: 'SOURCE METADATA', value: `Video: ${source.video} · Audio: ${source.audio}` },
          { id: 'reason', label: 'FALLBACK', value: REASONS[reason] },
        );
        return rows;
      },

      get evidenceNote() { return EVIDENCE_NOTE; },
    };
  }

  const api = {
    BACKENDS, DELIVERY, REASONS, RECOVERY_REQUESTS, EVIDENCE_NOTE,
    codecLabel, webQualityLabel, sizeLabel, create,
  };

  global.NostalgexPlaybackInfo = api;
  if (typeof module !== 'undefined' && typeof module.exports !== 'undefined') {
    module.exports = api;
  }
})(typeof window !== 'undefined' ? window : globalThis);
