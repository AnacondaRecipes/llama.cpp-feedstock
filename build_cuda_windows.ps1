# Automated CUDA Build Script for Windows EC2 Instance (llama.cpp b6653)
# This script should be run on a g4dn.4xlarge instance with CUDA support
# Run in PowerShell: .\build_cuda_windows.ps1

$ErrorActionPreference = "Stop"  # Exit on any error

# Function to print colored messages
function Write-Step {
    param($Message, $Color = "Cyan")
    Write-Host "`n[$($script:StepCounter)/$($script:TotalSteps)] $Message" -ForegroundColor $Color
    $script:StepCounter++
}

function Write-Success {
    param($Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Error-Message {
    param($Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Write-Info {
    param($Message)
    Write-Host "  → $Message" -ForegroundColor Blue
}

# Initialize counters
$script:StepCounter = 1
$script:TotalSteps = 10

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  llama.cpp CUDA Build - Windows" -ForegroundColor Cyan
Write-Host "  Version: b6653" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Step 1: Initialize conda
Write-Step "Initializing conda environment..." "Cyan"
try {
    & 'C:\miniconda3\shell\condabin\conda-hook.ps1'
    Write-Success "Conda initialized"

    Write-Info "Conda information:"
    conda info --envs
} catch {
    Write-Error-Message "Failed to initialize conda: $_"
    exit 1
}

# Step 2: Navigate to home directory
Write-Step "Setting up working directory..." "Cyan"
Set-Location ~
$workDir = Join-Path $HOME "llama-cuda-build"
if (-not (Test-Path $workDir)) {
    New-Item -ItemType Directory -Path $workDir | Out-Null
}
Set-Location $workDir
Write-Success "Working directory: $(Get-Location)"

# Step 3: Install CUDA driver
Write-Step "Installing CUDA driver (this may take 10-15 minutes)..." "Cyan"
Write-Info "Running CUDA driver installation script..."
try {
    if (Test-Path 'C:\prefect\install_cuda_driver.ps1') {
        powershell -ExecutionPolicy ByPass -File 'C:\prefect\install_cuda_driver.ps1'
        Write-Success "CUDA driver installed"
    } else {
        Write-Host "  ⚠ CUDA driver script not found, assuming already installed" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ⚠ CUDA driver installation failed or already installed: $_" -ForegroundColor Yellow
}

# Step 4: Install CUDA toolkit
Write-Step "Installing CUDA toolkit 12.3.0 (this may take 10-15 minutes)..." "Cyan"
Write-Info "Running CUDA toolkit installation script..."
try {
    if (Test-Path 'C:\prefect\install_cuda_12.3.0.ps1') {
        powershell -ExecutionPolicy ByPass -File 'C:\prefect\install_cuda_12.3.0.ps1'
        Write-Success "CUDA toolkit 12.3.0 installed"
    } else {
        Write-Host "  ⚠ CUDA toolkit script not found, assuming already installed" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ⚠ CUDA toolkit installation failed or already installed: $_" -ForegroundColor Yellow
}

# Step 5: Verify CUDA installation
Write-Step "Verifying CUDA installation..." "Cyan"
try {
    nvidia-smi
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Message "nvidia-smi failed. CUDA may not be properly configured."
        exit 1
    }
    Write-Success "CUDA is available"
} catch {
    Write-Error-Message "nvidia-smi not found. This instance may not have NVIDIA GPU support."
    exit 1
}

# Step 6: Create checkout environment
Write-Step "Creating conda checkout environment..." "Cyan"
Write-Info "Installing git and curl..."
try {
    conda create -n checkout -y curl git 2>&1 | Out-Null
    Write-Success "Checkout environment created"
} catch {
    Write-Host "  ⚠ Checkout environment may already exist: $_" -ForegroundColor Yellow
}

# Step 7: Download aggregate config and clone repository
Write-Step "Downloading aggregate config and cloning repository..." "Cyan"
try {
    conda activate checkout

    Write-Info "Downloading conda_build_config.yaml..."
    if (Test-Path "conda_build_config.yaml") {
        Remove-Item "conda_build_config.yaml" -Force
    }
    & curl.exe -O https://raw.githubusercontent.com/AnacondaRecipes/aggregate/master/conda_build_config.yaml

    Write-Info "Cloning llama.cpp-feedstock (branch: update-llama-cpp-b6653)..."
    if (Test-Path "llama.cpp-feedstock") {
        Write-Host "    Repository directory exists, removing..." -ForegroundColor Yellow
        Remove-Item -Recurse -Force "llama.cpp-feedstock"
    }

    git clone -b update-llama-cpp-b6653 https://github.com/AnacondaRecipes/llama.cpp-feedstock.git

    Set-Location llama.cpp-feedstock

    Write-Info "Repository information:"
    git log --oneline -3
    git branch -vv

    Write-Info "Available patches:"
    Get-ChildItem recipe\patches\ -Name

    Write-Success "Repository cloned successfully"

    conda deactivate
} catch {
    Write-Error-Message "Failed to clone repository: $_"
    exit 1
}

# Step 8: Create build environment
Write-Step "Creating conda build environment..." "Cyan"
try {
    conda create -n build -y conda-build 2>&1 | Out-Null
    Write-Success "Build environment created"
} catch {
    Write-Host "  ⚠ Build environment may already exist: $_" -ForegroundColor Yellow
}

# Step 9: Run CUDA build
Write-Step "Starting CUDA build (this will take 60-90 minutes)..." "Cyan"
Write-Host "`nBuild progress will be shown below and logged to: cuda-windows-b6653.log`n" -ForegroundColor Yellow

Write-Host "========================================" -ForegroundColor Blue
Write-Host "  Starting conda build with CUDA support" -ForegroundColor Blue
Write-Host "========================================" -ForegroundColor Blue
Write-Host "  Variants:" -ForegroundColor Blue
Write-Host "    - output_set: llama" -ForegroundColor Blue
Write-Host "    - gpu_variant: cuda-12" -ForegroundColor Blue
Write-Host "    - cuda_compiler_version: 12.4" -ForegroundColor Blue
Write-Host "    - blas_impl: cublas" -ForegroundColor Blue
Write-Host "========================================`n" -ForegroundColor Blue

try {
    conda activate build

    # Enable CUDA builds
    $env:ANACONDA_ROCKET_ENABLE_CUDA = "1"
    Write-Info "ANACONDA_ROCKET_ENABLE_CUDA = $env:ANACONDA_ROCKET_ENABLE_CUDA"

    # Get parent directory for conda_build_config.yaml
    $parentConfigPath = Join-Path (Get-Location).Path "..\conda_build_config.yaml"

    # Run the build
    $buildStartTime = Get-Date

    conda build --error-overlinking --croot=cr -m $parentConfigPath . `
        --variants "{output_set: llama, gpu_variant: cuda-12, cuda_compiler_version: 12.4, blas_impl: cublas}" `
        2>&1 | Tee-Object -FilePath ".\cuda-windows-b6653.log"

    $buildEndTime = Get-Date
    $buildDuration = $buildEndTime - $buildStartTime

    if ($LASTEXITCODE -eq 0) {
        Write-Success "Build completed successfully in $($buildDuration.ToString('hh\:mm\:ss'))!"
        $buildSuccess = $true
    } else {
        Write-Error-Message "Build failed with exit code $LASTEXITCODE after $($buildDuration.ToString('hh\:mm\:ss'))"
        $buildSuccess = $false
    }

    conda deactivate
} catch {
    Write-Error-Message "Build process failed: $_"
    $buildSuccess = $false
}

# Step 10: Verify and summarize
Write-Step "Build process completed - Generating summary..." "Cyan"

if (Test-Path "cuda-windows-b6653.log") {
    $logSize = (Get-Item "cuda-windows-b6653.log").length / 1MB
    Write-Info "Log file: cuda-windows-b6653.log ($([math]::Round($logSize, 2)) MB)"

    Write-Info "Built packages:"
    if (Test-Path "cr\win-64") {
        Get-ChildItem "cr\win-64\*.tar.bz2" -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host "    - $($_.Name)" -ForegroundColor Gray
        }
        Get-ChildItem "cr\win-64\*.conda" -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host "    - $($_.Name)" -ForegroundColor Gray
        }
    } else {
        Write-Host "    ⚠ cr\win-64 directory not found" -ForegroundColor Yellow
    }

    Write-Host "`n  Build Summary (last 100 lines):" -ForegroundColor Blue
    Write-Host "  ────────────────────────────────────────" -ForegroundColor Blue
    Get-Content "cuda-windows-b6653.log" -Tail 100
} else {
    Write-Error-Message "Log file not found!"
}

# Final instructions
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Next Steps" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "The build log is located at:" -ForegroundColor White
Write-Host "  $(Join-Path (Get-Location).Path "cuda-windows-b6653.log")" -ForegroundColor Yellow
Write-Host ""
Write-Host "To copy the log to your local machine, run from your Mac:" -ForegroundColor White
$currentPath = (Get-Location).Path -replace '\\', '/'
$currentPath = $currentPath -replace '^C:', '/c'
Write-Host "  scp -i ~/.ssh/github_id_rsa dev-admin@<IP_ADDRESS>:$currentPath/cuda-windows-b6653.log ~/Desktop/" -ForegroundColor Yellow
Write-Host ""
Write-Host "Alternatively (if above doesn't work):" -ForegroundColor White
Write-Host "  scp -i ~/.ssh/github_id_rsa dev-admin@<IP_ADDRESS>:/Users/dev-admin/llama-cuda-build/llama.cpp-feedstock/cuda-windows-b6653.log ~/Desktop/" -ForegroundColor Yellow
Write-Host ""
Write-Host "To copy built packages (optional):" -ForegroundColor White
Write-Host "  scp -i ~/.ssh/github_id_rsa dev-admin@<IP_ADDRESS>:$currentPath/cr/win-64/*.tar.bz2 ~/Desktop/cuda-packages/" -ForegroundColor Yellow
Write-Host ""

if ($buildSuccess) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  ✓ BUILD SUCCESSFUL" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    exit 0
} else {
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  ✗ BUILD FAILED" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Check the log file for details: cuda-windows-b6653.log" -ForegroundColor Yellow
    exit 1
}
