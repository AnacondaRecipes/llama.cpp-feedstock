#! /bin/bash
set -e

cd gguf-py
# Relax upstream's `numpy (>=2.2.6)` in pyproject.toml to match the conda run:
# pin (`numpy >=2.2.5`). pkgs/main tops out at numpy 2.2.5 for py3.10 — 2.2.6+
# builds start at py3.11 — so leaving the upstream constraint would let the
# conda solver pass but fail `pip check` on py3.10 with:
#   gguf 0.19.0 has requirement numpy>=2.2.6, but you have numpy 2.2.5.
# Revert once pkgs/main ships numpy 2.2.6+ for py3.10 (or if the py-skip
# floor moves to py3.11); keep in lockstep with the run: pin in meta.yaml.
sed -i.bak "s/'numpy (>=2.2.6)'/'numpy (>=2.2.5)'/" pyproject.toml
grep "'numpy" pyproject.toml
rm -f pyproject.toml.bak

pip install . -vv --no-deps --no-build-isolation
