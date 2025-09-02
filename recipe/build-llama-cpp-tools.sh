#!/bin/bash

# Create our package directory
mkdir -p $SP_DIR/llama_cpp_tools
cp convert_hf_to_gguf.py $SP_DIR/llama_cpp_tools/
cp convert_llama_ggml_to_gguf.py $SP_DIR/llama_cpp_tools/
cp convert_lora_to_gguf.py $SP_DIR/llama_cpp_tools/

# Copy the models directory and its contents
cp -r models $SP_DIR/llama_cpp_tools/

# Create an __init__.py file to make it a proper Python package
touch $SP_DIR/llama_cpp_tools/__init__.py