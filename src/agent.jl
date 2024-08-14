abstract type Agent end

const BACKGROUND_AGENT = Ref{Union{Agent,Nothing}}(nothing)
const BACKGROUND_MODEL_NAME = Ref("")

function load_agent_background(model_name::String)
    if model_name != BACKGROUND_MODEL_NAME[]
        agent = create_agent(model_name)
        BACKGROUND_AGENT[] = agent
        BACKGROUND_MODEL_NAME[] = model_name
    end
    return BACKGROUND_AGENT[]
end

# FIXME: Automate this
load_api_key(model_name::String) = load_api_key(load_model(model_name))
load_api_key(model::PTModel) = load_api_key(model.schema)
load_api_key(::PT.OpenAISchema) = PT.OPENAI_API_KEY
load_api_key(::PT.AnthropicSchema) = PT.ANTHROPIC_API_KEY
load_api_key(::PT.GroqOpenAISchema) = PT.GROQ_API_KEY

struct PTAgent <: Agent
    model::PTModel
    api_key::Union{String,Nothing}
end
function create_agent(model_name::String)
    # FIXME: Don't hardcode PT here
    model = load_model(model_name)::PTModel
    return PTAgent(model, nothing)
end
function infer(agent::PTAgent, prompt::String)
    if agent.api_key === nothing
        api_key = load_api_key(agent.model)
    else
        api_key = agent.api_key
    end
    return infer(agent.model, prompt; api_key)
end

# TODO: Llama2Agent
