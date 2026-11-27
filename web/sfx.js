// Sound effects for Last Card, synthesized with the Web Audio API (no audio
// files). Used from Dart through lib/ui/sfx_web.dart.
window.lastCardSfx = (() => {
  const KEY = 'lc-muted';
  let muted = false;
  try {
    muted = localStorage.getItem(KEY) === '1';
  } catch (_) {}

  let ctx = null;
  let master = null;
  let noiseBuffer = null;

  // Browsers (iOS above all) only allow audio after a user gesture.
  function ensure() {
    if (!ctx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return null;
      ctx = new AC();
      master = ctx.createGain();
      master.gain.value = 0.55;
      master.connect(ctx.destination);
    }
    if (ctx.state === 'suspended') ctx.resume().catch(() => {});
    return ctx;
  }
  for (const ev of ['pointerdown', 'touchend', 'keydown']) {
    window.addEventListener(ev, ensure, { passive: true, capture: true });
  }

  function noise() {
    if (!noiseBuffer) {
      noiseBuffer = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
      const d = noiseBuffer.getChannelData(0);
      for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    }
    return noiseBuffer;
  }

  function envelope(t, peak, dur, attack = 0.004) {
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(peak, t + attack);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    g.connect(master);
    return g;
  }

  // Filtered noise: card flicks, slides, riffles and whooshes.
  function burst(t, dur, freq, { q = 0.8, gain = 0.3, to, type = 'bandpass' } = {}) {
    const src = ctx.createBufferSource();
    src.buffer = noise();
    const f = ctx.createBiquadFilter();
    f.type = type;
    f.Q.value = q;
    f.frequency.setValueAtTime(freq, t);
    if (to) f.frequency.exponentialRampToValueAtTime(to, t + dur);
    src.connect(f).connect(envelope(t, gain, dur));
    src.start(t, Math.random() * 0.5);
    src.stop(t + dur + 0.05);
  }

  // A pitched note, optionally gliding to another pitch.
  function tone(t, freq, dur, { gain = 0.12, type = 'sine', to, attack = 0.008 } = {}) {
    const o = ctx.createOscillator();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    if (to) o.frequency.exponentialRampToValueAtTime(to, t + dur);
    let out = o;
    if (type === 'square' || type === 'sawtooth') {
      // Soften buzzy waves so they never sound harsh on phone speakers.
      const lp = ctx.createBiquadFilter();
      lp.type = 'lowpass';
      lp.frequency.value = 2200;
      o.connect(lp);
      out = lp;
    }
    out.connect(envelope(t, gain, dur, attack));
    o.start(t);
    o.stop(t + dur + 0.05);
  }

  const notes = (t, freqs, step, opts) =>
    freqs.forEach((f, i) => tone(t + i * step, f, opts.dur, opts));

  const sounds = {
    card(t) {
      burst(t, 0.08, 2600, { gain: 0.45 });
      tone(t, 170, 0.07, { gain: 0.16, type: 'triangle', to: 80 });
    },
    draw(t) {
      burst(t, 0.2, 900, { gain: 0.22, to: 3200, q: 0.6 });
    },
    deal(t) {
      burst(t, 0.05, 3200 + Math.random() * 600, { gain: 0.16, q: 1 });
    },
    shuffle(t) {
      for (let i = 0; i < 24; i++) {
        const at = t + i * 0.045 + Math.random() * 0.012;
        burst(at, 0.04, 2600 + Math.random() * 1600, { gain: 0.14, q: 1.2 });
      }
    },
    flip(t) {
      burst(t, 0.1, 2000, { gain: 0.3 });
      tone(t + 0.02, 520, 0.14, { gain: 0.07, to: 980 });
    },
    turn(t) {
      tone(t, 784, 0.2, { gain: 0.09 });
      tone(t + 0.1, 1175, 0.3, { gain: 0.08 });
    },
    start(t) {
      notes(t, [523, 659, 784], 0.09, { dur: 0.22, gain: 0.08, type: 'triangle' });
    },
    skip(t) {
      tone(t, 440, 0.12, { gain: 0.12, type: 'square', to: 330 });
      tone(t + 0.11, 300, 0.18, { gain: 0.12, type: 'square', to: 200 });
    },
    reverse(t) {
      tone(t, 380, 0.24, { gain: 0.1, type: 'triangle', to: 760 });
      tone(t + 0.14, 760, 0.24, { gain: 0.09, type: 'triangle', to: 380 });
    },
    penalty(t) {
      tone(t, 260, 0.34, { gain: 0.14, type: 'sawtooth', to: 110 });
      burst(t, 0.25, 600, { gain: 0.12, to: 200, type: 'lowpass' });
    },
    wild(t) {
      notes(t, [523, 659, 784, 1047], 0.06, { dur: 0.25, gain: 0.07 });
    },
    last(t) {
      tone(t, 880, 0.12, { gain: 0.1, type: 'square' });
      tone(t + 0.12, 1319, 0.32, { gain: 0.1, type: 'square' });
    },
    caught(t) {
      tone(t, 320, 0.1, { gain: 0.14, type: 'square', to: 220 });
      tone(t + 0.12, 220, 0.28, { gain: 0.14, type: 'square', to: 120 });
    },
    swap(t) {
      burst(t, 0.4, 350, { gain: 0.25, to: 3200, q: 1.4 });
    },
    knockout(t) {
      tone(t, 130, 0.6, { gain: 0.22, to: 40 });
      burst(t, 0.4, 400, { gain: 0.16, to: 80, type: 'lowpass' });
    },
    win(t) {
      notes(t, [523, 659, 784], 0.11, { dur: 0.2, gain: 0.09, type: 'triangle' });
      tone(t + 0.33, 1047, 0.7, { gain: 0.1, type: 'triangle' });
      tone(t + 0.33, 784, 0.7, { gain: 0.05, type: 'triangle' });
    },
    lose(t) {
      notes(t, [392, 330, 262], 0.16, { dur: 0.3, gain: 0.09, type: 'triangle' });
    },
    tick(t) {
      tone(t, 1400, 0.03, { gain: 0.06, attack: 0.002 });
    },
    nope(t) {
      tone(t, 170, 0.1, { gain: 0.1, type: 'square' });
    },
  };

  return {
    play(name) {
      if (muted) return;
      const c = ensure();
      // Before the first tap the context is still locked: skip silently.
      if (!c || c.state !== 'running') return;
      const fn = sounds[name];
      if (fn) fn(c.currentTime + 0.01);
    },
    isMuted: () => muted,
    setMuted(value) {
      muted = !!value;
      try {
        localStorage.setItem(KEY, muted ? '1' : '0');
      } catch (_) {}
    },
  };
})();
