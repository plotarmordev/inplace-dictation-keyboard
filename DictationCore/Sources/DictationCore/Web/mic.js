// Page side of the microphone bridge. Native code calls Mic.open() and Mic.close(); the page
// reports `{state}` changes and `{pcm, level}` audio chunks to the `mic` message handler.
//
// Every audio chunk is acknowledged by native code. If acknowledgements stop arriving (the
// keyboard was suspended or torn down) the page releases the microphone on its own.

const TARGET_RATE = 16000;
const CHUNK_SECONDS = 0.1;
const STALL_MS = 2500;

const native = window.webkit.messageHandlers.mic;
let session = null;

const toBase64 = (buffer) => btoa(String.fromCharCode(...new Uint8Array(buffer)));

function close(reason = 'closed') {
  const ended = session;
  if (!ended) return;
  session = null;
  ended.stream?.getTracks().forEach((track) => track.stop());
  ended.context?.close();
  native.postMessage({ state: 'ended', reason });
}

async function open() {
  close('reopened');
  const mine = (session = { lastAck: performance.now() });
  const current = () => session === mine;
  const endIfCurrent = (reason) => current() && close(reason);

  try {
    if (navigator.audioSession) navigator.audioSession.type = 'play-and-record';
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    if (!current()) return stream.getTracks().forEach((track) => track.stop());
    mine.stream = stream;
    stream.getAudioTracks()[0].onended = () => endIfCurrent('track-ended');

    // Created only now: an idle AudioContext would claim the audio route while the
    // keyboard is merely on screen.
    const context = (mine.context = new AudioContext({ latencyHint: 'interactive' }));
    await context.audioWorklet.addModule('pcm-worklet.js');
    await context.resume();
    if (!current()) return;

    const rate = Math.min(TARGET_RATE, context.sampleRate);
    const tap = new AudioWorkletNode(context, 'pcm-tap', {
      processorOptions: { rate, chunkFrames: Math.round(rate * CHUNK_SECONDS) },
    });
    tap.port.onmessage = ({ data }) => {
      if (!current()) return;
      if (performance.now() - mine.lastAck > STALL_MS) return close('unacknowledged');
      native
        .postMessage({ pcm: toBase64(data.pcm), level: data.peak })
        .then(() => (mine.lastAck = performance.now()), () => endIfCurrent('bridge-lost'));
    };
    // Connect through a zero-gain node so the worklet stays pulled without making the mic audible.
    const mute = new GainNode(context, { gain: 0 });
    context.createMediaStreamSource(stream).connect(tap).connect(mute).connect(context.destination);
    context.onstatechange = () => context.state === 'running' || endIfCurrent(`context-${context.state}`);

    mine.lastAck = performance.now();
    native.postMessage({ state: 'live', rate });
  } catch (error) {
    endIfCurrent(`${error.name}: ${error.message}`);
  }
}

addEventListener('pagehide', () => close('page-hidden'));
document.addEventListener('visibilitychange', () => document.hidden && close('page-hidden'));

window.Mic = { open, close };
native.postMessage({ state: 'ready' });
