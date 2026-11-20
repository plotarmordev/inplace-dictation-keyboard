// Runs on the audio thread: converts the microphone signal to 16-bit mono PCM at `rate`
// and hands it to the page in fixed-size chunks.

// Streaming downsampler. Each output sample is the exact average of the input signal over
// its time span, so input samples straddling two output samples are split by overlap.
class Downsampler {
  constructor(inputRate, outputRate) {
    this.span = inputRate / outputRate; // input samples per output sample, >= 1
    this.filled = 0;
    this.sum = 0;
  }

  feed(input, emit) {
    for (const sample of input) {
      const room = this.span - this.filled;
      if (room > 1) {
        this.sum += sample;
        this.filled += 1;
      } else {
        emit((this.sum + sample * room) / this.span);
        this.filled = 1 - room;
        this.sum = sample * this.filled;
      }
    }
  }
}

class PCMTap extends AudioWorkletProcessor {
  constructor({ processorOptions: { rate, chunkFrames } }) {
    super();
    this.downsampler = new Downsampler(sampleRate, rate);
    this.chunkFrames = chunkFrames;
    this.reset();
  }

  reset() {
    this.chunk = new Int16Array(this.chunkFrames);
    this.length = 0;
    this.peak = 0;
  }

  process([channels]) {
    if (channels.length === 0) return true;
    this.downsampler.feed(channels[0], (value) => {
      const clamped = Math.max(-1, Math.min(1, value));
      this.peak = Math.max(this.peak, Math.abs(clamped));
      this.chunk[this.length++] = Math.round(clamped * 0x7fff);
      if (this.length === this.chunkFrames) {
        this.port.postMessage({ pcm: this.chunk.buffer, peak: this.peak }, [this.chunk.buffer]);
        this.reset();
      }
    });
    return true;
  }
}

registerProcessor('pcm-tap', PCMTap);
