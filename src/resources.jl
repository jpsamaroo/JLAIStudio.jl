Base.@kwdef struct RunnerConfig
    num_threads::Int = 1
    loaded_packages::Vector{Symbol} = Symbol[]
end
function select_parallelization()
    res = known_resources()
    if res.num_gpus > 0
        if res.num_cuda_gpus > 0
            # Use CUDA
            num_threads = min(res.num_threads, res.num_cuda_gpus)
            return RunnerConfig(;num_threads, loaded_packages = [:CUDA])
        elseif res.num_rocm_gpus > 0
            # Use ROCM
            num_threads = min(res.num_threads, res.num_rocm_gpus)
            return RunnerConfig(;num_threads, loaded_packages = [:AMDGPU])
        elseif res.num_metal_gpus > 0
            # Use Metal
            num_threads = min(res.num_threads, res.num_metal_gpus)
            return RunnerConfig(;num_threads, loaded_packages = [:Metal])
        elseif res.num_intel_gpus > 0
            # Use oneAPI
            num_threads = min(res.num_threads, res.num_intel_gpus)
            return RunnerConfig(;num_threads, loaded_packages = [:oneAPI])
        else
            error("Expected a specific vendor GPU to be available")
        end
    else
        # Use CPUs
        return RunnerConfig(;num_threads = res.num_cpus)
    end
end
function autodetect_scope()
    # Construct Dagger scope from loaded processors
    all_procs = Dagger.all_processors()
    gpu_procs = filter(p -> !(p isa Dagger.ThreadProc), all_procs)
    if !isempty(gpu_procs)
        return Dagger.UnionScope([Dagger.ExactScope(proc) for proc in gpu_procs])
    else
        return Dagger.scope(threads=:)
    end
end

# TODO: Calculate this path in __init__
const RESOURCE_PATH = joinpath(homedir(), ".config", "jlaistudio", "resources.toml")
function detect_resources!()
    c = Base.julia_cmd()
    push!(c.exec, "--startup-file=no")
    append!(c.exec, ["-e", "'using JLAIStudio; JLAIStudio._detect_resources!()'"])
    run(c)
end
function _detect_resources!()
    # Check number of CPUs
    num_cpus = Sys.CPU_THREADS

    # Try to load GPU packages and detect GPUs
    try
        @eval using CUDA
    catch
    end
    num_cuda_gpus = CUDA.functional() ? length(CUDA.devices()) : 0

    try
        @eval using AMDGPU
    catch
    end
    num_rocm_gpus = AMDGPU.functional() ? length(AMDGPU.devices()) : 0

    try
        @eval using Metal
    catch
    end
    num_metal_gpus = Metal.functional() ? length(Metal.devices()) : 0

    try
        @eval using oneAPI
    catch
    end
    num_intel_gpus = oneAPI.functional() ? length(oneAPI.devices()) : 0

    num_gpus = num_cuda_gpus + num_rocm_gpus + num_metal_gpus + num_intel_gpus

    res = (;num_cpus, num_cuda_gpus, num_rocm_gpus, num_metal_gpus, num_intel_gpus, num_gpus)

    # Record available resources
    TOML.write(resource_path, Dict("resources" => res))
end
function known_resources(; force = false)
    if force || !isfile(resource_path)
        # Detect available resources
        detect_resources!()
    end
    return TOML.parse(resource_path)["resources"]
end
