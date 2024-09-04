function load_git_repos()
    return DataFrame(execute(db[], "SELECT * FROM git_repos"))
end
function load_git_repo(repo_id)
    tbl = DataFrame(execute(db[], "SELECT * FROM git_repos WHERE id = ?", [repo_id]))
    nrow(tbl) == 0 && error("No Git repository found with ID $repo_id")
    return tbl
end
function load_git_repo_by_name(repo_name)
    tbl = DataFrame(execute(db[], "SELECT * FROM git_repos WHERE name = ?", [repo_name]))
    nrow(tbl) == 0 && error("No Git repository found with name $repo_name")
    return tbl
end

"""
    {{list_user_tools}}

Lists the tools available to the user by name.
"""
function list_user_tools()
    return join(sort(map(string, USER_TOOLS)), '\n')
end
"""
    {{list_assistant_tools}}

Lists the tools available to the AI assistant by name.
"""
function list_assistant_tools()
    return join(sort(map(string, ASSISTANT_TOOLS)), '\n')
end
"""
    {{want_system_response}}

Returns the assistant's latest response back to it with all tools expanded.
"""
want_system_response() = ""
"""
    {{git_repos_list}}

Lists all the Git repository names in the database.
"""
function git_repos_list()
    repos = load_git_repos()
    return join(repos.name, '\n')
end
"""
    {{git_repo_dump repo_name="MyRepo"}}

Returns a summary of the status and contents of a Git repository.
"""
git_repo_dump(repo_name::String) = git_repo_dump(; repo_name)
function git_repo_dump(; repo_name)
    repo = only(eachrow(load_git_repo_by_name(repo_name)))
    result = ""
    result *= "Repository name: " * repo.name * "\n"
    result *= "Repository path: " * repo.path * "\n"
    result *= "Current branch: " * git_current_branch(repo.path) * "\n"
    result *= "Repository contents:\n"
    result *= git_repo_contents(repo.path)
    return result
end
"""
    {{git_repo_contents repo_name="MyRepo"}}

Returns the contents of all files in a Git repository.
"""
git_repo_contents(repo_name::String) = git_repo_contents(; repo_name)
function git_repo_contents(; repo_name)
    result = ""
    for file in git_files(repo_name)
        result *= "Filename: $file\n"
        result *= "File contents:\n"
        result *= read(`git -C $(repo_path) show HEAD:$file`, String) * "\nEOF\n\n"
    end
    return result
end
"""
    {{git_commits repo_name="MyRepo"}}

Returns the list of commits in a Git repository on the current branch.
"""
git_commits(repo_name::String) = git_commits(; repo_name)
function git_commits(; repo_name)
    repo_path = only(load_git_repo_by_name(repo_name).path)
    return read(`git -C $(repo_path) log --pretty=format:"%H"`, String)
end
"""
    {{git_commit_show repo_name="MyRepo" commit_hash="abcdef"}}

Shows the diff of a commit in a Git repository.
"""
git_commit_show(repo_name::String, commit_hash::String) = git_commit_show(; repo_name, commit_hash)
function git_commit_show(; repo_name, commit_hash)
    repo_path = only(load_git_repo_by_name(repo_name).path)
    return read(`git -C $(repo_path) show $commit_hash`, String)
end
"""
    {{git_current_branch repo_name="MyRepo"}}

Returns the current branch of a Git repository.
"""
git_current_branch(repo_name::String) = git_current_branch(; repo_name)
function git_current_branch(; repo_name)
    repo_path = only(load_git_repo_by_name(repo_name).path)
    return read(`git -C $(repo_path) rev-parse --abbrev-ref HEAD`, String)
end
"""
    {{git_files repo_name="MyRepo"}}

Returns the list of files tracked in a Git repository.
"""
git_files(repo_name::String) = git_files(; repo_name)
function git_files(; repo_name)
    repo_path = only(load_git_repo_by_name(repo_name).path)
    return read(`git -C $(repo_path) ls-tree -r --name-only HEAD`, String)
end
"""
    {{git_file_contents repo_name="MyRepo" file_name="hello.jl"}}

Returns the contents of a file in a Git repository.
"""
function git_file_contents(; repo_name::String, file_name::String)
    repo_path = only(load_git_repo_by_name(repo_name).path)
    contents = read(`git -C $(repo_path) show HEAD:$file_name`, String)
    return code_prepend_line_numbers(contents)
