# Copyright (c) 2020-2021, Bank of Canada
# All rights reserved.

module FAME

include("Types.jl")
include("ChliLibrary.jl")
include("Command.jl")
include("Databases.jl")
include("Objects.jl")
include("Read.jl")
include("Write.jl")
include("Bridge.jl")

export version
"""
    version()

Return the version of FAME in use.
"""
function version()
    version = Ref{Cfloat}(0.0)
    @cfm_call_check(cfmver, (Ref{Cfloat},), version)
    return VersionNumber(Base.string(version.x))
end

"""
    close_chli()

Finalize FAME and unload the CHLI library.
"""
function close_chli()
    if chli.lib !== nothing
        @cfm_call_check(cfmfin)
        Libdl.dlclose(chli.lib)
        global chli = Chli{FameDatabase}(nothing)
    end
    return
end

"""
    init_chli()

Load the CHLI library and initialize FAME. If it is already loaded, we first
close it and then load it fresh. See also [`close_chli`](@ref).
"""
function init_chli()
    close_chli()
    global chli = Chli()

    if chli.lib === nothing
        @warn "FAME not found."
        return
    end

    @cfm_call_check(cfmini)

    global FAME_INDEX_NC = @cfm_global(FAME_INDEX_NC, FameIndex)

    global FPRCNA = @cfm_global(FPRCNA, Cdouble)
    global FPRCNC = @cfm_global(FPRCNC, Cdouble)
    global FPRCND = @cfm_global(FPRCND, Cdouble)

    global FNUMNA = @cfm_global(FNUMNA, Cfloat)
    global FNUMNC = @cfm_global(FNUMNC, Cfloat)
    global FNUMND = @cfm_global(FNUMND, Cfloat)

    global FBOONA = @cfm_global(FBOONA, Cint)
    global FBOONC = @cfm_global(FBOONC, Cint)
    global FBOOND = @cfm_global(FBOOND, Cint)

    global FSTRNA = @cfm_global(FSTRNA, Cstring)
    global FSTRNC = @cfm_global(FSTRNC, Cstring)
    global FSTRND = @cfm_global(FSTRND, Cstring)

    return
end

function __init__()
    init_chli()
    atexit(close_chli)
end

end # module
