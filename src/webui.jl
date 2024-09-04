const WEBUI_ROOT_PATH = joinpath(@__DIR__, "..", "assets")
function handle_request(req::HTTP.Request)
    if req.method == "GET" && req.target == "/"
        return HTTP.Response(200, read(joinpath(WEBUI_ROOT_PATH, "index.html")))
    elseif req.method == "GET" && req.target == "/conversations"
        conversations = load_conversations()
        sorted_conversations = sort(conversations, :timestamp; rev=true)
        sorted_conversations_vec = [(;row...) for row in eachrow(sorted_conversations)]
        return HTTP.Response(200, JSON3.write(sorted_conversations_vec))
    elseif req.method == "GET" && req.target == "/models"
        all_models = unique(vcat(collect(keys(MODELS)),
                                 collect(keys(ALIASES))))
        sort!(all_models)
        return HTTP.Response(200, JSON3.write(all_models))
    elseif req.method == "POST" && req.target == "/new-conversation"
        conv_id = string(uuid4())
        create_conversation!(conv_id, (;
            title = "New Conversation",
            timestamp = now()
        ))
        return HTTP.Response(200, JSON3.write(Dict("id" => conv_id)))
    elseif req.method == "POST" && req.target == "/query"
        body = JSON3.read(req.body)
        prompt = body.prompt
        model = body.model
        conv_id = body.conversation_id
        extras = get(body, :extras, [])

        if nrow(load_conversation(conv_id)) == 0
            return HTTP.Response(400, "Invalid conversation ID")
        end

        response = process_new_prompt!(conv_id, model, prompt, extras)

        return HTTP.Response(200, JSON3.write(Dict(
            "response" => response,
            "conversation_id" => conv_id
        )))
    elseif req.method == "GET" && startswith(req.target, "/conversation/")
        conv_id = split(req.target, "/")[3]
        if nrow(load_conversation(conv_id)) == 0
            return HTTP.Response(404, "Conversation not found")
        end
        conv_msgs = load_messages(conv_id)
        conv_msgs_vec = [(;row...) for row in eachrow(conv_msgs)]
        return HTTP.Response(200, JSON3.write(conv_msgs_vec))
    else
        return HTTP.Response(404, "Not Found")
    end
end

const WEBUI_RUNNING = Ref(false)
const WEBUI_SERVER = Ref{HTTP.Server}()
function webui(; blocking::Bool=true, port::Int=8080, kwargs...)
    WEBUI_RUNNING[] && return
    WEBUI_RUNNING[] = true

    # Initialize DB
    init_db()

    # Start the server
    if blocking
        HTTP.serve(handle_request, "0.0.0.0", port; kwargs...)
    else
        WEBUI_SERVER[] = HTTP.serve!(handle_request, "0.0.0.0", port; kwargs...)
    end
    return
end
function webui(f::Function; kwargs...)
    was_running = WEBUI_RUNNING[]
    if was_running
        @warn "WebUI is already running, ignoring options"
        return f()
    else
        webui(; blocking=false, kwargs...)
        try
            return f()
        finally
            stop_webui()
        end
    end
end

function stop_webui()
    if WEBUI_RUNNING[]
        @assert isassigned(WEBUI_SERVER)
        close(WEBUI_SERVER[])
        WEBUI_RUNNING[] = false
    end
end
