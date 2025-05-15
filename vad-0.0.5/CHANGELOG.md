## 0.0.5

* Add support for Silero VAD v5 model. (Default model is set to v4)
* Automatically upsample audio to 16kHz if the input audio is not 16kHz (fixes model load failures due to lower sample rates).
* Expose `onRealSpeechStart` event to notify when the number of speech positive frames exceeds the minimum speech frames (i.e. not a misfire event).
* Expose `onFrameProcessed` event to track VAD decisions by exposing speech probabilities and frame data for real-time processing.
* Update example app to show the `onRealSpeechStart` callback in action and introduce VAD Settings dialog to change the VAD model and other settings at runtime.
* For web platform, bundle the required files within the package to avoid download failures when fetching from CDNs and to ensure offline support.
* Update example app to log `onFrameProcessed` details for debugging.

## 0.0.4

* Fixed a bug where default `modelPath` was not picked up, resulting in silent failure if `modelPath` was not provided.
* Export `VadIterator` class for manual control over the VAD process for non-streaming use cases. Only available on iOS/Android.
* Added comments for all public methods and classes.

## 0.0.3

* Switch to `onnxruntime` package for inference on a separate isolate on iOS and Android to avoid using a full browser in the background, overall reducing the app size and improving performance.
* Example app will show audio track slider with controls while speech segment is being played and it will reflect a misfire event on the UI if occurred.

## 0.0.2

* Fix broken LICENSE hyperlink in README.md and add topics to pubspec.yaml

## 0.0.1

* Initial release