end
"""
    {{git_propose_patch repo_name="MyRepo" message="Fix typo in hello.jl" <<<<
    --- a/hello.jl
    +++ b/hello.jl
    @@ -1 +1 @@
    -println("Hello World!")
    +println("Hello Bob!")
    >>>>}}

Proposes a patch to a Git repository, with the specified message and patch
contents. The user may choose to accept or reject the patch.
"""
function git_propose_patch(patch::String; repo_name::String, message::String)
    repo_path = only(load_git_repo_by_name(repo_name).path)

    @warn "AI proposing patch to $repo_name with message: $message\n$patch"
    print("Enter Y to accept the patch, else will reject: ")
    response = readline()
    if uppercase(response) != "Y"
        print("Reason: ")
        reason = readline()
        return "Patch rejected, reason: $reason"
    end

    patch_file = tempname() * ".patch"
    open(patch_file, "w") do io
        write(io, patch)
    end
    try
        # FIXME: Add to extras for later accept/reject
        run(`git -C $(repo_path) apply $patch_file`)
        msg = String(read(`git -C $(repo_path) commit -am $message`))
        return "Patch applied successfully:\n$msg"
    catch err
        return error_string("Failed to apply patch", err, catch_backtrace())
    finally
        rm(patch_file)
    end
end

leftpad(x, n, pad=" ") = pad^(n - length(string(x))) * string(x)
function code_prepend_line_numbers(code::String)
    code_lines = split(code, '\n')
    num_lines = length(code_lines)
    num_lines_dec = fld(num_lines, 10) + 1
    num_lines_dec = max(ceil(Int, log10(num_lines)), 1)
    return join(map(num_line->leftpad(string(num_line[1]), num_lines_dec) * ": " * num_line[2], enumerate(code_lines)), '\n')
end

function remove_utf8_surrogates(s::String)
    return String(collect(codepoint for codepoint in s if !is_surrogate(codepoint)))
end
function is_surrogate(c::Char)
    isvalid(c) || return true
    return 0xD800 <= UInt32(c) <= 0xDFFF
end

COMMON_TOOLS = [
    list_user_tools,
    want_system_response,
    git_repos_list,
    git_repo_dump,
    git_repo_contents,
    git_commits,
    git_commit_show,
    git_current_branch,
    git_files,
    git_file_contents,
    git_propose_patch,
]
USER_TOOLS = COMMON_TOOLS
ASSISTANT_TOOLS = COMMON_TOOLS

# Replace "{{mytool x=1 y=a}}" with the output of tools["mytool"](;x=1, y="a")
TOOL_REGEX = r"\{\{(\w+)(?:\s+([^{}]*?))?\}\}"
# Capture ("x", "1") and ("y", "abc") in "x=1 y=\"abc\"
TOOL_ARG_REGEX = r"(\w+)=(\"[^\"]*\"|[^ ]+)"
# Capture "Some stuff\nMore stuff" in "<<<<Some stuff\nMore stuff>>>>"
TOOL_MULTILINE_REGEX = r"<<<<([^<]+)>>>>"
function replace_tools(prompt::AbstractString, tools::Vector{Function}; inplace::Bool=true)
    out_prompt = ""
    while (m = match(TOOL_REGEX, prompt)) !== nothing
        tool_name = m.captures[1]
        tool_args = Dict{Symbol, Any}()
        tool_multiline_arg = ()
        try
            if !isnothing(m.captures[2])
                args_raw = m.captures[2]
                while (arg_m = match(TOOL_ARG_REGEX, args_raw)) !== nothing
                    key, value = arg_m.captures
                    key = Symbol(key)
                    value = Meta.parse(value)
                    tool_args[key] = value
                    args_raw = replace(args_raw, arg_m.match => ""; count=1)
                end
                if (multiline_m = match(TOOL_MULTILINE_REGEX, args_raw)) !== nothing
                    tool_multiline_arg = (String(lstrip(multiline_m.captures[1])),)
                end
            end
        catch err
            err_str = error_string("Failed to parse tool definition: $(m.match)", err, catch_backtrace())
            if inplace
                prompt = replace(prompt, m.match => "\n$err_str\n"; count=1)
            else
                prompt = replace(prompt, m.match => ""; count=1)
                out_prompt *= "Result of $(m.match):\n"
                out_prompt *= "$err_str\n"
            end
            continue
        end
        tool_idx = findfirst(f -> string(f) == tool_name, tools)
        if tool_idx === nothing
            err_str = error_string("Unknown tool: $tool_name")
            if inplace
                prompt = replace(prompt, m.match => "\n$err_str\n"; count=1)
            else
                prompt = replace(prompt, m.match => ""; count=1)
                out_prompt *= "Result of $(m.match):\n"
                out_prompt *= "$err_str\n"
            end
            continue
        end
        tool_fn = tools[tool_idx]
        tool_output = try
            tool_fn(tool_multiline_arg...; tool_args...)
        catch err
            err_str = error_string("Error running tool $tool_name", err, catch_backtrace())
            if inplace
                prompt = replace(prompt, m.match => "\n$err_str\n"; count=1)
            else
                prompt = replace(prompt, m.match => ""; count=1)
                out_prompt *= "Result of $(m.match):\n"
                out_prompt *= "$err_str\n"
            end
            continue
        end
        if inplace
            prompt = replace(prompt, m.match => tool_output; count=1)
        else
            prompt = replace(prompt, m.match => ""; count=1)
            out_prompt *= "Result of $(m.match):\n"
            out_prompt *= "$tool_output\n"
        end
    end
    return inplace ? prompt : out_prompt
