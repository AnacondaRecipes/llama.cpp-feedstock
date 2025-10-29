#!/bin/bash
# Automated CUDA Build Script for Linux EC2 Instance (llama.cpp b6653)
# This script should be run on a g4dn.4xlarge instance with CUDA 12.4
# Prerequisites: Docker with NVIDIA runtime support

set -e  # Exit on any error

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  llama.cpp CUDA Build - Linux${NC}"
echo -e "${BLUE}  Version: b6653${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Verify CUDA availability
echo -e "${GREEN}[1/9] Verifying CUDA availability on host...${NC}"
if ! command -v nvidia-smi &> /dev/null; then
    echo -e "${RED}ERROR: nvidia-smi not found. This instance may not have NVIDIA GPU support.${NC}"
    exit 1
fi
nvidia-smi
if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: nvidia-smi failed. CUDA may not be properly configured.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ CUDA is available${NC}"
echo ""

# Step 2: Create working directory
echo -e "${GREEN}[2/9] Creating working directory...${NC}"
cd ~
mkdir -p llama-cuda-build
cd llama-cuda-build
echo -e "${GREEN}✓ Working directory created: $(pwd)${NC}"
echo ""

# Step 3: Start CUDA-enabled Docker container
echo -e "${GREEN}[3/9] Starting CUDA-enabled Docker container...${NC}"
if docker ps -a --format '{{.Names}}' | grep -q '^llama-cuda-build$'; then
    echo -e "${YELLOW}Container 'llama-cuda-build' already exists. Removing...${NC}"
    docker rm -f llama-cuda-build
fi

docker run -itd --name llama-cuda-build \
    -v $(pwd):/io \
    --gpus all \
    public.ecr.aws/y0o4y9o3/anaconda-pkg-build:main-cuda

