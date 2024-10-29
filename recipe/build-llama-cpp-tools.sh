#!/bin/bash

# Create our package directory
mkdir -p $SP_DIR/llama_cpp_tools
cp convert_hf_to_gguf.py $SP_DIR/llama_cpp_tools/
cp convert_llama_ggml_to_gguf.py $SP_DIR/llama_cpp_tools/
cp convert_lora_to_gguf.py $SP_DIR/llama_cpp_tools/

# Install the llava scripts from the examples directory
mkdir -p $SP_DIR/llama_cpp_tools/examples/llava
cp -r ./examples/llava/*.py $SP_DIR/llama_cpp_tools/examples/llava/

# Create an __init__.py file to make it a proper Python package
touch $SP_DIR/llama_cpp_tools/__init__.py
touch $SP_DIR/llama_cpp_tools/examples/__init__.py
touch $SP_DIR/llama_cpp_tools/examples/llava/__init__.py