end
function error_string(str, err=nothing, bt=nothing)
    iob = IOBuffer()
    print(iob, "ERROR: " * str)
    if err !== nothing
        println(iob)
        Base.showerror(iob, err)
        Base.show_backtrace(iob, bt)
    end
    seekstart(iob)
    return String(take!(iob))
end
function load_conversation_history(conv_id)
    history = ""
    for message in eachrow(load_messages(conv_id))
        history *= message_to_string(message)
    end
    return history
end
function message_to_string(message)
    output = ""
    if message.role == "user"
        output *= "User:" * "\n"
        output *= message.content * "\n"
    elseif message.role == "assistant"
        output *= "AI assistant:" * "\n"
        output *= message.content * "\n"
    elseif message.role == "system"
        output *= "System response:" * "\n"
        output *= message.content * "\n"
    else
        @warn "Ignoring unknown message role: $(message.role)"
    end
    if !isempty(message.extras)
        for extra in message.extras
            kind, content = extra
            if kind == "file"
                data, file_name = content
                output *= "File at path " * file_name * ":\n" * data * "\nEOF\n\n"
            elseif kind == "audio"
                output *= "Audio transcription:\n" * content * "\nEOF\n\n"
            else
                @warn "Ignoring unknown extra kind: $kind"
            end
        end
    end
    return output
end

function load_conversations()
    tbl = DataFrame(execute(db[], "SELECT * FROM conversations"))
    tbl.timestamp = DateTime.(tbl.timestamp)
    return tbl
end
function load_conversation(conv_id)
    tbl = DataFrame(execute(db[], "SELECT * FROM conversations WHERE id = ?", [conv_id]))
    tbl.timestamp = DateTime.(tbl.timestamp)
    return tbl
end
function create_conversation!(conv_id, conv_info)
    execute(db[], "INSERT INTO conversations VALUES (?, ?, ?)", [conv_id, conv_info.title, conv_info.timestamp])
end
function update_conversation!(conv_id, conv_info)
    execute(db[], "UPDATE conversations SET title = ?, timestamp = ? WHERE id = ?", [conv_info.title, conv_info.timestamp, conv_id])
end

function load_messages()
    tbl = DataFrame(execute(db[], "SELECT * FROM messages"))
    tbl.extras = [x isa String ? JSON3.read(x) : x for x in tbl.extras]
    return tbl
end
function load_messages(conv_id)
    tbl = DataFrame(execute(db[], "SELECT * FROM messages WHERE id = ?", [conv_id]))
    tbl.extras = [x isa String ? JSON3.read(x) : x for x in tbl.extras]
    return tbl
end
function num_messages(conv_id)
    return only(DataFrame(execute(db[], "SELECT COUNT(*) AS count FROM messages WHERE id = ?", [conv_id])).count)
end
function append_message!(conv_id, message_info)
    execute(db[], "INSERT INTO messages VALUES (?, ?, ?, ?)", [conv_id, message_info.role, message_info.content, JSON3.write(message_info.extras)])
end

function process_extra_content(extras)
    extras_out = []
    for extra in extras
        kind = extra.kind
        kind = lowercase(kind)
        content = extra.data
        @show kind
        if kind == "file"
            # Store content
            name = extra.fileName
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

