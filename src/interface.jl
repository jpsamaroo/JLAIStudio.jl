abstract type TextInterface end

generator(::TextInterface) = false
consumer(::TextInterface) = false

struct TextFileInterface <: TextInterface
    path::String
end
generator(::TextFileInterface) = true
initialize(iface::TextFileInterface) = open(iface.path, "r")
function generate!(iface::TextFileInterface, state::IOStream)
    return read(state)
end

struct ReadlineInterface <: TextInterface
    prompt::String
end
generator(::ReadlineInterface) = true
initialize(::ReadlineInterface) = nothing
function generate!(iface::ReadlineInterface, state)
    return readline(prompt)
end
