Only the iOS test bundle includes these public speech samples; the app does not.

- `mandarin.wav`: FunASR Mandarin test sample, https://isv-data.oss-cn-hangzhou.aliyuncs.com/ics/MaaS/ASR/test_audio/BAC009S0764W0121.wav
- `english.wav`: JFK public speech excerpt from whisper.cpp, https://github.com/ggml-org/whisper.cpp/blob/master/samples/jfk.wav

The integration test runs the real SenseVoice INT8 model against both samples.
The test substitutes file-based capture to make recognition reproducible and
separately checks the native iOS microphone recording session.
