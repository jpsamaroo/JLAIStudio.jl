using REPL: TerminalMenus

function readlineui_main()
    @label select_model
    print("Select a model (Ctrl-C to quit): ")
    model = readline()
    if isempty(model)
        model = "claudeh"
    end
    println("Selected model: $model")

    @label select_conv
    convs = reverse(load_conversations())
    options = convs.title
    menu = TerminalMenus.RadioMenu(options)
    response = try
        TerminalMenus.request("Select a conversation (Ctrl-C to quit):", menu)
    catch err
        if err isa InterruptException
            return
        end
        rethrow(err)
    end
    if response != -1
        conv_id = convs.id[response]
    else
        conv_id = string(uuid4())
        create_conversation!(conv_id, (;
            title = "New Conversation",
            timestamp = now()
        ))
    end
    println("Selected conversation: $conv_id")

    @label load_history
    history = load_conversation_history(conv_id)
    println("Conversation History:")
    println(history)

    @label get_prompt
    println("Enter a message (Ctrl-C to quit):")
    prompt = try
        readline()
    catch err
        if err isa InterruptException
            return
        end
        rethrow(err)
    end
    if isempty(prompt)
        @goto get_prompt
    end
    last_msg_idx = num_messages(conv_id)
    process_new_prompt!(conv_id, model, prompt, [])
    println()
    msgs = load_messages(conv_id)
    for idx in (last_msg_idx+2):num_messages(conv_id)
        msg = msgs[idx, :]
        println(message_to_string(msg))
    end
    println()

    @goto get_prompt
end
function readlineui(; kwargs...)
    init_db()
    readlineui_main()
end
