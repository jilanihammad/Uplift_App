// vad_web.js

function logMessage(message) {
  console.log(message);
}

let isListening = false;
let vadInstance = null;

function startListeningImpl(
  positiveSpeechThreshold,
  negativeSpeechThreshold,
  preSpeechPadFrames,
  redemptionFrames,
  frameSamples,
  minSpeechFrames,
  submitUserSpeechOnPause,
  model,
  baseAssetPath,
  onnxWASMBasePath
) {
  if (isListening || vadInstance) return;

  isListening = true;
  // Initialize and start VAD service
  async function initializeVAD() {
    try {
      vadInstance = await vad.MicVAD.new({
        positiveSpeechThreshold,
        negativeSpeechThreshold,
        preSpeechPadFrames,
        redemptionFrames,
        frameSamples,
        minSpeechFrames,
        submitUserSpeechOnPause,
        model,
        baseAssetPath,
        onnxWASMBasePath,
        onVADMisfire: () => {
          onVADMisfireCallback();
        },
        onSpeechStart: () => {
          onSpeechStartCallback();
        },
        onSpeechEnd: (audio) => {
          onSpeechEndCallback(audio);
        },
        onSpeechRealStart: () => {
          onRealSpeechStartCallback();
        },
        onFrameProcessed: (probabilities, frame) => {
          onFrameProcessedCallback(probabilities, frame);
        }
      });
      vadInstance.start();
    } catch (err) {
      onErrorCallback(err);
    }
  }
  initializeVAD();
}

function stopListeningImpl() {
  if (vadInstance) {
    vadInstance.pause();
    vadInstance.destroy();
    isListening = false;
    vadInstance = null;
  } else {
    onErrorCallback("VAD instance is not initialized");
  }
}

function isListeningNow() {
  return isListening;
}

const onErrorCallback = (error) => {
  if (typeof executeDartHandler === 'function') {
    if (error instanceof DOMException) {
      error = error.toString();
    }
    error = JSON.stringify({ error });
    executeDartHandler("onError", error);
  } else {
    console.error(error);
  }
};

const onSpeechEndCallback = (float32Array) => {
  const audioArray = Array.from(float32Array);
  const jsonData = JSON.stringify({ 
    audioData: audioArray,
  });
  
  if (typeof executeDartHandler === 'function') {
    executeDartHandler("onSpeechEnd", jsonData);
  } else {
    onErrorCallback("executeDartHandler is not a function");
  }
};

const onFrameProcessedCallback = (probabilities, frame) => {
  const frameArray = Array.from(frame);
  const jsonData = JSON.stringify({
    probabilities: {
      isSpeech: probabilities.isSpeech,
      notSpeech: probabilities.notSpeech
    },
    frame: frameArray
  });

  if (typeof executeDartHandler === 'function') {
    executeDartHandler("onFrameProcessed", jsonData);
  } else {
    onErrorCallback("executeDartHandler is not a function");
  }
};

const onSpeechStartCallback = () => {
  if (typeof executeDartHandler === 'function') {
    executeDartHandler("onSpeechStart", "");
  } else {
    onErrorCallback("executeDartHandler is not a function");
  }
};

const onRealSpeechStartCallback = () => {
  if (typeof executeDartHandler === 'function') {
    executeDartHandler("onRealSpeechStart", "");
  } else {
    onErrorCallback("executeDartHandler is not a function");
  }
}

const onVADMisfireCallback = () => {
  if (typeof executeDartHandler === 'function') {
    executeDartHandler("onVADMisfire", "");
  } else {
    onErrorCallback("executeDartHandler is not a function");
  }
};
