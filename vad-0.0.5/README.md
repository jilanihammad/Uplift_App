# VAD
VAD is a Flutter library for Voice Activity Detection (VAD) across **iOS** , **Android** , and **Web**  platforms. This package allows applications to start and stop VAD-based listening and handle various VAD events seamlessly.
Under the hood, the VAD Package uses `dart:js_interop` for Web to run [VAD JavaScript library](https://github.com/ricky0123/vad) and [onnxruntime](https://github.com/gtbluesky/onnxruntime_flutter) for iOS and Android utilizing onnxruntime library with full-feature parity with the JavaScript library.
The package provides a simple API to start and stop VAD listening, configure VAD parameters, and handle VAD events such as speech start, speech end, errors, and misfires.

## Table of Contents
<!-- TOC start (generated with https://github.com/derlin/bitdowntoc) -->

- [VAD](#vad)
    * [Table of Contents](#table-of-contents)
    * [Live Demo](#live-demo)
    * [Features](#features)
    * [Getting Started](#getting-started)
        + [Prerequisites](#prerequisites)
            - [Web](#web)
            - [iOS](#ios)
            - [Android](#android)
    * [Installation](#installation)
    * [Usage](#usage)
        + [Example](#example)
            - [Explanation of the Example](#explanation-of-the-example)
    * [VadHandler API](#vadhandler-api)
        + [Methods](#methods)
            - [`create`](#create)
            - [`startListening`](#startlistening)
            - [`stopListening`](#stoplistening)
            - [`dispose`](#dispose)
        +  [Events](#events)
            - [`onSpeechEnd`](#onspeechend)
            - [`onSpeechStart`](#onspeechstart)
            - [`onRealSpeechStart`](#onrealspeechstart)
            - [`onVADMisfire`](#onvadmisfire)
            - [`onFrameProcessed`](#onframeprocessed)
            - [`onError`](#onerror)
    * [Permissions](#permissions)
        + [iOS](#ios-1)
        + [Android](#android-1)
        + [Web](#web-1)
    * [Cleaning Up](#cleaning-up)
    * [Tested Platforms](#tested-platforms)
    * [Contributing](#contributing)
    * [Acknowledgements](#acknowledgements)
    * [License](#license)

<!-- TOC end -->

## Live Demo
Check out the [VAD Package Example App](https://keyur2maru.github.io/vad/) to see the VAD Package in action on the Web platform.

## Features

- **Cross-Platform Support:**  Works seamlessly on iOS, Android, and Web.

- **Event Streams:**  Listen to events such as speech start, real speech start, speech end, speech misfire, frame processed, and errors.

- **Silero V4 and V5 Models:**  Supports both Silero VAD v4 and v5 models.

## Getting Started

### Prerequisites

Before integrating the VAD Package into your Flutter application, ensure that you have the necessary configurations for each target platform.

#### Web
To use VAD on the web, include the following scripts within the head and body tags respectively in the `web/index.html` file to load the necessary VAD libraries:

```html
<head>
  ...
  <script src="assets/packages/vad/assets/ort.js"></script>
  ...
</head>
...
<body>
...
<script src="assets/packages/vad/assets/bundle.min.js" defer></script>
<script src="assets/packages/vad/assets/vad_web.js" defer></script>
...
</body>
```

You can also refer to the [VAD Example App](https://github.com/keyur2maru/vad/blob/master/example/web/index.html) for a complete example.

**Tip: Enable WASM multithreading (SharedArrayBuffer) for a 10x performance improvement** 

* For Production, send the following headers in your server response:
  ```html
  Cross-Origin-Embedder-Policy: require-corp
  Cross-Origin-Opener-Policy: same-origin
  ```

* For Local, refer to the workaround applied in the GitHub Pages demo page for the example app. It is achieved with the inclusion of [enable-threads.js](https://github.com/keyur2maru/vad/blob/master/example/web/enable-threads.js) and loading it in the [web/index.html#L24](https://github.com/keyur2maru/vad/blob/master/example/web/index.html#L24) file in the example app.


#### iOS
For iOS, you need to configure microphone permissions and other settings in your `Info.plist` file.
1. **Add Microphone Usage Description:** Open `ios/Runner/Info.plist` and add the following entries to request microphone access:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs access to the microphone for Voice Activity Detection.</string>
```

2. **Configure Build Settings:** Ensure that your `Podfile` includes the necessary build settings for microphone permissions:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_MICROPHONE=1',
      ]
    end
  end
end
```

#### Android
For Android, configure the required permissions and build settings in your `AndroidManifest.xml` and `build.gradle` files.
1. **Add Permissions:** Open `android/app/src/main/AndroidManifest.xml` and add the following permissions:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
```

2. **Configure Build Settings:** Open `android/app/build.gradle` and add the following settings:
```gradle
android {
    compileSdkVersion 34
    ...
}
```


## Installation
Add the VAD Package to your `pubspec.yaml` dependencies:
```yaml
dependencies:
  flutter:
    sdk: flutter
  vad: ^0.0.5
  permission_handler: ^11.3.1
```
Then, run `flutter pub get` to fetch the packages.
## Usage

### Example

Below is a simple example demonstrating how to integrate and use the VAD Package in a Flutter application.
For a more detailed example, check out the [VAD Example App](https://github.com/keyur2maru/vad/tree/master/example) in the GitHub repository.


```dart
// main.dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vad/vad.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text("VAD Example")),
        body: const MyHomePage(),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _vadHandler = VadHandler.create(isDebug: true);
  bool isListening = false;
  final List<String> receivedEvents = [];

  @override
  void initState() {
    super.initState();
    _setupVadHandler();
  }

  void _setupVadHandler() {
    _vadHandler.onSpeechStart.listen((_) {
      debugPrint('Speech detected.');
      setState(() {
        receivedEvents.add('Speech detected.');
      });
    });

    _vadHandler.onRealSpeechStart.listen((_) {
      debugPrint('Real speech start detected (not a misfire).');
      setState(() {
        receivedEvents.add('Real speech start detected (not a misfire).');
      });
    });

    _vadHandler.onSpeechEnd.listen((List<double> samples) {
      debugPrint('Speech ended, first 10 samples: ${samples.take(10).toList()}');
      setState(() {
        receivedEvents.add('Speech ended, first 10 samples: ${samples.take(10).toList()}');
      });
    });

    _vadHandler.onFrameProcessed.listen((frameData) {
      final isSpeech = frameData.isSpeech;
      final notSpeech = frameData.notSpeech;
      final firstFewSamples = frameData.frame.take(5).toList();

      debugPrint('Frame processed - Speech probability: $isSpeech, Not speech: $notSpeech');
      debugPrint('First few audio samples: $firstFewSamples');

      // You can use this for real-time audio processing
    });

    _vadHandler.onVADMisfire.listen((_) {
      debugPrint('VAD misfire detected.');
      setState(() {
        receivedEvents.add('VAD misfire detected.');
      });
    });

    _vadHandler.onError.listen((String message) {
      debugPrint('Error: $message');
      setState(() {
        receivedEvents.add('Error: $message');
      });
    });
  }

  @override
  void dispose() {
    _vadHandler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton.icon(
            onPressed: () async {
              setState(() {
                if (isListening) {
                  _vadHandler.stopListening();
                } else {
                  _vadHandler.startListening();
                }
                isListening = !isListening;
              });
            },
            icon: Icon(isListening ? Icons.stop : Icons.mic),
            label: Text(isListening ? "Stop Listening" : "Start Listening"),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              final status = await Permission.microphone.request();
              debugPrint("Microphone permission status: $status");
            },
            icon: const Icon(Icons.settings_voice),
            label: const Text("Request Microphone Permission"),
            style: TextButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: receivedEvents.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(receivedEvents[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```
#### Explanation of the Example
1. **Initialization:**
- Initializes the `VadHandler` with debugging enabled.

- Sets up listeners for various VAD events (`onSpeechStart`, `onRealSpeechStart`, `onSpeechEnd`, `onFrameProcessed`, `onVADMisfire`, `onError`).

2.  **Permissions:**
- Requests microphone permission when the "Request Microphone Permission" button is pressed.

3. **Listening Controls:**
- Toggles listening on and off with the "Start Listening"/"Stop Listening" button.

- Configures the audio player to mix with other audio sources on iOS.

4. **Event Handling:**
- Displays received events in a list view.

- Updates the UI based on the received events.

**Note: For Real-time Audio Processing, listen to the onFrameProcessed events to access raw audio frames and speech probabilities as they're processed.**
## VadHandler API

### Methods


#### `create`
Creates a new instance of the `VadHandler` with optional debugging enabled with the `isDebug` parameter and optional configurable model path with the `modelPath` parameter but it's only applicable for the iOS and Android platforms. It has no effect on the Web platform.

#### `startListening`
Starts the VAD with configurable parameters.
Notes:
- The sample rate is fixed at 16kHz, which means when using legacy model with default frameSamples value, one frame is equal to 1536 samples or 96ms.
- For Silero VAD v5 model, frameSamples must be set to 512 samples unlike the previous version, so one frame is equal to 32ms.
- `model` parameter can be set to 'legacy' or 'v5' to use the respective VAD model. Default is 'legacy'.
- `baseAssetPath` and `onnxWASMBasePath` are the default paths for the VAD JavaScript library and onnxruntime WASM files respectively. Currently, they are bundled with the package but can be overridden if needed by providing custom paths or CDN URLs. **<u>Only applicable for the Web platform.</u>**

```dart
void startListening({
  double positiveSpeechThreshold = 0.5,
  double negativeSpeechThreshold = 0.35,
  int preSpeechPadFrames = 1,
  int redemptionFrames = 8,
  int frameSamples = 1536,
  int minSpeechFrames = 3,
  bool submitUserSpeechOnPause = false,
  String model = 'legacy',
  String baseAssetPath = 'assets/packages/vad/assets/',
  String onnxWASMBasePath = 'assets/packages/vad/assets/',
});
```

#### `stopListening`
Stops the VAD session.


```dart
void stopListening();
```

#### `dispose`
Disposes the VADHandler and closes all streams.


```dart
void dispose();
```

## Events
Available event streams to listen to various VAD events:

#### `onSpeechEnd`
Emitted when speech end is detected, providing audio samples.

#### `onSpeechStart`
Emitted when speech start is detected.

#### `onRealSpeechStart`
Emitted when actual speech is confirmed (exceeds minimum frames threshold).

#### `onVADMisfire`
Emitted when speech was initially detected but didn't meet the minimum speech frames threshold.

#### `onFrameProcessed`
Emitted after each audio frame is processed, providing speech probabilities and raw audio data.

#### `onError`
Emitted when an error occurs.


## Permissions

Proper handling of microphone permissions is crucial for the VAD Package to function correctly on all platforms.

### iOS

- **Configuration:** Ensure that `NSMicrophoneUsageDescription` is added to your `Info.plist` with a descriptive message explaining why the app requires microphone access.

- **Runtime Permission:** Request microphone permission at runtime using the `permission_handler` package.

### Android

- **Configuration:** Add the `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`, and `INTERNET` permissions to your `AndroidManifest.xml`.

- **Runtime Permission:** Request microphone permission at runtime using the `permission_handler` package.

### Web

- **Browser Permissions:**
  Microphone access is managed by the browser. Users will be prompted to grant microphone access when the VAD starts listening.

## Cleaning Up

To prevent memory leaks and ensure that all resources are properly released, always call the `dispose` method on the `VadHandler` instance when it's no longer needed.

```dart
vadHandler.dispose();
```

## Tested Platforms
The VAD Package has been tested on the following platforms:

- **iOS:**  Tested on iPhone 15 Pro Max running iOS 18.1.
- **Android:**  Tested on Lenovo Tab M8 Running Android 10.
- **Web:**  Tested on Chrome Mac/Windows/Android/iOS, Safari Mac/iOS.

## Contributing
Contributions are welcome! Please feel free to submit a pull request or open an issue if you encounter any problems or have suggestions for improvements.

## Acknowledgements
Special thanks to [Ricky0123](https://github.com/ricky0123) for creating the [VAD JavaScript library](https://github.com/ricky0123/vad), [gtbluesky](https://github.com/gtbluesky) for building the [onnxruntime package](https://github.com/gtbluesky/onnxruntime_flutter) and Silero Team for the [VAD model](https://github.com/snakers4/silero-vad) used in the library.


## License
This project is licensed under the [MIT License](https://opensource.org/license/mit). See the [LICENSE](https://github.com/keyur2maru/vad/blob/master/LICENSE)  file for details.

---

For any issues or contributions, please visit the [GitHub repository](https://github.com/keyur2maru/vad).