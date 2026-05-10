# NVIDIA NeMo parakeet-tdt-0.6b-v3, pre-converted to ONNX by sherpa-onnx
# upstream and shipped as a release tarball (encoder/decoder/joiner int8 +
# tokens). ~670 MB unpacked — large, but FOD-pinned so the cpu lane is
# reproducible offline.
#
# Shared between transcribe-cpu (sherpa-onnx runtime) and
# transcribe-npu/probe-parakeet (OpenVINO compile probe) so the FOD is
# fetched once, not duplicated per lane.
pkgs:
pkgs.fetchzip {
  url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2";
  hash = "sha256-3zMIAaTYBJZB8rXgaxHZdgBqBbrrLLN7USLH+JNTaDY=";
}
