# Copyright (c) 2020-2021, Bank of Canada
# All rights reserved.

# __precompile__(false)

# CHLI library: load and bindings

using Libdl

###  check_status

export check_status

try
    include("../deps/FAMEMessages.jl")
catch
    @error "Try re-building FAME"
end

struct HLIError <: Exception
    status::Int32
    msg::String
end
HLIError(st::Int32) = HLIError(st, 
    st == 513 ? cfmferr() : get(chli_status_description, st, "Unknown CHLI error."))
Base.showerror(io::IO, e::HLIError) = print(io, "HLI status($(e.status)): $(e.msg)")


"""
    check_status(status)

Check the status code returned by cfmXYZ functions. If status indicates success
we do nothing, otherwise we trigger an HLIError with the error code and message.
"""
@inline check_status(status::Ref{Int32}) = check_status(status[])
@inline function check_status(code::Int32)
    code == HSUCC && return
    throw(HLIError(code))
end

function Chli()
    if !haskey(Base.ENV, "FAME")
        @error "FAME environment variable is not set! Will not be able to use FAME."
        return Chli{AbstractFameDatabase}(nothing)
    end
    if Sys.iswindows()
        # we need only the basename of the .dll; Windows automatically 
        # decorates it with extension and finds it on the PATH
        chli_lib_path = "chli"
        # ensure  chli.dll file is on the PATH so Windows can find it
        if Sys.ARCH == :x86_64
            Base.ENV["PATH"] *= ";" * Base.ENV["FAME"] * "\\64"
        else
            Base.ENV["PATH"] *= ";" * Base.ENV["FAME"]
        end
    elseif Sys.islinux()
        # in Linux libchli.so is located in a subdirectory hli
        # we need to specify the full path to the .so file 
        if Sys.ARCH == :x86_64
            chli_lib_path = joinpath(Base.ENV["FAME"], "hli", "64", "libchli.so")
        else
            chli_lib_path = joinpath(Base.ENV["FAME"], "hli", "libchli.so")
        end
    else
        @error "Your OS is not supported. Will not be able to use FAME."
        return Chli{AbstractFameDatabase}(nothing)
    end
    try
        return Chli{FameDatabase}(Libdl.dlopen(chli_lib_path), FameDatabase[], Ref(FameDatabase(-1)))
    catch
        @error "Failed to load CHLI library! Will not be able to use FAME."
        return Chli{AbstractFameDatabase}(nothing)
    end
end


"""
    @cfm_global(:cfmXYZ, type)

Fetch the value of a constant by the given name from the CHLI library.

See also: [`@cfm_call_check`](@ref)
"""
macro cfm_global(symbol, type)
    sym = :($(@__MODULE__).getsym($(QuoteNode(symbol))))
    call_expr = Expr(:call, :cglobal, sym, type)
    return esc(:(unsafe_load($call_expr)))
end

"""
    @fame_call(:fame_XYZ, argTypes, args...)

Build an appropriate ccall to the given fame_XYZ function. 

See also: [`@cfm_call_check`](@ref)
"""
macro fame_call(symbol, argTypes, args...)
    sym = :($(@__MODULE__).getsym($(QuoteNode(symbol))))
    call_expr = Expr(:call, :ccall, sym, :Cint, argTypes, args...)
    return esc(:($call_expr))
end


"""
    @fame_call_check(:fame_XYZ, argTypes, args...)

Build an appropriate ccall to the given fame_XYZ function. This macro also
checks the status and throws an error if not success.

See also: [`@cfm_call_check`](@ref)
"""
macro fame_call_check(symbol, argTypes, args...)
    sym = :($(@__MODULE__).getsym($(QuoteNode(symbol))))
    call_expr = Expr(:call, :ccall, sym, :Cint, argTypes, args...)
    return esc(:(check_status($call_expr)))
end

"""
    @cfm_call(:cfmXYZ, argTypes, args...)

Build an appropriate ccall to the given cfmXYZ function. When using this macro,
include the status variable and check it yourself.

See also: [`@cfm_call_check`](@ref)
"""
macro cfm_call(symbol, argTypes, args...)
    sym = :($(@__MODULE__).getsym($(QuoteNode(symbol))))
    call_expr = Expr(:call, :ccall, sym, :Cvoid, argTypes, args...)
    return esc(:($call_expr))
end

"""
    @cfm_call_check(:cfmXYZ, argTypes, args...)

Call the cfm function and check status. When using this macro, do not include
the status variable.

See also: [`@cfm_call`](@ref)
"""
macro cfm_call_check(symbol)
    sym = :($(@__MODULE__).getsym($(QuoteNode(symbol))))
    return quote
        local st = Ref{Cint}(-1)
        ccall($sym, Cvoid, (Ref{Cint},), st)
        check_status(st)
    end |> esc
end
macro cfm_call_check(symbol, argTypes, args...)
    sym = :($(@__MODULE__).getsym($(QuoteNode(symbol))))
    pushfirst!(argTypes.args, Ref{Cint})
    call_expr = Expr(:call, :ccall, sym, :Cvoid, argTypes, :st, args...)
    return quote
        local st = Ref{Cint}(-1)
        $call_expr
        check_status(st)
    end |> esc
end

cfmferr() = (
    errtxt = repeat(' ', 200);
    @cfm_call_check(cfmferr, (Cstring,), errtxt);
    errtxt
)
