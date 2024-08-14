abstract type Model end

# FIXME: Do this via DataToolkit or something
const MODELS = Dict{String,Model}()
const ALIASES = Dict{String,String}()

function load_model(model_name::String)
    if haskey(ALIASES, model_name)
        model_name = ALIASES[model_name]
    end
    return MODELS[model_name]
end

struct PTModel <: Model
    schema # TODO: Concrete-ish type
    name::String
end
function infer(model::PTModel, prompt::String; api_key::String)
    aimsg = PT.aigenerate(model.schema, prompt; model=model.name, api_key)
    return aimsg.content
end
for (alias, name) in PT.aliases
    # Register PT aliases
    ALIASES[alias] = name
end
for (name, spec) in PT.registry
    # Pre-load registered PT models
    MODELS[name] = PTModel(spec.schema, name)
end
