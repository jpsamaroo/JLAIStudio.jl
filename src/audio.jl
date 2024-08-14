# Borrowed from ProToPortal.jl (license is MIT)

"Calls a Whisper-compatible API to transcribe audio"
function create_transcription(
        file; url::String, api_key::String, model::String, prompt::String = "")
    ## TODO: upstream to OpenAI.jl
    headers = ["Authorization" => "Bearer $(api_key)"]
    f = open(file)
    data = Dict("file" => f, "model" => model)
    if !isempty(prompt)
        ## Providing a prompt can significantly enhanced the transcription quality (especially spelling)
        data["prompt"] = prompt
        length(prompt) > 30 &&
            @warn "Prompts longer than 30 characters can cause errors in some Whisper APIs!"
    end
    form = HTTP.Forms.Form(data)
    response = HTTP.post(url, headers, form; status_exception = false)
    transcription = response.status == 200 ? JSON3.read(response.body)["text"] :
                    "ERROR: " * JSON3.read(response.body)[:error][:message]
    close(f)
    return transcription
end

# FIXME: Don't do this
MODELS["whisper-1"] = PTModel(PT.OpenAISchema(), "whisper-1")
MODELS["whisper-large-v3"] = PTModel(PT.GroqOpenAISchema(), "whisper-large-v3")

"Calls a Whisper-compatible API to transcribe audio - dispatches on the right API based on the model name."
function speech_to_text(file; model::String = "whisper-1", prompt::String = "")
    ## TODO: implement native model registration and schema-based dispatch
    if model == "whisper-1"
        url = "https://api.openai.com/v1/audio/transcriptions"
        api_key = load_api_key("whisper-1")
    elseif model == "whisper-large-v3"
        url = "https://api.groq.com/openai/v1/audio/transcriptions"
        api_key = load_api_key("whisper-large-v3")
    else
        throw(ArgumentError("Invalid model: $(model)"))
    end
    return create_transcription(file; url, api_key, model, prompt)
end
