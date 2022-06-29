# Copyright (c) 2020-2021, Bank of Canada
# All rights reserved.

try    # ============================================

using LightXML

if !haskey(Base.ENV, "FAME")
    error("FAME environment variable is not set!")
end

# The CHLI help file containing the table of codes
help_file = joinpath(Base.ENV["FAME"], "help", "chli", "chli_status_codes.htm")
help_file = Base.Filesystem.realpath(help_file)

function do_row(el_tr)
    td_vals = map(content, get_elements_by_tagname(el_tr, "td"))
    @assert length(td_vals) == 3
    return (strip(td_vals[1]), parse(Int32, td_vals[2]), strip(td_vals[3]))
end

find_table(els::Array) = isempty(els) ? nothing : (z=filter(!isequal(nothing), find_table.(els)); length(z) == 0 ? nothing : length(z) == 1 ? z[1] : z)
find_table(el::XMLElement) = name(el) == "table" ? el : find_table( collect(child_elements(el)) )

# main loop
open("./FAMEMessages.jl", "w") do f
    println(f, "\n# This file is autogenerted.  Do not edit.")
    println(f, "\n\nchli_help_file = \"", escape_string(help_file), "\"")
    # Read and parse the help file
    xdoc = parse_file(help_file)
    table = find_table(root(xdoc))
    @assert table !== nothing && isa(table, XMLElement)
    table_rows = get_elements_by_tagname(table, "tr")
    table_rows = table_rows[2:end]
    # Print codes and messages to file
    println(f, "\nchli_status_description = Dict{Int32, String}(")
    for (hval, code, msg) in map(do_row, table_rows)
        println(f, "    $code => \"$msg\",")
    end
    println(f, ")\n\n")
    for (hval, code, msg) in map(do_row, table_rows)
        println(f, "const $hval = Int32($code)")
    end
    println(f)
end

catch e # ============================================
    @error "$(sprint(showerror, e))"
    isfile("./FAMEMessages.jl") && rm("./FAMEMessages.jl")
    # use a stub - these are the status codes we explicitly use in our code.
    open("./FAMEMessages.jl", "w") do f
        println(f, "\n# This file is autogenerted.  Do not edit.")
        println(f, "\n\nchli_help_file = ", "not found")
        println(f, "\nchli_status_description = Dict{Int32, String}(")
        println(f, "    0 => ", "Success.")
        println(f, "    13 => ", "The given object does not exist.") 
        println(f, "    67 => ", "Bad option.")
        println(f, ")\n\n")
        println(f, "global const HSUCC = Int32(0)")
        println(f, "global const HNOOBJ = Int32(13)")
        println(f, "global const HBOPT = Int32(67)")
        println(f)
    end
end
