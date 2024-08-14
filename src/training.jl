"Trains `model` on `data` automatically, using whatever hardware resources are available."
function run_trainer(model, data; trainer_config = select_parallelization())
    p = start_trainer(trainer_config, model, data)
    # TODO: Do something useful with p
    wait(p)
end
function train!(model_name::String, data_name::String)
    all_data = load_data(data_name)

    # FIXME: Construct Dagger scope
    all_procs = Dagger.all_processors()
    thread_procs = filter(p -> p isa Dagger.ThreadProc, all_procs)
    gpu_procs = filter(p -> !(p isa Dagger.ThreadProc), all_procs)
    if !isempty(gpu_procs)
        scope = Dagger.UnionScope([Dagger.ExactScope(proc) for proc in gpu_procs])
    else
        scope = Dagger.scope(threads=:)
    end

    Dagger.spmd(n_ranks, scope, Ref(model_name), all_data) do model_name, data
        model = load_model(model_name)
        niters = 100 # FIXME: Make this configurable
        rank = Dagger.spmd_rank()
        print("[$rank] Starting training\n")
        for iter in 1:niters
            print("[$rank] Iteration $iter\n")
            gs = Flux.gradient(model, data)
            gs = Dagger.spmd_reduce(+, gs)
            gs ./= Dagger.spmd_size()
        end
        print("[$rank] Finished training\n")
        if rank == 1
            # FIXME: Save model
        end
    end
end

function start_trainer(model, data)
    config = select_parallelization()
    return start_trainer(config, model, data)
end
function start_trainer(config::RunnerConfig, model, data)
    c = Base.julia_cmd()
    push!(c.exec, "--startup-file=no")
    push!(c.exec, "--threads=$(config.num_threads)")
    push!(c.exec, "-e")
    for pkg in config.loaded_packages
        push!(c.exec, "using $pkg; ")
    end
    push!(c.exec, "using JLAIStudio; JLAIStudio.train!(\"$model\", \"$data\")")
    return run(c; wait=false)
end