if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Failed to start Docker container${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Docker container started${NC}"
docker ps | grep llama-cuda-build
echo ""

# Step 4: Setup build environment inside container
echo -e "${GREEN}[4/9] Setting up conda environment inside container...${NC}"
docker exec llama-cuda-build bash -c "
    set -e
    echo -e '${BLUE}  → Initializing conda...${NC}'
    conda init bash
    source ~/.bashrc

    cd /io

    echo -e '${BLUE}  → Creating checkout environment...${NC}'
    conda create -n checkout -y curl git

    echo -e '${BLUE}  → Downloading aggregate conda_build_config.yaml...${NC}'
    conda run -n checkout curl -O https://raw.githubusercontent.com/AnacondaRecipes/aggregate/master/conda_build_config.yaml

    echo -e '${GREEN}✓ Conda environment ready${NC}'
"
echo ""

# Step 5: Clone the repository
echo -e "${GREEN}[5/9] Cloning llama.cpp-feedstock repository...${NC}"
docker exec llama-cuda-build bash -c "
    set -e
    cd /io

    if [ -d llama.cpp-feedstock ]; then
        echo -e '${YELLOW}Repository directory already exists. Removing...${NC}'
        rm -rf llama.cpp-feedstock
    fi

    echo -e '${BLUE}  → Cloning branch: update-llama-cpp-b6653${NC}'
    conda run -n checkout git clone -b update-llama-cpp-b6653 https://github.com/AnacondaRecipes/llama.cpp-feedstock.git

    cd llama.cpp-feedstock

    echo -e '${BLUE}  → Repository information:${NC}'
    git log --oneline -3
    git branch -vv

    echo -e '${BLUE}  → Patches available:${NC}'
    ls -1 recipe/patches/

    echo -e '${GREEN}✓ Repository cloned successfully${NC}'
"
echo ""

# Step 6: Verify CUDA in container
echo -e "${GREEN}[6/9] Verifying CUDA inside Docker container...${NC}"
docker exec llama-cuda-build bash -c "
    nvidia-smi
    if [ \$? -ne 0 ]; then
        echo -e '${RED}ERROR: nvidia-smi failed inside container${NC}'
        exit 1
    fi
    echo -e '${GREEN}✓ CUDA accessible inside container${NC}'
"
echo ""

# Step 7: Run the CUDA build
echo -e "${GREEN}[7/9] Starting CUDA build (this will take 30-45 minutes)...${NC}"
echo -e "${YELLOW}Build progress will be shown below and logged to: cuda-linux-b6653.log${NC}"
echo ""

docker exec llama-cuda-build bash -c "
    set -e
    cd /io/llama.cpp-feedstock

    echo -e '${BLUE}════════════════════════════════════════${NC}'
    echo -e '${BLUE}  Starting conda build with CUDA support${NC}'
    echo -e '${BLUE}════════════════════════════════════════${NC}'
    echo -e '${BLUE}  Variants:${NC}'
    echo -e '${BLUE}    - output_set: llama${NC}'
    echo -e '${BLUE}    - gpu_variant: cuda-12${NC}'
    echo -e '${BLUE}    - cuda_compiler_version: 12.4${NC}'
    echo -e '${BLUE}════════════════════════════════════════${NC}'
    echo ''

    # Enable CUDA builds
    export ANACONDA_ROCKET_ENABLE_CUDA=1

    # Run the build with logging
    conda build --error-overlinking --croot=cr . \
        --variants '{output_set: llama, gpu_variant: cuda-12, cuda_compiler_version: 12.4}' \
        2>&1 | tee ./cuda-linux-b6653.log

    BUILD_EXIT_CODE=\${PIPESTATUS[0]}

    if [ \$BUILD_EXIT_CODE -eq 0 ]; then
        echo -e '${GREEN}✓ Build completed successfully!${NC}'
    else
        echo -e '${RED}✗ Build failed with exit code: \$BUILD_EXIT_CODE${NC}'
        exit \$BUILD_EXIT_CODE
    fi
"

BUILD_RESULT=$?
echo ""

# Step 8: Verify build artifacts
if [ $BUILD_RESULT -eq 0 ]; then
    echo -e "${GREEN}[8/9] Verifying build artifacts...${NC}"
    docker exec llama-cuda-build bash -c "
        cd /io/llama.cpp-feedstock

        echo -e '${BLUE}  → Log file:${NC}'
        ls -lh cuda-linux-b6653.log

        echo -e '${BLUE}  → Built packages:${NC}'
        if [ -d cr/linux-64 ]; then
            ls -lh cr/linux-64/*.tar.bz2 2>/dev/null || echo 'No .tar.bz2 packages found'
            ls -lh cr/linux-64/*.conda 2>/dev/null || echo 'No .conda packages found'
        else
            echo -e '${YELLOW}Warning: cr/linux-64 directory not found${NC}'
        fi

        echo ''
        echo -e '${BLUE}  → Build summary (last 100 lines):${NC}'
        tail -100 cuda-linux-b6653.log
    "
    echo -e "${GREEN}✓ Build artifacts verified${NC}"
    echo ""
else
    echo -e "${RED}[8/9] Build failed. Showing error context...${NC}"
    docker exec llama-cuda-build bash -c "
        cd /io/llama.cpp-feedstock
        if [ -f cuda-linux-b6653.log ]; then
            echo -e '${BLUE}  → Last 200 lines of build log:${NC}'
            tail -200 cuda-linux-b6653.log
        fi
    "
    echo ""
fi

# Step 9: Provide instructions for copying artifacts
echo -e "${GREEN}[9/9] Build process completed${NC}"
echo ""
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  Next Steps${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""
echo -e "The build log is located inside the container at:"
echo -e "  ${YELLOW}/io/llama.cpp-feedstock/cuda-linux-b6653.log${NC}"
echo ""
echo -e "On the host, it's at:"
echo -e "  ${YELLOW}~/llama-cuda-build/llama.cpp-feedstock/cuda-linux-b6653.log${NC}"
echo ""
echo -e "To copy the log to your local machine, run from your Mac:"
echo -e "  ${YELLOW}scp -i ~/.ssh/github_id_rsa ec2-user@<IP_ADDRESS>:~/llama-cuda-build/llama.cpp-feedstock/cuda-linux-b6653.log ~/Desktop/${NC}"
echo ""
echo -e "To copy built packages (optional):"
echo -e "  ${YELLOW}scp -i ~/.ssh/github_id_rsa -r ec2-user@<IP_ADDRESS>:~/llama-cuda-build/llama.cpp-feedstock/cr/linux-64/*.tar.bz2 ~/Desktop/cuda-packages/${NC}"
echo ""

if [ $BUILD_RESULT -eq 0 ]; then
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✓ BUILD SUCCESSFUL${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    exit 0
else
    echo -e "${RED}════════════════════════════════════════${NC}"
    echo -e "${RED}  ✗ BUILD FAILED${NC}"
    echo -e "${RED}════════════════════════════════════════${NC}"
    exit 1
fi