function generate_llm_response(model_name::String, conv_id::String)
    full_prompt = "You are an AI assistant helping a user with a task.\n"
    full_prompt *= "To assist you in this endeavor, you have access to the following tools:\n"
    for tool_sym in sort(map(nameof, ASSISTANT_TOOLS))
        docstring = string(Base.Docs.doc(Base.Docs.Binding(@__MODULE__, tool_sym), Union{Tuple{}}))
        full_prompt *= docstring * "\n"
    end
    full_prompt *= "When you include a tool invocation like shown above, the tool will be seamlessly executed and the user will see the result. Alternatively, if you'd like to see the output of a tool without showing it to the user, you can use the {{want_system_response}} tool. Once you use this tool, you will be invoked again with conversation history that shows your previous message with all tools expanded, so that you can see their result. You can then use this information to assist with your next response to the user.\n"
    full_prompt *= "If working with Git repositories, please first make sure to load the repository list using the {{git_repos_list}} tool, then use the {{git_files}} tool to list the files in the repository, and the {{git_file_contents}} tool to view the contents of any files of interest.\n"
    #=
    full_prompt *= """Additionally, if you need to provide code to modify a Git repository, please provide it using the {{{propose_patch}}} tool, which can be used like so:
                      {{{propose_patch repo_name="JLAIStudio.jl#main"
                      --- a/hello.jl
                      +++ b/hello.jl
                      @@ -1 +1 @@
                      -println("Hello World!")
                      +println("Hello Bob!")
                      }}}
                      Which would propose a modification to the "JLAIStudio.jl#main" Git repository with the specified patch.
                      """
                      =#
    full_prompt *= "Now, the conversation history between you and the user follows:\n\n"
    full_prompt *= load_conversation_history(conv_id)
    full_prompt *= "\n"
    full_prompt *= "Given the above conversation history and the tools available to you, your goal is to respond to the user's latest prompt as helpfully as possible.\n"
    full_prompt = remove_utf8_surrogates(full_prompt)
    @debug "Full prompt:\n$full_prompt"
    agent = load_agent_background(model_name)
    return infer(agent, full_prompt)
end

function process_new_prompt!(conv_id, model, prompt, extras)
    # Process user tools
    prompt = replace_tools(prompt, USER_TOOLS)

    # Process extras
    extras = process_extra_content(extras)

    # Add prompt to the conversation
    append_message!(conv_id, (;
        role = "user",
        content = prompt,
        extras = extras
    ))

    @label generate_response

    # Generate assistant response
    response = generate_llm_response(model, conv_id)

    # Check if the assistant has requested a system response
    need_system_response = occursin("{{want_system_response}}", response)

    if need_system_response
        # Add raw response to the conversation
        append_message!(conv_id, (;
            role = "assistant",
            content = response,
            extras = []
        ))
    end

    # Process assistant tools
    response = replace_tools(response, ASSISTANT_TOOLS; inplace=!need_system_response)

    # Add processed response to the conversation
    append_message!(conv_id, (;
        role = need_system_response ? "system" : "assistant",
        content = response,
        extras = []
    ))

    # Return the response to the assistant if requested
    if need_system_response
        @goto generate_response
    end

    # Update conversation timestamp and title
    new_title = length(prompt) > 30 ? prompt[1:30] * "..." : prompt
    update_conversation!(conv_id, (;
        title = new_title,
        timestamp = now()
    ))

    return response
end

const db = Ref{SQLite.DB}()
function init_db()
    isassigned(db) && return

    db_path = joinpath(homedir(), ".local", "var", "jlaistudio", "conversations.db")
    mkpath(dirname(db_path))
    db[] = SQLite.DB(db_path)
    conversations_schema = Tables.Schema([:id, :title, :timestamp],
                                         [String, String, DateTime])
    messages_schema = Tables.Schema([:id, :role, :content, :extras],
                                    [String, String, String, Vector{String}])
    git_repos_schema = Tables.Schema([:id, :name, :path],
                                     [String, String, String])
    SQLite.createtable!(db[], "conversations", conversations_schema; ifnotexists=true)
    SQLite.createtable!(db[], "messages", messages_schema; ifnotexists=true)
    SQLite.createtable!(db[], "git_repos", git_repos_schema; ifnotexists=true)
end
