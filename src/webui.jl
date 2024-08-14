# Simulated conversations database
const conversations = DataFrame(id=String[], title=String[], timestamp=DateTime[])

# Simulated messages database
const messages = DataFrame(id=String[], role=String[], content=String[], extras=Vector{Any}[])

# Simulated LLM function (replace with actual LLM integration)
function generate_llm_response(model_name::String, conv_id::String)
    agent = load_agent_background(model_name)
    full_prompt = "You are an AI assistant helping a user with a task. The user has provided the following conversation history:\n\n"
    for message in eachrow(messages[messages.id .== conv_id, :])
        if message.role == "user"
            full_prompt *= "User:" * "\n"
            full_prompt *= message.content * "\n"
        else
            full_prompt *= "AI assistant:" * "\n"
            full_prompt *= message.content * "\n"
        end
        if !isempty(message.extras)
            for extra in message.extras
                kind, content = extra
                if kind == "file"
                    data, metadata = content
                    full_prompt *= "File at path " * metadata * ":\n" * data * "\nEOF\n\n"
                elseif kind == "audio"
                    full_prompt *= "Audio transcription:\n" * content * "\nEOF\n\n"
                else
                    @warn "Ignoring unknown extra kind: $kind"
                end
            end
        end
    end
    full_prompt *= "Given the above conversation history, respond to the user's latest prompt."
    println("Full prompt:")
    println(full_prompt)
    return infer(agent, full_prompt)
end
function process_extra_content(extras)
    extras_out = []
    for extra in extras
        kind = extra.kind
        content = extra.content
        @show kind
        if kind == "file"
            # Store content
            name = extra.metadata.name
            push!(extras_out, "file" => [name, content])
        elseif kind == "audio"
            # Decode into file
            path = tempname() * ".ogg"
            open(path, "w") do io
                write(io, base64decode(content))
            end
            text = speech_to_text(path) # TODO: Allow specifying model and prompt
            rm(path)
            push!(extras_out, "audio" => text)
        else
            @warn "Ignoring unknown extra kind: $kind"
        end
    end
    return extras_out
end

function create_conversation!(conv_id, conv_info)
    push!(conversations, (;id=conv_id, Base.pairs(conv_info)...))
    tbl = conversations[conversations.id .== conv_id, :]
    SQLite.load!(tbl, db[], "conversations")
end
function append_message!(conv_id, message_info)
    push!(messages, (;id=conv_id, Base.pairs(message_info)...))
    tbl = messages[messages.id .== conv_id, :]
    SQLite.load!(tbl, db[], "messages")
end
function update_conversation!(conv_id)
    conv = first(eachrow(conversations[conversations.id .== conv_id, :]))
    execute(db[], "UPDATE conversations SET title = ?, timestamp = ? WHERE id = ?", [conv.title, conv.timestamp, conv_id])
end

const WEBUI_ROOT_PATH = joinpath(@__DIR__, "..", "assets")
function handle_request(req::HTTP.Request)
    if req.method == "GET" && req.target == "/"
        return HTTP.Response(200, read(joinpath(WEBUI_ROOT_PATH, "index.html")))
    elseif req.method == "GET" && req.target == "/conversations"
        #sorted_conversations = sort(collect(values(conversations)), by = c -> c["timestamp"], rev = true)
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
        create_conversation!(conv_id, Dict(
            :title => "New Conversation",
            :timestamp => now()
        ))
        return HTTP.Response(200, JSON3.write(Dict("id" => conv_id)))
    elseif req.method == "POST" && req.target == "/query"
        body = JSON3.read(req.body)
        prompt = get(body, :prompt, "")
        model = get(body, :model, "default")
        conv_id = get(body, :conversation_id, "")
        extras = get(body, :extras, [])

        if nrow(conversations[conversations.id .== conv_id, :]) == 0
            return HTTP.Response(400, "Invalid conversation ID")
        end

        # Process extras
        extras = process_extra_content(extras)

        # Add prompt to the conversation
        append_message!(conv_id, Dict(:role => "user",
                                      :content => prompt,
                                      :extras => extras))

        response = generate_llm_response(model, conv_id)

        # Add response to the conversation
        append_message!(conv_id, Dict(:role => "assistant",
                                      :content => response,
                                      :extras => []))

        # Update conversation timestamp and title
        conversations[conversations.id .== conv_id, :timestamp] .= now()
        new_title = length(prompt) > 30 ? prompt[1:30] * "..." : prompt
        conversations[conversations.id .== conv_id, :title] .= new_title
        update_conversation!(conv_id)

        return HTTP.Response(200, JSON3.write(Dict(
            "response" => response,
            "conversation_id" => conv_id
        )))
    elseif req.method == "GET" && startswith(req.target, "/conversation/")
        conv_id = split(req.target, "/")[3]
        if nrow(messages[messages.id .== conv_id, :]) == 0
            return HTTP.Response(404, "Conversation not found")
        end
        conv_msgs = messages[messages.id .== conv_id, :]
        conv_msgs_vec = [(;row...) for row in eachrow(conv_msgs)]
        return HTTP.Response(200, JSON3.write(conv_msgs_vec))
    else
        return HTTP.Response(404, "Not Found")
    end
end

const db = Ref{SQLite.DB}()

function webui()
    # Initialize DB
    db_path = joinpath(homedir(), ".local", "var", "jlaistudio", "conversations.db")
    mkpath(dirname(db_path))
    db[] = SQLite.DB(db_path)
    conversations_schema = Tables.Schema([:id, :title, :timestamp],
                                         [String, String, DateTime])
    messages_schema = Tables.Schema([:id, :role, :content, :extras],
                                    [String, String, String, Vector{String}])
    SQLite.createtable!(db[], "conversations", conversations_schema; ifnotexists=true)
    SQLite.createtable!(db[], "messages", messages_schema; ifnotexists=true)

    # Load conversations and messages
    empty!(conversations)
    convs = DataFrame(execute(db[], "SELECT * FROM conversations"))
    convs.timestamp = DateTime.(convs.timestamp)
    append!(conversations, convs)
    empty!(messages)
    append!(messages, execute(db[], "SELECT * FROM messages"))

    # Start the server
    port = 8080
    HTTP.serve(handle_request, "0.0.0.0", port)
    println("Server running on http://localhost:$port/")
end
