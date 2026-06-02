#!/bin/bash
set -e

# Create our package directory
mkdir -p $SP_DIR/llama_cpp_tools
cp convert_hf_to_gguf.py $SP_DIR/llama_cpp_tools/
cp convert_llama_ggml_to_gguf.py $SP_DIR/llama_cpp_tools/
cp convert_lora_to_gguf.py $SP_DIR/llama_cpp_tools/

# Upstream b9445+ moved model definitions into a `conversion/` package; copy
# it under llama_cpp_tools/ so the redirected imports
# (`from llama_cpp_tools.conversion import ...`) resolve at runtime.
cp -r conversion $SP_DIR/llama_cpp_tools/

# Copy the models directory and its contents
cp -r models $SP_DIR/llama_cpp_tools/

# Create an __init__.py file to make it a proper Python package
touch $SP_DIR/llama_cpp_tools/__init__.py