const RUNDIR = Ref("")

function run_inferencer(model, text; trainer_config = select_parallelization())
    mkpath(RUNDIR)
    socket_path = "pipe_" * tempname(RUNDIR)
    server = listen(socket_path)
    p = start_inferencer(trainer_config, model, socket_path)
    socket = accept(server)
    println(socket, string(length(text)))
    write(socket, text)
    response_len = parse(Int, readline(socket))
    response = String(read(socket, response_len))
    close(socket)
    wait(p)
end
function infer!(model_name::String, socket_path::String)
    socket = connect(socket_path)
    text_len = parse(Int, readline(socket))
    text = String(read(socket, text_len))

    scope = autodetect_scope()

    response = Dagger.with_options(;scope) do
        model = load_model(model_name)
        infer(model, text)
    end

    println(socket, string(length(response)))
    write(socket, response)
    close(socket)
end

function start_inferencer(model, socket_path)
    # FIXME: Instead, select just one GPU, or all threads
    config = select_parallelization()
    return start_inferencer(config, model, socket_path)
end
function start_inferencer(config::RunnerConfig, model, socket_path)
    c = Base.julia_cmd()
    push!(c.exec, "--startup-file=no")
    push!(c.exec, "--threads=$(config.num_threads)")
    push!(c.exec, "-e")
    for pkg in config.loaded_packages
        push!(c.exec, "using $pkg; ")
    end
    push!(c.exec, "using JLAIStudio; JLAIStudio.infer!(\"$model\", \"$socket_path\")")
    return run(c; wait=false)
end
