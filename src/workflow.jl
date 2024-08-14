struct AgentWorkflow
    graph::SimpleDiGraph{Int}
    execs::Dict{Int, Union{Agent, TextInterface}}
end
function run!(workflow::AgentWorkflow)
    # FIXME: Execute in topological order
end
