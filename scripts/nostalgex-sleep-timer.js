// Sleep timer for the web tuner.
//
// PARITY with tvOS
//   Nostalgex/Nostalgex/Services/NowPlayingPanelLogic.swift   SleepTimerLogic (presets, labels)
//   Nostalgex/Nostalgex/App/AppState+Playback.swift            startSleepTimer, cancelSleepTimer,
//                                                              keepAwakeFromGrace, beginSleepGrace,
//                                                              expireSleepTimer, revalidateSleepTimerOnForeground
//   Nostalgex/Nostalgex/Views/NowPlayingPanel.swift            SleepGracePrompt ("STILL WATCHING?")
//
// Same choices (OFF, 15 MIN, 30 MIN, 1 HR), same countdown format, same 20 second
// "Still watching?" grace before playback stops, and any input during the grace keeps
// watching and uses the timer up. It survives channel changes and is never saved: a
// reload starts with it off, the way a relaunch does on Apple TV.
//
// One web-only addition: a hidden tab throttles timers, so `revalidate()` also ends a
// grace whose deadline passed while the tab was in the background. tvOS only needs the
// first half of that, because a backgrounded app is not playing.
//
// USAGE (browser: plain <script src="scripts/nostalgex-sleep-timer.js">,
// node: `import "./nostalgex-sleep-timer.js"`, then globalThis):
//
//   const ST = window.NostalgexSleepTimer;
//   const timer = ST.createSleepTimer({ onGraceStart, onExpire, onChange });
//   timer.start(30); timer.cancel(); timer.keepAwake(); timer.revalidate(); timer.state();

(function (global) {
  'use strict';

  /** Minute presets offered in the picker. OFF is a separate row. */
  const PRESETS = [15, 30, 60];

  /** Seconds the "Still watching?" prompt waits before playback stops. */
  const GRACE_SECONDS = 20;

  /**
   * The minute rows to render, given whatever timer is armed. A running timer whose
   * duration is no longer offered keeps its row until it fires or is cancelled.
   */
  function offeredMinutes(armed) {
    if (!(armed > 0) || PRESETS.includes(armed)) return PRESETS.slice();
    return PRESETS.concat([armed]).sort((a, b) => a - b);
  }

  /** Seconds left until `endMs`, clamped at 0. `null` when the timer is off. */
  function remaining(endMs, nowMs) {
    if (endMs == null) return null;
    return Math.max(0, (endMs - nowMs) / 1000);
  }

  /** True only when an armed timer has reached or passed its end. */
  function isExpired(endMs, nowMs) {
    return endMs != null && nowMs >= endMs;
  }

  /** "OFF", "15 MIN", "1 HR", "1 HR 30 MIN". */
  function label(minutes) {
    if (!(minutes > 0)) return 'OFF';
    const hours = Math.floor(minutes / 60);
    const mins = minutes % 60;
    if (hours === 0) return `${mins} MIN`;
    if (mins === 0) return `${hours} HR`;
    return `${hours} HR ${mins} MIN`;
  }

  /** "m:ss", or "h:mm:ss" past an hour. Rounded to the nearest second, as on tvOS. */
  function countdownLabel(seconds) {
    const total = Math.max(0, Math.round(seconds || 0));
    const h = Math.floor(total / 3600);
    const m = Math.floor((total % 3600) / 60);
    const s = total % 60;
    const pad = (n) => String(n).padStart(2, '0');
    return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
  }

  /**
   * The timer itself. Clock and timer functions are injectable so the expiry, the
   * grace and a cancel can be tested without waiting.
   */
  function createSleepTimer(options = {}) {
    const now = options.now || (() => Date.now());
    const setT = options.setTimeout || ((fn, ms) => global.setTimeout(fn, ms));
    const clearT = options.clearTimeout || ((id) => global.clearTimeout(id));
    const graceSeconds = options.graceSeconds == null ? GRACE_SECONDS : options.graceSeconds;
    const onChange = options.onChange || (() => {});
    const onGraceStart = options.onGraceStart || (() => {});
    const onExpire = options.onExpire || (() => {});

    let endMs = null;
    let minutes = null;
    let graceActive = false;
    let graceDeadline = null;
    let timer = null;
    let graceTimer = null;

    function clearTimers() {
      if (timer != null) { clearT(timer); timer = null; }
      if (graceTimer != null) { clearT(graceTimer); graceTimer = null; }
    }

    function state() {
      const t = now();
      return {
        armed: endMs != null,
        minutes,
        endMs,
        remainingSeconds: remaining(endMs, t),
        graceActive,
        graceRemainingSeconds: graceActive ? remaining(graceDeadline, t) : null,
      };
    }

    function off() {
      clearTimers();
      endMs = null;
      minutes = null;
      graceActive = false;
      graceDeadline = null;
    }

    /** Arms the timer for `mins`. Zero or less cancels. Replaces any running timer. */
    function start(mins) {
      off();
      if (!(mins > 0)) { onChange(state()); return; }
      minutes = mins;
      endMs = now() + mins * 60000;
      timer = setT(beginGrace, mins * 60000);
      onChange(state());
    }

    /** Turns the timer off and dismisses any grace prompt. */
    function cancel() {
      off();
      onChange(state());
    }

    /** Input during the grace: keep playing, and the timer is used up. */
    function keepAwake() {
      if (!graceActive) return false;
      off();
      onChange(state());
      return true;
    }

    function beginGrace() {
      if (timer != null) { clearT(timer); timer = null; }
      if (graceActive || endMs == null) return;
      graceActive = true;
      graceDeadline = now() + graceSeconds * 1000;
      graceTimer = setT(expire, graceSeconds * 1000);
      onGraceStart(state());
      onChange(state());
    }

    function expire() {
      graceTimer = null;
      if (!graceActive) return;
      off();
      onExpire();
      onChange(state());
    }

    /** Catches up after a throttled or hidden tab, the way tvOS does on foreground. */
    function revalidate() {
      const t = now();
      if (graceActive) {
        if (graceDeadline != null && t >= graceDeadline) expire();
        return;
      }
      if (isExpired(endMs, t)) beginGrace();
    }

    return { start, cancel, keepAwake, revalidate, state };
  }

  const api = {
    PRESETS, GRACE_SECONDS, offeredMinutes, remaining, isExpired, label, countdownLabel, createSleepTimer,
  };

  global.NostalgexSleepTimer = api;
  if (typeof module !== 'undefined' && typeof module.exports !== 'undefined') {
    module.exports = api;
  }
})(typeof window !== 'undefined' ? window : globalThis);
