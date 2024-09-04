module JLAIStudio

import PromptingTools as PT

import Dagger

import Graphs
import Graphs: SimpleDiGraph

import Sockets

import HTTP
import JSON3
import SQLite, DBInterface, Tables
import DBInterface: execute
import DataFrames: DataFrame, eachrow, nrow
import Dates: DateTime, Minute, now
import UUIDs: uuid4
import Base64: base64encode, base64decode

include("engine.jl")
include("resources.jl")
include("inference.jl")
include("training.jl")
include("model.jl")
include("agent.jl")
include("interface.jl")
include("workflow.jl")
include("db.jl")
include("webui.jl")

include("audio.jl")

function __init__()
    id_output = String(open(read, `id`))
    uid = match(r"uid=(\d+)", id_output).captures[1]
    RUNDIR[] = joinpath("/run/user", uid, "jlaistudio")
end

end # module JLAIStudio
